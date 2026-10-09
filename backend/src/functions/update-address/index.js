/**
 * Lambda function to update an address
 * دالة لتحديث عنوان
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');

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
 * Build full address from components
 * Format: Country, Province, District, Neighborhood, Landmark
 */
function buildFullAddress(addressData) {
    // إذا كان العنوان الكامل موجود، استخدمه مباشرة
    if (addressData.fullAddress && addressData.fullAddress.trim()) {
        return addressData.fullAddress.trim();
    }
    
    // إذا كان detailed_address موجود ويحتوي على بيانات حقيقية (ليس "-")
    // استخدمه كمصدر رئيسي (يحتوي على: البلد، المحافظة، القضاء، الحي)
    if (addressData.detailed_address && 
        addressData.detailed_address.trim() && 
        addressData.detailed_address.trim() !== '-') {
        
        // تنظيف العنوان من كلمة "محافظة"
        let cleanedAddress = addressData.detailed_address
            .replace(/\s+محافظة/g, '')
            .replace(/محافظة\s+/g, '');
        
        // تقسيم العنوان إلى أجزاء لإعادة ترتيبها
        const addressParts = cleanedAddress.split('، ').map(p => p.trim()).filter(p => p);
        
        // إعادة ترتيب: العراق (آخر جزء) يأتي أولاً، ثم المحافظة، ثم الباقي
        const reorderedParts = [];
        
        if (addressParts.length > 0) {
            // البلد (آخر جزء) يأتي أولاً
            const country = addressParts[addressParts.length - 1];
            reorderedParts.push(country);
            
            // المحافظة (قبل الأخير) تأتي ثانياً
            if (addressParts.length > 1) {
                const province = addressParts[addressParts.length - 2];
                reorderedParts.push(province);
            }
            
            // الباقي (الناحية/القضاء، الحي) بنفس ترتيبهم
            if (addressParts.length > 2) {
                for (let i = 0; i < addressParts.length - 2; i++) {
                    reorderedParts.push(addressParts[i]);
                }
            }
        }
        
        // أضف landmark في النهاية إذا كان موجود وليس "-"
        if (addressData.landmark && 
            addressData.landmark.trim() && 
            addressData.landmark.trim() !== '-') {
            reorderedParts.push(`قرب ${addressData.landmark}`);
        }
        
        return reorderedParts.join('، ');
    }
    
    // وإلا، ابنِ العنوان من الأجزاء (للعناوين القديمة)
    const parts = [];
    
    if (addressData.province && addressData.province !== '-') parts.push(addressData.province);
    if (addressData.district && addressData.district !== '-') parts.push(addressData.district);
    if (addressData.neighborhood && addressData.neighborhood !== '-') parts.push(addressData.neighborhood);
    if (addressData.landmark && addressData.landmark !== '-') parts.push(`قرب ${addressData.landmark}`);
    
    return parts.join('، ') || 'عنوان غير محدد';
}

/**
 * Clear existing default addresses for user
 */
async function clearDefaultAddresses(userId, excludeAddressId) {
    try {
        // First, find all default addresses for this user
        const queryParams = {
            TableName: TABLE_NAME,
            IndexName: 'userId-isDefault-index',
            KeyConditionExpression: 'userId = :userId AND isDefault = :isDefault',
            ExpressionAttributeValues: {
                ':userId': userId,
                ':isDefault': 'true'
            }
        };

        const result = await dynamodb.send(new QueryCommand(queryParams));
        
        // Update each default address to not be default (except the one being updated)
        for (const address of result.Items) {
            if (address.addressId !== excludeAddressId) {
                const updateParams = {
                    TableName: TABLE_NAME,
                    Key: { addressId: address.addressId },
                    UpdateExpression: 'SET isDefault = :isDefault, updatedAt = :updatedAt',
                    ExpressionAttributeValues: {
                        ':isDefault': 'false',
                        ':updatedAt': new Date().toISOString()
                    }
                };
                
                await dynamodb.send(new UpdateCommand(updateParams));
            }
        }
        
        console.log(`✅ Cleared default addresses for user ${userId}`);
    } catch (error) {
        console.error('❌ Error clearing default addresses:', error);
        throw error;
    }
}

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
    console.log('📥 Incoming event:', JSON.stringify(event, null, 2));

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
        
        console.log('👤 User ID:', userId);
        console.log('🏠 Address ID:', addressId);

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

        console.log('📋 Update data:', JSON.stringify(updateData, null, 2));

        // First, verify that the address exists and belongs to the user
        const getParams = {
            TableName: TABLE_NAME,
            Key: { addressId: addressId }
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

        if (existingResult.Item.userId !== userId) {
            return {
                statusCode: 403,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'غير مخول لتحديث هذا العنوان'
                })
            };
        }

        // Build update expression
        const updateExpressions = [];
        const expressionAttributeNames = {};
        const expressionAttributeValues = {};

        // Always update the updatedAt field
        updateExpressions.push('#updatedAt = :updatedAt');
        expressionAttributeNames['#updatedAt'] = 'updatedAt';
        expressionAttributeValues[':updatedAt'] = new Date().toISOString();

        // Check if setting as default
        if (updateData.is_default === true) {
            await clearDefaultAddresses(userId, addressId);
        }

        // Build update expressions for provided fields
        const updatableFields = {
            'name': 'name',
            'province': 'province', 
            'district': 'district',
            'neighborhood': 'neighborhood',
            'landmark': 'landmark',
            'detailed_address': 'detailedAddress',
            'latitude': 'latitude',
            'longitude': 'longitude',
            'address_type': 'addressType',
            'is_default': 'isDefault',
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
            
            const newFullAddress = buildFullAddress(mergedData);
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

        const result = await dynamodb.send(new UpdateCommand(updateParams));
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
            latitude: updatedAddress.latitude || null,
            longitude: updatedAddress.longitude || null,
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
            statusCode: 500,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في تحديث العنوان',
                error: error.message
            })
        };
    }
};
