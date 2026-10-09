const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const TABLE_NAME = process.env.WIZZORDERS_TABLE || 'WizzOrders';

/**
 * Lambda handler for retrieving user orders using GSI_User
 */
exports.handler = async (event) => {
    console.log('Event received:', JSON.stringify(event, null, 2));
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    };
    
    try {
        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: headers,
                body: ''
            };
        }

        // Get user ID from path parameters
        const userId = event.pathParameters?.user_id || event.pathParameters?.userId;
        
        // Get query parameters
        const queryParams = event.queryStringParameters || {};
        const limit = parseInt(queryParams.limit) || 20;
        const status = queryParams.status;
        const guestToken = queryParams.guestToken; // Support guestToken for guest orders

        // Support both userId and guestToken
        let queryKey;
        if (guestToken) {
            // Guest order lookup using guestToken
            queryKey = guestToken;
            console.log('Retrieving orders for guest with token:', guestToken);
        } else if (userId) {
            // Registered user lookup
            queryKey = userId;
            console.log('Retrieving orders for user:', userId);
        } else {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Either userId or guestToken is required',
                    success: false
                })
            };
        }

        // Use GSI_User to query orders by userId_gsi in WizzOrders table
        let queryCommand = {
            TableName: TABLE_NAME,
            IndexName: 'GSI_User',
            KeyConditionExpression: 'userId_gsi = :userId',
            ExpressionAttributeValues: {
                ':userId': queryKey
            },
            ScanIndexForward: false, // Sort by createdAt descending (newest first)
            Limit: limit
        };

        // Add status filter if provided
        if (status) {
            if (status === 'active') {
                // Active orders (currently being processed)
                // Include both unified and legacy statuses for compatibility
                queryCommand.FilterExpression = '#status IN (:pending, :confirmed, :preparing, :ready, :onTheWay, :inKitchen, :outForDelivery)';
                queryCommand.ExpressionAttributeNames = { '#status': 'status' };
                queryCommand.ExpressionAttributeValues = {
                    ...queryCommand.ExpressionAttributeValues,
                    ':pending': 'pending',
                    ':confirmed': 'confirmed', 
                    ':preparing': 'preparing',
                    ':ready': 'ready',
                    ':onTheWay': 'on_the_way',
                    // Legacy support
                    ':inKitchen': 'in_kitchen',
                    ':outForDelivery': 'out_for_delivery'
                };
            } else if (status === 'completed') {
                // Completed orders (including all final states)
                queryCommand.FilterExpression = '#status IN (:delivered, :cancelled, :failed, :rejected, :expired, :canceledByUser, :canceledByStore, :canceledBySystem)';
                queryCommand.ExpressionAttributeNames = { '#status': 'status' };
                queryCommand.ExpressionAttributeValues = {
                    ...queryCommand.ExpressionAttributeValues,
                    ':delivered': 'delivered',
                    ':cancelled': 'cancelled',
                    ':failed': 'failed',
                    ':rejected': 'rejected',
                    ':expired': 'expired',
                    // Legacy support
                    ':canceledByUser': 'canceled_by_user',
                    ':canceledByStore': 'canceled_by_store',
                    ':canceledBySystem': 'canceled_by_system'
                };
            } else {
                // Single status filter
                queryCommand.FilterExpression = '#status = :status';
                queryCommand.ExpressionAttributeNames = {
                    '#status': 'status'
                };
                queryCommand.ExpressionAttributeValues[':status'] = status;
            }
        }

        const command = new QueryCommand(queryCommand);
        const result = await dynamoDb.send(command);

        const orders = result.Items || [];

        console.log('Orders retrieved successfully:', orders.length, 'orders found');

        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                success: true,
                orders: orders,
                count: orders.length,
                lastEvaluatedKey: result.LastEvaluatedKey
            })
        };

    } catch (error) {
        console.error('Error retrieving user orders:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                error: 'Failed to retrieve user orders',
                message: error.message,
                success: false
            })
        };
    }
};
