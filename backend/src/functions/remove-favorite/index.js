/**
 * Lambda function to remove item from favorites
 * دالة لحذف عنصر من المفضلة
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, DeleteCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');

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
 * Main Lambda handler
 */
exports.handler = async (event) => {
    console.log('Account mutation request', {requestId:event.requestContext?.requestId});

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
        const favoriteId = event.pathParameters?.favorite_id;
        
        console.log('👤 User ID:', userId);
        console.log('⭐ Favorite ID:', favoriteId);

        if (!userId || !favoriteId) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المستخدم ومعرف المفضلة مطلوبان'
                })
            };
        }

        // First, verify that the favorite exists and belongs to the user
        const write=await writeContext(dynamodb,event,userId);
        const getParams = {
            TableName: TABLE_NAME,
            Key: { favoriteId: favoriteId }
        };

        const existingResult = await dynamodb.send(new GetCommand(getParams));
        
        if (!existingResult.Item) {
            return {
                statusCode: 404,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'المفضلة غير موجودة'
                })
            };
        }

        if (existingResult.Item.userId !== userId) {
            return {
                statusCode: 403,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'غير مخول لحذف هذه المفضلة'
                })
            };
        }

        // Delete the favorite
        const deleteParams = {
            TableName: TABLE_NAME,
            Key: { favoriteId: favoriteId }
        };

        await write('Delete',{...deleteParams,ConditionExpression:'attribute_exists(favoriteId) AND userId = :owner',ExpressionAttributeValues:{':owner':userId}});

        console.log(`✅ Removed from favorites successfully: ${favoriteId}`);

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                message: 'تم حذف المطعم من المفضلة بنجاح'
            })
        };

    } catch (error) {
        console.error('💥 Error removing from favorites:', error);
        
        return {
            statusCode: error.statusCode || (error.name==='TransactionCanceledException'?409:500),
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في حذف المطعم من المفضلة',
                error: error.message
            })
        };
    }
};
