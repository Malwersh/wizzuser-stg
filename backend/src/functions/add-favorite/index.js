/**
 * Lambda function to add item to favorites
 * دالة لإضافة عنصر إلى المفضلة
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const {writeContext}=require('../create-order/guarded-write');

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
 * Generate unique favorite ID
 */
function generateFavoriteId() {
    return 'fav_' + Date.now() + '_' + Math.random().toString(36).substring(2, 15);
}

/**
 * Check if item is already in favorites
 */
async function isAlreadyFavorite(userId, businessId, favoriteType) {
    try {
        const params = {
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

        const result = await dynamodb.send(new QueryCommand(params));
        return result.Items && result.Items.length > 0;
    } catch (error) {
        console.error('Error checking favorite status:', error);
        return false;
    }
}

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
    console.log('Add favorite request', {requestId:event.requestContext?.requestId});

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
        
        console.log('👤 User ID:', userId);

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

        console.log('📋 Request data:', JSON.stringify(requestData, null, 2));

        // Validate required fields
        const { businessId, businessName, businessImage, businessCategory, favoriteType = 'restaurant' } = requestData;

        if (!businessId || !businessName) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المطعم واسم المطعم مطلوبان'
                })
            };
        }

        // Check if already favorite
        const alreadyFavorite = await isAlreadyFavorite(userId, businessId, favoriteType);
        if (alreadyFavorite) {
            return {
                statusCode: 409,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'هذا المطعم موجود في المفضلة بالفعل'
                })
            };
        }

        // Create favorite item
        const favoriteId = generateFavoriteId();
        const now = new Date().toISOString();

        const favoriteItem = {
            favoriteId: favoriteId,
            userId: userId,
            businessId: businessId,
            businessName: businessName,
            businessImage: businessImage || null,
            businessCategory: businessCategory || null,
            favoriteType: favoriteType,
            createdAt: now,
            updatedAt: now
        };

        // Save to DynamoDB with conditional expression to prevent duplicates
        const putParams = {
            TableName: TABLE_NAME,
            Item: favoriteItem,
            ConditionExpression: 'attribute_not_exists(favoriteId) AND NOT (userId = :checkUserId AND businessId = :checkBusinessId)',
            ExpressionAttributeValues: {
                ':checkUserId': userId,
                ':checkBusinessId': businessId
            }
        };

        await write('Put',putParams);

        // Format response
        const responseData = {
            id: favoriteId,
            user_id: userId,
            business_id: businessId,
            business_name: businessName,
            business_image: businessImage,
            business_category: businessCategory,
            favorite_type: favoriteType,
            created_at: now,
            updated_at: now
        };

        console.log(`✅ Added to favorites successfully: ${favoriteId}`);

        return {
            statusCode: 201,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                message: 'تم إضافة المطعم إلى المفضلة بنجاح',
                data: responseData
            })
        };

    } catch (error) {
        console.error('💥 Error adding to favorites:', error);
        
        return {
            statusCode: error.statusCode || (error.name==='TransactionCanceledException'?409:500),
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في إضافة المطعم إلى المفضلة',
                error: error.message
            })
        };
    }
};
