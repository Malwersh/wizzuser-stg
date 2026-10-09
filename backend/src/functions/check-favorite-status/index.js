/**
 * Lambda function to check if item is in favorites
 * دالة لفحص حالة المفضلة لعنصر معين
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
        const businessId = event.pathParameters?.business_id;
        const favoriteType = event.queryStringParameters?.type || 'restaurant'; // Default to restaurant
        
        console.log('👤 User ID:', userId);
        console.log('🏢 Business ID:', businessId);
        console.log('🎯 Favorite Type:', favoriteType);

        if (!userId || !businessId) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المستخدم ومعرف المطعم مطلوبان'
                })
            };
        }

        // Check if item is in favorites
        const queryParams = {
            TableName: TABLE_NAME,
            IndexName: 'userId-businessId-index',
            KeyConditionExpression: 'userId = :userId AND businessId = :businessId',
            FilterExpression: 'favoriteType = :favoriteType',
            ExpressionAttributeValues: {
                ':userId': userId,
                ':businessId': businessId,
                ':favoriteType': favoriteType
            }
        };

        const result = await dynamodb.send(new QueryCommand(queryParams));
        
        const isFavorite = result.Items && result.Items.length > 0;
        const favoriteData = isFavorite ? result.Items[0] : null;

        console.log(`📊 Is favorite: ${isFavorite} for business ${businessId}`);

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                data: {
                    is_favorite: isFavorite,
                    favorite_id: favoriteData ? favoriteData.favoriteId : null,
                    business_id: businessId,
                    user_id: userId,
                    favorite_type: favoriteType
                }
            })
        };

    } catch (error) {
        console.error('💥 Error checking favorite status:', error);
        
        return {
            statusCode: 500,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في فحص حالة المفضلة',
                error: error.message
            })
        };
    }
};
