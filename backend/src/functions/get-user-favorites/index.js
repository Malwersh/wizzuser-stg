/**
 * Lambda function to get user favorites
 * دالة لجلب مفضلات المستخدم
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamodb = DynamoDBDocumentClient.from(client);
const TABLE_NAME = process.env.FAVORITES_TABLE || 'WizzUser_favorites_dev';

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
        const favoriteType = event.queryStringParameters?.type || 'restaurant'; // Default to restaurant
        
        console.log('👤 User ID:', userId);
        console.log('🎯 Favorite Type:', favoriteType);

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

        // Query user favorites
        const queryParams = {
            TableName: TABLE_NAME,
            IndexName: 'userId-createdAt-index',
            KeyConditionExpression: 'userId = :userId',
            FilterExpression: 'favoriteType = :favoriteType',
            ExpressionAttributeValues: {
                ':userId': userId,
                ':favoriteType': favoriteType
            },
            ScanIndexForward: false // Order by createdAt descending (newest first)
        };

        const result = await dynamodb.send(new QueryCommand(queryParams));
        
        console.log(`📊 Found ${result.Items.length} favorites for user ${userId}`);

        // Format response data
        const favorites = result.Items.map(item => ({
            id: item.favoriteId,
            user_id: item.userId,
            business_id: item.businessId,
            business_name: item.businessName,
            business_image: item.businessImage,
            business_category: item.businessCategory,
            favorite_type: item.favoriteType,
            created_at: item.createdAt,
            updated_at: item.updatedAt
        }));

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                data: {
                    favorites: favorites,
                    total: favorites.length,
                    favorite_type: favoriteType
                }
            })
        };

    } catch (error) {
        console.error('💥 Error getting favorites:', error);
        
        return {
            statusCode: 500,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في جلب المفضلات',
                error: error.message
            })
        };
    }
};
