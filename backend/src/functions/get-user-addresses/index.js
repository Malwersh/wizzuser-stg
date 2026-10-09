/**
 * Lambda function to get user addresses
 * دالة للحصول على عناوين المستخدم
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');

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
 * Validate user ID format
 */
function validateUserId(userId) {
    if (!userId || typeof userId !== 'string') {
        return { valid: false, error: 'معرف المستخدم مطلوب' };
    }
    
    if (userId.length < 3) {
        return { valid: false, error: 'معرف المستخدم غير صالح' };
    }
    
    return { valid: true };
}

/**
 * Build full address from components
 */
function buildFullAddress(address) {
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

        // Extract user ID from path parameters
        const userId = event.pathParameters?.user_id;
        console.log('👤 Requested user ID:', userId);

        // Validate user ID
        const userIdValidation = validateUserId(userId);
        if (!userIdValidation.valid) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: userIdValidation.error
                })
            };
        }

        // Query addresses for this user
        const queryParams = {
            TableName: TABLE_NAME,
            IndexName: 'userId-index',
            KeyConditionExpression: 'userId = :userId',
            ExpressionAttributeValues: {
                ':userId': userId
            },
            ScanIndexForward: false // Get newest first
        };

        console.log('🔍 DynamoDB Query Parameters:', JSON.stringify(queryParams, null, 2));

        let result;
        try {
            result = await dynamodb.send(new QueryCommand(queryParams));
            console.log('📊 DynamoDB Query Result:', JSON.stringify(result, null, 2));
        } catch (queryError) {
            // If GSI query fails, fall back to scan
            console.log('⚠️ GSI query failed, falling back to scan:', queryError.message);
            const scanParams = {
                TableName: TABLE_NAME,
                FilterExpression: 'userId = :userId',
                ExpressionAttributeValues: {
                    ':userId': userId
                }
            };
            result = await dynamodb.send(new ScanCommand(scanParams));
            console.log('📊 DynamoDB Scan Result:', JSON.stringify(result, null, 2));
        }

        // Process and format addresses
        const addresses = result.Items.map(address => {
            // Build full address if not already set
            if (!address.fullAddress) {
                address.fullAddress = buildFullAddress(address);
            }

            // Convert isDefault from string to boolean if needed
            let isDefault = false;
            if (typeof address.isDefault === 'string') {
                isDefault = address.isDefault === 'true';
            } else if (typeof address.isDefault === 'boolean') {
                isDefault = address.isDefault;
            }

            return {
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
                is_default: isDefault,
                building_number: address.buildingNumber || null,
                floor_number: address.floorNumber || null,
                apartment_number: address.apartmentNumber || null,
                phone_number: address.phoneNumber || null,
                created_at: address.createdAt || new Date().toISOString(),
                updated_at: address.updatedAt || new Date().toISOString()
            };
        });

        // Find default address
        const defaultAddress = addresses.find(addr => addr.is_default);

        console.log(`✅ Found ${addresses.length} addresses for user ${userId}`);
        console.log('🎯 Default address:', defaultAddress?.id || 'none');

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                message: `تم جلب ${addresses.length} عنوان بنجاح`,
                data: {
                    addresses: addresses,
                    total: addresses.length,
                    default_address_id: defaultAddress?.id || null
                }
            })
        };

    } catch (error) {
        console.error('💥 Error getting user addresses:', error);
        
        return {
            statusCode: 500,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في جلب العناوين',
                error: error.message
            })
        };
    }
};
