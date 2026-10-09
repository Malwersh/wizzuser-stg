const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

// Use WizzOrders table
const TABLE_NAME = process.env.WIZZORDERS_TABLE || 'WizzOrders';

/**
 * 🔍 Get Guest Orders Handler
 * 
 * Endpoint: GET /orders?guestToken=<token>&status=active|all
 * 
 * Retrieves orders for guest users using guestToken
 * Supports filtering by status (active vs completed)
 */
exports.handler = async (event) => {
    console.log('🔍 Get Guest Orders Event:', JSON.stringify(event, null, 2));

    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',  
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS'
    };

    try {
        // Handle CORS preflight
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers,
                body: ''
            };
        }

        if (event.httpMethod !== 'GET') {
            return {
                statusCode: 405,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Method not allowed'
                })
            };
        }

        // Extract query parameters
        const queryParams = event.queryStringParameters || {};
        const guestToken = queryParams.guestToken;
        const statusFilter = queryParams.status; // 'active', 'completed', or 'all'
        const limit = parseInt(queryParams.limit || '20');

        // Validate required parameters
        if (!guestToken) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'guestToken is required',
                    error: 'MISSING_GUEST_TOKEN'
                })
            };
        }

        console.log('🎫 Guest token:', guestToken);
        console.log('📊 Status filter:', statusFilter);
        console.log('📄 Limit:', limit);

        // Query DynamoDB using GSI on userId_gsi field
        const queryParameters = {
            TableName: TABLE_NAME,
            IndexName: 'GSI_User', // Use the existing GSI
            KeyConditionExpression: 'userId_gsi = :guestToken',
            ExpressionAttributeValues: {
                ':guestToken': guestToken
            },
            Limit: limit,
            ScanIndexForward: false // Get newest orders first (reverse chronological)
        };

        // Add status filtering if requested
        if (statusFilter && statusFilter !== 'all') {
            if (statusFilter === 'active') {
                // Active orders: pending, confirmed, preparing, ready, on_the_way, in_kitchen, out_for_delivery
                queryParameters.FilterExpression = '#status IN (:pending, :confirmed, :preparing, :ready, :on_the_way, :in_kitchen, :out_for_delivery)';
                queryParameters.ExpressionAttributeNames = { '#status': 'status' };
                queryParameters.ExpressionAttributeValues = {
                    ...queryParameters.ExpressionAttributeValues,
                    ':pending': 'pending',
                    ':confirmed': 'confirmed',
                    ':preparing': 'preparing',
                    ':ready': 'ready',
                    ':on_the_way': 'on_the_way',
                    ':in_kitchen': 'in_kitchen',
                    ':out_for_delivery': 'out_for_delivery'
                };
            } else if (statusFilter === 'completed') {
                // Completed orders: delivered, cancelled, failed, expired
                queryParameters.FilterExpression = '#status IN (:delivered, :cancelled, :failed, :expired)';
                queryParameters.ExpressionAttributeNames = { '#status': 'status' };
                queryParameters.ExpressionAttributeValues = {
                    ...queryParameters.ExpressionAttributeValues,
                    ':delivered': 'delivered',
                    ':cancelled': 'cancelled',
                    ':failed': 'failed',
                    ':expired': 'expired'
                };
            }
        }

        console.log('🔍 DynamoDB Query Parameters:', JSON.stringify(queryParameters, null, 2));

        // Execute query
        const result = await dynamoDb.send(new QueryCommand(queryParameters));
        const orders = result.Items || [];

        console.log(`✅ Found ${orders.length} orders for guest token: ${guestToken}`);

        // Process orders for response
        const processedOrders = orders.map(order => {
            return {
                orderId: order.orderId,
                orderNumber: order.orderNumber,
                status: order.status,
                storeName: order.storeName,
                items: order.items,
                pricing: order.pricing,
                total: order.pricing?.total || order.total || 0,
                createdAt: order.createdAt,
                updatedAt: order.updatedAt,
                deliveryAddress: order.deliveryAddress,
                paymentMethod: order.paymentMethod,
                isGuestOrder: order.isGuestOrder,
                estimatedDeliveryTime: order.estimatedDeliveryTime
            };
        });

        // Categorize orders
        const activeStatuses = ['pending', 'confirmed', 'preparing', 'ready', 'on_the_way', 'in_kitchen', 'out_for_delivery'];
        const activeOrders = processedOrders.filter(order => activeStatuses.includes(order.status));
        const completedOrders = processedOrders.filter(order => !activeStatuses.includes(order.status));

        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                message: `Found ${orders.length} orders for guest`,
                orders: processedOrders,
                summary: {
                    total: processedOrders.length,
                    active: activeOrders.length,
                    completed: completedOrders.length
                },
                metadata: {
                    guestToken: guestToken,
                    statusFilter: statusFilter || 'all',
                    limit: limit,
                    timestamp: new Date().toISOString()
                }
            })
        };

    } catch (error) {
        console.error('❌ Error fetching guest orders:', error);

        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({
                success: false,
                message: 'Failed to fetch guest orders',
                error: error.message
            })
        };
    }
};
