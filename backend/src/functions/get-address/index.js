/**
 * Lambda function to get a specific address
 * دالة للحصول على عنوان محدد
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

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
 * Build full address from components if needed
 */
function buildFullAddress(address) {
    // إذا كان العنوان الكامل موجود، استخدمه مباشرة
    if (address.fullAddress && address.fullAddress.trim()) {
        return address.fullAddress.trim();
    }
    
    // ✅ إذا كان detailedAddress موجود، استخدمه (من Google Places)
    if (address.detailedAddress && address.detailedAddress.trim()) {
        return address.detailedAddress.trim();
    }
    
    // وإلا، ابنِ العنوان من الأجزاء (مع تجاهل placeholders)
    const parts = [];
    
    // ✅ تجاهل القيم التي تساوي '-' أو فارغة
    if (address.province && address.province.trim() !== '-') parts.push(address.province);
    if (address.district && address.district.trim() !== '-') parts.push(address.district);
    if (address.neighborhood && address.neighborhood.trim() !== '-') parts.push(address.neighborhood);
    if (address.landmark) parts.push(`قرب ${address.landmark}`);
    
    return parts.join('، ') || 'عنوان غير محدد';
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

        // Get address from DynamoDB
        const getParams = {
            TableName: TABLE_NAME,
            Key: { addressId: addressId }
        };

        console.log('🔍 DynamoDB Get Parameters:', JSON.stringify(getParams, null, 2));

        const result = await dynamodb.send(new GetCommand(getParams));
        
        if (!result.Item) {
            return {
                statusCode: 404,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'العنوان غير موجود'
                })
            };
        }

        const address = result.Item;

        // Verify that this address belongs to the requesting user
        if (address.userId !== userId) {
            return {
                statusCode: 403,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'غير مخول للوصول إلى هذا العنوان'
                })
            };
        }

        // Build full address if not already set
        if (!address.fullAddress) {
            address.fullAddress = buildFullAddress(address);
        }

        // Format response
        const responseData = {
            id: address.addressId,
            user_id: address.userId,
            name: address.name || 'عنوان غير محدد',
            province: address.province || '',
            district: address.district || '',
            neighborhood: address.neighborhood || '',
            landmark: address.landmark || '',
            detailed_address: address.detailedAddress || null,
            full_address: address.fullAddress,
            latitude: address.latitude || null,
            longitude: address.longitude || null,
            address_type: address.addressType || 'other',
            is_default: address.isDefault === 'true' || address.isDefault === true,
            building_number: address.buildingNumber || null,
            floor_number: address.floorNumber || null,
            apartment_number: address.apartmentNumber || null,
            phone_number: address.phoneNumber || null,
            created_at: address.createdAt || new Date().toISOString(),
            updated_at: address.updatedAt || new Date().toISOString()
        };

        console.log('✅ Address found:', addressId);

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                message: 'تم جلب العنوان بنجاح',
                data: responseData
            })
        };

    } catch (error) {
        console.error('💥 Error getting address:', error);
        
        return {
            statusCode: 500,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في جلب العنوان',
                error: error.message
            })
        };
    }
};
