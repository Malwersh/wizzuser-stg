/**
 * Lambda function to create a new address
 * دالة لإنشاء عنوان جديد
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, ScanCommand, TransactWriteCommand, PutCommand, QueryCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const crypto = require('crypto');
const {writeContext,commitBook,fullAddress319}=require('../shared/address-book-319');

// Function to generate UUID-like string using crypto
function generateUUID() {
    return 'addr_' + crypto.randomBytes(16).toString('hex').slice(0, 32);
}

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
 * Validate required address data
 */
function validateAddressData(data) {
    const errors = [];
    
    if (!data.name || data.name.trim().length < 2) {
        errors.push('اسم العنوان مطلوب ويجب أن يكون أكثر من حرفين');
    }
    
    if (!data.province || data.province.trim().length < 1) {
        errors.push('المحافظة مطلوبة');
    }
    
    // ✅ السماح بـ placeholders مثل '-' للقضاء والحي
    if (!data.district || data.district.trim().length < 1) {
        errors.push('القضاء/الناحية مطلوب');
    }
    
    if (!data.neighborhood || data.neighborhood.trim().length < 1) {
        errors.push('الحي مطلوب');
    }
    
    if (!data.landmark || data.landmark.trim().length < 2) {
        errors.push('أقرب نقطة دالة مطلوبة');
    }
    
    // Validate address type (optional, default to 'other' if not provided)
    const validTypes = ['home', 'work', 'other'];
    if (data.address_type && !validTypes.includes(data.address_type)) {
        errors.push('نوع العنوان غير صالح');
    }
    
    return errors;
}

/**
 * Build full address from components
 */
