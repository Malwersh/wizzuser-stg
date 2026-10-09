/**
 * Merchant Order Status Update Handler
 * Allows merchants to update order status and triggers notifications to customers
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, UpdateCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');
const { LambdaClient, InvokeCommand } = require('@aws-sdk/client-lambda');

const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const lambdaClient = new LambdaClient({ region: process.env.AWS_REGION });

const WIZZORDERS_TABLE = process.env.WIZZORDERS_TABLE || 'WizzOrders';

/**
 * Lambda handler for merchant order status updates
 */
exports.handler = async (event) => {
    console.log('🏪 Merchant order status update event:', JSON.stringify(event, null, 2));
    
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
                headers,
                body: ''
            };
        }

        // Parse request
        const { orderId } = event.pathParameters || {};
        let body = {};
        
        if (event.body) {
            body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
        }

        const { status, estimatedTime, notes, estimatedDeliveryTime, deliveryTime } = body;

        // Validation
        if (!orderId) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Order ID is required'
                })
            };
        }

        if (!status) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Status is required'
                })
            };
        }

        // Validate status - updated with proper merchant flow
        const validStatuses = ['pending', 'confirmed', 'preparing', 'ready', 'on_the_way', 'delivered', 'cancelled', 'failed'];
        if (!validStatuses.includes(status)) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: `Invalid status. Valid statuses are: ${validStatuses.join(', ')}`
                })
            };
        }

        console.log(`🏪 Merchant updating order ${orderId} status to: ${status}`);

        // Get current order to verify it exists and get businessId/userId
        const orderGetCommand = new GetCommand({
            TableName: WIZZORDERS_TABLE,
            Key: {
                PK: `ORDER#${orderId}`,
                SK: `ORDER#${orderId}`
            }
        });

        const currentOrder = await docClient.send(orderGetCommand);

        if (!currentOrder.Item) {
            return {
                statusCode: 404,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Order not found'
                })
            };
        }

        const order = currentOrder.Item;
        console.log('🏪 Found order:', order.orderId, 'for business:', order.storeId);

        // Update order in DynamoDB
        const updateExpression = 'SET #status = :status, updatedAt = :updatedAt';
        const expressionAttributeNames = { '#status': 'status' };
        const expressionAttributeValues = {
            ':status': status,
            ':updatedAt': new Date().toISOString()
        };

        // Add optional fields
        if (estimatedTime) {
            updateExpression += ', estimatedDeliveryTime = :estimatedTime';
            expressionAttributeValues[':estimatedTime'] = estimatedTime;
        }

        if (notes) {
            updateExpression += ', merchantNotes = :notes';
            expressionAttributeValues[':notes'] = notes;
        }

        // Update storeStatus GSI field for status-based queries
        const bucket = order.storeStatus ? order.storeStatus.split('#')[2] : 'b0';
        updateExpression += ', storeStatus = :storeStatus';
        expressionAttributeValues[':storeStatus'] = `${order.storeId}#${status}#${bucket}`;

        const updateCommand = new UpdateCommand({
            TableName: WIZZORDERS_TABLE,
            Key: {
                PK: `ORDER#${orderId}`,
                SK: `ORDER#${orderId}`
            },
            UpdateExpression: updateExpression,
            ExpressionAttributeNames: expressionAttributeNames,
            ExpressionAttributeValues: expressionAttributeValues,
            ReturnValues: 'ALL_NEW'
        });

        console.log('🏪 Executing DynamoDB update...');
        const updateResult = await docClient.send(updateCommand);
        const updatedOrder = updateResult.Attributes;

        console.log('🏪 Order updated successfully:', orderId);

        // Trigger unified notification system to notify customer and merchant
        try {
            console.log('📡 Triggering unified notification for status update...');
            
            const notificationPayload = {
                orderId: orderId,
                orderData: {
                    orderId: updatedOrder.orderId,
                    orderNumber: updatedOrder.orderNumber_gsi,
                    status: updatedOrder.status,
                    customerName: updatedOrder.customerName,
                    businessId: updatedOrder.storeId,
                    userId: updatedOrder.userId,
                    estimatedDeliveryTime: updatedOrder.estimatedDeliveryTime || estimatedTime,
                    total: updatedOrder.pricing?.total ? updatedOrder.pricing.total / 1000 : (updatedOrder.total || 0),
                    updatedAt: updatedOrder.updatedAt
                },
                eventType: 'MODIFY',
                status: updatedOrder.status,
                businessId: updatedOrder.storeId,
                userId: updatedOrder.userId
            };
            
            const lambdaCommand = new InvokeCommand({
                FunctionName: 'WizzUser-UnifiedNotificationSender-dev',
                InvocationType: 'Event', // Async
                Payload: JSON.stringify(notificationPayload)
            });
            
            await lambdaClient.send(lambdaCommand);
            console.log('📡 Unified notification triggered successfully');
            
        } catch (notificationError) {
            console.error('📡 Failed to trigger notification (non-blocking):', notificationError);
            // Don't fail the status update if notification fails
        }

        // Return success response
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                message: 'Order status updated successfully',
                order: {
                    orderId: updatedOrder.orderId,
                    status: updatedOrder.status,
                    orderNumber: updatedOrder.orderNumber_gsi,
                    updatedAt: updatedOrder.updatedAt,
                    estimatedDeliveryTime: updatedOrder.estimatedDeliveryTime
                }
            })
        };

    } catch (error) {
        console.error('🏪 Error updating order status:', error);
        
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({
                success: false,
                error: 'Internal server error',
                message: error.message
            })
        };
    }
};
