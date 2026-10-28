/**
 * Lambda function to update an address
 * دالة لتحديث عنوان
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, ScanCommand, TransactWriteCommand, UpdateCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const {writeContext,commitBook,fullAddress319}=require('../shared/address-book-319');

const client = new DynamoDBClient({});
const dynamodb = DynamoDBDocumentClient.from(client);

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

const TABLE_NAME = requireEnv('ADDRESSES_TABLE');

/**
 * CORS headers for responses
 */
const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'Content-Type': 'application/json; charset=utf-8'
};

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
    console.log('Update address request', {requestId:event.requestContext?.requestId});

    try {
        // Handle CORS preflight
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: CORS_HEADERS,
                body: JSON.stringify({ message: 'CORS preflight successful' })
            };
        }

        // Extract parameters
        const userId = event.pathParameters?.user_id;
        const addressId = event.pathParameters?.address_id;
        


        if (!userId || !addressId) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المستخدم ومعرف العنوان مطلوبان'
                })
            };
        }

        const write=await writeContext(dynamodb,event,userId);
        // Parse request body
        let updateData;
        try {
            updateData = JSON.parse(event.body || '{}');
        } catch (parseError) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'بيانات الطلب غير صالحة'
                })
            };
        }



        // First, verify that the address exists and belongs to the user
        const getParams = {
            TableName: TABLE_NAME,
            Key: { addressId: addressId }, ConsistentRead:true
        };

        const existingResult = await dynamodb.send(new GetCommand(getParams));
        
        if (!existingResult.Item) {
            return {
                statusCode: 404,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'العنوان غير موجود'
                })
            };
        }

        if (existingResult.Item.userId !== userId || existingResult.Item.recordType==='CHECKOUT_ADDRESS') {
            return {
                statusCode: 403,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'غير مخول لتحديث هذا العنوان'
                })
            };
        }

        for (const key of ['neighborhood','landmark']) {
            const value=updateData[key]??existingResult.Item[key];
            if(typeof value!=='string'||value.trim().length<2||['-','موقع محدد من الخريطة'].includes(value.trim()))return{statusCode:400,headers:CORS_HEADERS,body:JSON.stringify({success:false,code:'ADDRESS_DETAILS_REQUIRED',message:'أدخل اسم الحي وأقرب نقطة دالة بشكل واضح.'})};
        }
        // Build update expression
        const updateExpressions = [];
        const expressionAttributeNames = {};
        const expressionAttributeValues = {};

        // Always update the updatedAt field
        updateExpressions.push('#updatedAt = :updatedAt');
        expressionAttributeNames['#updatedAt'] = 'updatedAt';
        expressionAttributeValues[':updatedAt'] = new Date().toISOString();

        const regionApi=require('../../utils/customer-regions-313').create({db:dynamodb,sdk:{GetCommand,QueryCommand,ScanCommand},tables:{regions:process.env.REGIONS_TABLE,derived:process.env.REGIONS_DERIVED_TABLE,index:process.env.REGION_INDEX_TABLE}});
        const verifiedRegion=await regionApi.resolve(updateData.latitude??existingResult.Item.latitude,updateData.longitude??existingResult.Item.longitude);
        updateData.region_id=verifiedRegion.regionId;updateData.region_name_ar=verifiedRegion.regionNameAr;
        updateData.province=verifiedRegion.path[1].base.name_ar||verifiedRegion.path[1].base.name;updateData.district=verifiedRegion.path[2].base.name_ar||verifiedRegion.path[2].base.name;
        for (const key of ['neighborhood','landmark']) {
            const value=updateData[key]??existingResult.Item[key];
            if(typeof value!=='string'||value.trim().length<2||['-','موقع محدد من الخريطة'].includes(value.trim()))return{statusCode:400,headers:CORS_HEADERS,body:JSON.stringify({success:false,code:'ADDRESS_DETAILS_REQUIRED',message:'أدخل اسم الحي وأقرب نقطة دالة بشكل واضح.'})};
        }
        // Build update expressions for provided fields
        const updatableFields = {
            'name': 'name',
            'province': 'province', 
            'district': 'district',
            'neighborhood': 'neighborhood',
            'landmark': 'landmark',
            'detailed_address': 'detailedAddress',
            'region_id': 'regionId',
            'region_name_ar': 'regionNameAr',
            'latitude': 'latitude',
            'longitude': 'longitude',
            'address_type': 'addressType',
            'building_number': 'buildingNumber',
            'floor_number': 'floorNumber',
            'apartment_number': 'apartmentNumber',
            'phone_number': 'phoneNumber'
        };

        for (const [requestField, dbField] of Object.entries(updatableFields)) {
            if (updateData.hasOwnProperty(requestField)) {
                let value = updateData[requestField];
                
                // Handle special cases
                if (requestField === 'is_default') {
                    value = value === true ? 'true' : 'false';
                } else if (typeof value === 'string') {
                    value = value.trim() || null;
                }
                
                updateExpressions.push(`#${dbField} = :${dbField}`);
                expressionAttributeNames[`#${dbField}`] = dbField;
                expressionAttributeValues[`:${dbField}`] = value;
            }
        }

        // Check if we need to rebuild full address
        const addressFieldsChanged = ['province', 'district', 'neighborhood', 'landmark', 'detailed_address']
            .some(field => updateData.hasOwnProperty(field));

        if (addressFieldsChanged) {
            // Get current data and merge with updates
            const currentAddress = existingResult.Item;
            const mergedData = {
                province: updateData.province || currentAddress.province,
                district: updateData.district || currentAddress.district,
                neighborhood: updateData.neighborhood || currentAddress.neighborhood,
                landmark: updateData.landmark || currentAddress.landmark,
                detailed_address: updateData.detailed_address || currentAddress.detailedAddress
            };
            
            const newFullAddress = fullAddress319({...mergedData,regionNameAr:verifiedRegion.regionNameAr},currentAddress);
            updateExpressions.push('#fullAddress = :fullAddress');
            expressionAttributeNames['#fullAddress'] = 'fullAddress';
            expressionAttributeValues[':fullAddress'] = newFullAddress;
        }

        if (updateExpressions.length === 1) { // Only updatedAt
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'لا توجد بيانات للتحديث'
                })
            };
        }

        // Perform update
        const updateParams = {
            TableName: TABLE_NAME,
            Key: { addressId: addressId },
            UpdateExpression: `SET ${updateExpressions.join(', ')}`,
            ExpressionAttributeNames: expressionAttributeNames,
            ExpressionAttributeValues: expressionAttributeValues,
            ReturnValues: 'ALL_NEW'
        };

        console.log('🔄 DynamoDB Update Parameters:', JSON.stringify(updateParams, null, 2));

        updateParams.ConditionExpression='attribute_exists(addressId) AND userId = :owner';
        updateParams.ExpressionAttributeValues[':owner']=userId;
        const checkedUpdate={...updateParams};delete checkedUpdate.ReturnValues;
        await commitBook({db:dynamodb,write,operation:{Update:checkedUpdate},makeDefault:updateData.is_default===true,expectedAddress:existingResult.Item,regionChecks:regionApi.checks(verifiedRegion.path)});
        const result={Attributes:(await dynamodb.send(new GetCommand({TableName:TABLE_NAME,Key:{addressId},ConsistentRead:true}))).Item};
        const updatedAddress = result.Attributes;

        // Format response
        const responseData = {
            id: updatedAddress.addressId,
            user_id: updatedAddress.userId,
            name: updatedAddress.name || 'عنوان غير محدد',
            province: updatedAddress.province || '',
            district: updatedAddress.district || '',
            neighborhood: updatedAddress.neighborhood || '',
            landmark: updatedAddress.landmark || '',
            detailed_address: updatedAddress.detailedAddress || null,
            full_address: updatedAddress.fullAddress,
            region_id: updatedAddress.regionId,
            region_name_ar: updatedAddress.regionNameAr,
            latitude: updatedAddress.latitude ?? null,
            longitude: updatedAddress.longitude ?? null,
            address_type: updatedAddress.addressType || 'other',
            is_default: updatedAddress.isDefault === 'true',
            building_number: updatedAddress.buildingNumber || null,
            floor_number: updatedAddress.floorNumber || null,
            apartment_number: updatedAddress.apartmentNumber || null,
            phone_number: updatedAddress.phoneNumber || null,
            created_at: updatedAddress.createdAt || new Date().toISOString(),
            updated_at: updatedAddress.updatedAt
        };

        console.log('✅ Address updated successfully:', addressId);

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                message: 'تم تحديث العنوان بنجاح',
                data: responseData
            })
        };

    } catch (error) {
        console.error('💥 Error updating address:', error);
        
        return {
            statusCode: error.statusCode || (error.name==='TransactionCanceledException'?409:500),
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                code: error.code||error.name,
                message: error.code==='ADDRESS_BOOK_CHANGED'?'تغيّرت العناوين. حدّث القائمة وأعد المحاولة.':'تعذر تأكيد تحديث العنوان. حدّث القائمة وأعد المحاولة.'
            })
        };
    }
};