function buildFullAddress(data) {
    // إذا كان العنوان الكامل موجود، استخدمه مباشرة
    if (data.fullAddress && data.fullAddress.trim()) {
        return data.fullAddress.trim();
    }
    
    // إذا كان detailed_address موجود ويحتوي على بيانات حقيقية (ليس "-")
    // استخدمه كمصدر رئيسي (يحتوي على: البلد، المحافظة، القضاء، الحي)
    if (data.detailed_address && 
        data.detailed_address.trim() && 
        data.detailed_address.trim() !== '-') {
        
        // تنظيف العنوان من كلمة "محافظة"
        let cleanedAddress = data.detailed_address
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
        if (data.landmark && 
            data.landmark.trim() && 
            data.landmark.trim() !== '-') {
            reorderedParts.push(`قرب ${data.landmark}`);
        }
        
        return reorderedParts.join('، ');
    }
    
    // وإلا، ابنِ العنوان من الأجزاء (للعناوين القديمة)
    const parts = [];
    
    if (data.province && data.province !== '-') parts.push(data.province);
    if (data.district && data.district !== '-') parts.push(data.district);
    if (data.neighborhood && data.neighborhood !== '-') parts.push(data.neighborhood);
    if (data.landmark && data.landmark !== '-') parts.push(`قرب ${data.landmark}`);
    
    return parts.join('، ') || 'عنوان غير محدد';
}

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
    console.log('Create address request', {requestId:event.requestContext?.requestId});

    try {
        // Handle CORS preflight
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: CORS_HEADERS,
                body: JSON.stringify({ message: 'CORS preflight successful' })
            };
        }

        // Extract user ID from path parameters
        const userId = event.pathParameters?.user_id;
        console.log('👤 Creating address for user ID:', userId);

        if (!userId) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المستخدم مطلوب'
                })
            };
        }

        const write=await writeContext(dynamodb,event,userId);
        // Parse request body
        let requestData;
        try {
            requestData = JSON.parse(event.body || '{}');
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



        // Validate address data
        const validationErrors = validateAddressData(requestData);
        if (validationErrors.length > 0) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'بيانات العنوان غير صالحة',
                    errors: validationErrors
                })
            };
        }

        if(requestData.save_to_address_book!==undefined&&typeof requestData.save_to_address_book!=='boolean')throw Object.assign(Error('INVALID_ADDRESS_STORAGE'),{statusCode:400});
        const checkoutOnly=requestData.save_to_address_book===false;
        if(requestData.save_to_address_book!==undefined){
          const meaningful=value=>typeof value==='string'&&value.trim().length>=2&&!['-','غير محدد','موقع محدد من الخريطة'].includes(value.trim());
          if(!meaningful(requestData.neighborhood)||!meaningful(requestData.landmark))throw Object.assign(Error('DELIVERY_DETAILS_REQUIRED'),{statusCode:400});
          if(checkoutOnly)requestData.is_default=false;
        }
        const idempotency=require('./idempotency-315');
        const requestIntent=idempotency.intent(userId,requestData);
        const replay=await idempotency.replay({db:dynamodb,GetCommand,table:TABLE_NAME,userId,intent:requestIntent,data:requestData});
        if(replay)return createdResponse(replay,true);

        const regionApi=require('../../utils/customer-regions-313').create({db:dynamodb,sdk:{GetCommand,QueryCommand,ScanCommand},tables:{regions:process.env.REGIONS_TABLE,derived:process.env.REGIONS_DERIVED_TABLE,index:process.env.REGION_INDEX_TABLE}});
        const verifiedRegion=await regionApi.resolve(requestData.latitude,requestData.longitude);
        if(requestData.save_to_address_book!==undefined&&requestData.region_id&&requestData.region_id!==verifiedRegion.regionId)throw Object.assign(Error('REGION_SELECTION_CHANGED'),{statusCode:400});
        if(requestData.save_to_address_book!==undefined){
          const path=verifiedRegion.path;
          requestData.province=path[1].base.name_ar||path[1].base.name;
          requestData.district=path[2].base.name_ar||path[2].base.name;
          requestData.region_level=3;requestData.region_is_active=true;
        }
        requestData.region_id=verifiedRegion.regionId;requestData.region_name_ar=verifiedRegion.regionNameAr;
        // Generate address ID and timestamps
        const addressId = requestIntent?.addressId || generateUUID();
        const now = new Date().toISOString();
        
        // Build full address
        const fullAddress = fullAddress319({...requestData,regionNameAr:requestData.region_name_ar});

        // Create address item
        const addressItem = {
            ...(requestIntent?{creationRequestHash:requestIntent.hash}:{}),
            ...(checkoutOnly?{recordType:'CHECKOUT_ADDRESS',checkoutExpiresAt:Math.floor(Date.now()/1000)+7*24*60*60}:{}),
            addressId: addressId,
            userId: userId,
            name: requestData.name.trim(),
            province: requestData.province.trim(),
            district: requestData.district.trim(),
            neighborhood: requestData.neighborhood.trim(),
            landmark: requestData.landmark.trim(),
            detailedAddress: requestData.detailed_address?.trim() || null,
            fullAddress: fullAddress,
            latitude: requestData.latitude ?? null,
            longitude: requestData.longitude ?? null,
            addressType: requestData.address_type || 'other',
            isDefault: requestData.is_default === true ? 'true' : 'false', // Store as string for GSI
            buildingNumber: requestData.building_number?.trim() || null,
            floorNumber: requestData.floor_number?.trim() || null,
            apartmentNumber: requestData.apartment_number?.trim() || null,
            phoneNumber: requestData.phone_number?.trim() || null,
            // Region System Data
            regionId: requestData.region_id || null,
            regionName: requestData.region_name || null,
            regionNameAr: requestData.region_name_ar || null,
            regionLevel: requestData.region_level || null,
            regionIsActive: requestData.region_is_active || null,
            deliveryFee: requestData.delivery_fee || null,
            minimumOrder: requestData.minimum_order || null,
            maxDistanceKm: requestData.max_distance_km || null,
            pricePerKm: requestData.price_per_km || null,
            createdAt: now,
            updatedAt: now
        };

        console.log('💾 Creating address item:', JSON.stringify(addressItem, null, 2));

        // Save to DynamoDB
        const putParams = {
            TableName: TABLE_NAME,
            Item: addressItem
        };

        putParams.ConditionExpression='attribute_not_exists(addressId)';
        await commitBook({db:dynamodb,write,operation:{Put:putParams},makeDefault:requestData.is_default===true,regionChecks:regionApi.checks(verifiedRegion.path)});

        console.log('✅ Address created successfully:', addressId);

        return createdResponse(addressItem);

    } catch (error) {
        console.error('💥 Error creating address:', error);

        return {
            statusCode: error.statusCode || (error.name==='TransactionCanceledException'?409:500),
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: error.code==='ADDRESS_LIMIT_REACHED'?'لا يمكن إضافة أكثر من 10 عناوين':error.code==='ADDRESS_BOOK_CHANGED'?'تغيّرت العناوين. أعد المحاولة للتحقق من الحفظ.':'تعذر تأكيد حفظ العنوان. أعد المحاولة.',
                code:error.code||null,
                error: error.message
            })
        };
    }
};

function addressData(addressItem) {
    return {
            id: addressItem.addressId,
            user_id: addressItem.userId,
            name: addressItem.name,
            province: addressItem.province,
            district: addressItem.district,
            neighborhood: addressItem.neighborhood,
            landmark: addressItem.landmark,
            detailed_address: addressItem.detailedAddress,
            full_address: addressItem.fullAddress,
            latitude: addressItem.latitude,
            longitude: addressItem.longitude,
            address_type: addressItem.addressType,
            is_default: addressItem.isDefault === 'true',
            building_number: addressItem.buildingNumber,
            floor_number: addressItem.floorNumber,
            apartment_number: addressItem.apartmentNumber,
            phone_number: addressItem.phoneNumber,
            // Region data
            region_id: addressItem.regionId,
            region_name: addressItem.regionName,
            region_name_ar: addressItem.regionNameAr,
            region_level: addressItem.regionLevel,
            region_is_active: addressItem.regionIsActive,
            delivery_fee: addressItem.deliveryFee,
            minimum_order: addressItem.minimumOrder,
            max_distance_km: addressItem.maxDistanceKm,
            price_per_km: addressItem.pricePerKm,
            created_at: addressItem.createdAt,
            updated_at: addressItem.updatedAt
        };

}
function createdResponse(item,reused=false){return {statusCode:201,headers:CORS_HEADERS,body:JSON.stringify({success:true,message:reused?'العنوان محفوظ مسبقًا':'تم إنشاء العنوان بنجاح',data:addressData(item)})};}
