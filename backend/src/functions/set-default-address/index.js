/**
 * Lambda function to set default address
 * دالة لتعيين العنوان الافتراضي
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ 
    region: 'us-east-1'
});
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
 * Clear existing default addresses for user
 */
async function clearDefaultAddresses(userId) {
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
        
        // Update each default address to not be default
        for (const address of result.Items) {
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
        
        console.log(`✅ Cleared ${result.Items.length} default addresses for user ${userId}`);
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
        console.log('🏠 Address ID to set as default:', addressId);

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
                    message: 'غير مخول لتعديل هذا العنوان'
                })
            };
        }

        // Check if this address is already default
        const isAlreadyDefault = existingResult.Item.isDefault === 'true' || existingResult.Item.isDefault === true;
        
        if (isAlreadyDefault) {
            return {
                statusCode: 200,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: true,
                    message: 'هذا العنوان افتراضي بالفعل',
                    data: {
                        address_id: addressId,
                        is_default: true
                    }
                })
            };
        }

        // Clear existing default addresses
        await clearDefaultAddresses(userId);

        // Set this address as default
        const updateParams = {
            TableName: TABLE_NAME,
            Key: { addressId: addressId },
            UpdateExpression: 'SET isDefault = :isDefault, updatedAt = :updatedAt',
            ExpressionAttributeValues: {
                ':isDefault': 'true',
                ':updatedAt': new Date().toISOString()
            },
            ReturnValues: 'ALL_NEW'
        };

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
            is_default: true,
            building_number: updatedAddress.buildingNumber || null,
            floor_number: updatedAddress.floorNumber || null,
            apartment_number: updatedAddress.apartmentNumber || null,
            phone_number: updatedAddress.phoneNumber || null,
            created_at: updatedAddress.createdAt || new Date().toISOString(),
            updated_at: updatedAddress.updatedAt
        };

        console.log(`✅ Address ${addressId} set as default successfully`);

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                message: 'تم تعيين العنوان الافتراضي بنجاح',
                data: responseData
            })
        };

    } catch (error) {
        console.error('💥 Error setting default address:', error);
        
        return {
            statusCode: 500,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في تعيين العنوان الافتراضي',
                error: error.message
            })
        };
    }
};
