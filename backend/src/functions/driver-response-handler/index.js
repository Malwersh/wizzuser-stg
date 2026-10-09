/**
 * Driver Order Response Handler
 * Handles when drivers accept or reject order offers
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand, ScanCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');

const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

/**
 * Process driver response to order offer
 * @param {string} driverId - ID of responding driver
 * @param {string} connectionId - WebSocket connection ID
 * @param {string} orderId - Order ID
 * @param {string} response - 'accept' or 'reject'
 * @param {object} responseData - Additional response data
 */
async function processDriverResponse(driverId, connectionId, orderId, response, responseData = {}) {
    console.log(`🎯 Processing driver response: ${response} from ${driverId} for order ${orderId}`);
    
    try {
        // 1. Check if order is still available for assignment
        const orderResult = await docClient.send(new GetCommand({
            TableName: 'WizzOrders',
            Key: {
                PK: `ORDER#${orderId}`,
                SK: 'META'
            }
        }));

        if (!orderResult.Item) {
            console.log(`❌ Order ${orderId} not found`);
            return { success: false, reason: 'order_not_found' };
        }

        const order = orderResult.Item;
        
        // Check if order is already assigned
        if (order.driverId && order.status !== 'ready') {
            console.log(`❌ Order ${orderId} already assigned to ${order.driverId}`);
            return { success: false, reason: 'order_already_assigned' };
        }

        if (response === 'accept') {
            console.log(`✅ Driver ${driverId} accepted order ${orderId}`);
            
            // 2. Assign order to this driver (atomic operation)
            const now = new Date().toISOString();
            const assignmentId = `assignment_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`;
            
            try {
                // Update order with driver assignment
                await docClient.send(new UpdateCommand({
                    TableName: 'WizzOrders',
                    Key: {
                        PK: `ORDER#${orderId}`,
                        SK: 'META'
                    },
                    UpdateExpression: 'SET #driverId = :driverId, #assignedAt = :assignedAt, #status = :status',
                    ConditionExpression: 'attribute_not_exists(#driverId) OR #driverId = :null',
                    ExpressionAttributeNames: {
                        '#driverId': 'driverId',
                        '#assignedAt': 'assignedAt',
                        '#status': 'status'
                    },
                    ExpressionAttributeValues: {
                        ':driverId': driverId,
                        ':assignedAt': now,
                        ':status': 'assigned',
                        ':null': null
                    }
                }));

                console.log(`✅ Order ${orderId} successfully assigned to driver ${driverId}`);

                // 3. Create assignment record
                await docClient.send(new UpdateCommand({
                    TableName: requireEnv('DRIVERS_ASSIGNMENTS_TABLE'),
                    Key: {
                        assignmentId: `offer_${orderId}_${Date.now()}`
                    },
                    UpdateExpression: 'SET #status = :status, #assignedTo = :assignedTo, #assignedAt = :assignedAt, #actualAssignmentId = :actualAssignmentId',
                    ExpressionAttributeNames: {
                        '#status': 'status',
                        '#assignedTo': 'assignedTo',
                        '#assignedAt': 'assignedAt',
                        '#actualAssignmentId': 'actualAssignmentId'
                    },
                    ExpressionAttributeValues: {
                        ':status': 'assigned',
                        ':assignedTo': driverId,
                        ':assignedAt': now,
                        ':actualAssignmentId': assignmentId
                    }
                }));

                // 4. Send confirmation to accepting driver
                await sendDriverConfirmation(connectionId, orderId, 'accepted', order);

                // 5. Cancel offers for all other drivers
                await cancelOffersForOtherDrivers(orderId, driverId);

                // 6. Send order update to user
                await sendUserOrderUpdate(orderId, order, driverId);

                return { 
                    success: true, 
                    assignmentId, 
                    driverId,
                    assignedAt: now 
                };

            } catch (conditionalError) {
                if (conditionalError.name === 'ConditionalCheckFailedException') {
                    console.log(`❌ Order ${orderId} was assigned to another driver while ${driverId} was accepting`);
                    // Send "too late" message to this driver
                    await sendDriverConfirmation(connectionId, orderId, 'too_late', order);
                    return { success: false, reason: 'order_already_taken' };
                }
                throw conditionalError;
            }

        } else if (response === 'reject') {
            console.log(`❌ Driver ${driverId} rejected order ${orderId}`);
            
            // Log rejection but don't do anything else
            // Order remains available for other drivers
            
            return { success: true, action: 'rejected' };
        }

    } catch (error) {
        console.error(`❌ Error processing driver response:`, error);
        return { success: false, reason: 'processing_error', error: error.message };
    }
}

/**
 * Send confirmation to driver
 */
async function sendDriverConfirmation(connectionId, orderId, result, orderData) {
    try {
        const driversWebsocketEndpoint = process.env.DRIVERS_WEBSOCKET_MANAGEMENT_ENDPOINT ||
            (process.env.DRIVERS_WEBSOCKET_ENDPOINT ? process.env.DRIVERS_WEBSOCKET_ENDPOINT.replace('wss://', 'https://') : undefined);

        if (!driversWebsocketEndpoint) {
            console.warn('⚠️ Driver confirmation skipped (missing DRIVERS_WEBSOCKET_* env vars)');
            return;
        }

        const apiGateway = new ApiGatewayManagementApiClient({
            endpoint: driversWebsocketEndpoint
        });

        const message = {
            type: 'order_response_result',
            data: {
                orderId,
                result, // 'accepted', 'too_late', 'error'
                timestamp: new Date().toISOString(),
                orderDetails: result === 'accepted' ? {
                    orderNumber: orderData.orderNumber,
                    customerName: orderData.customerName,
                    customerPhone: orderData.customerPhone,
                    deliveryAddress: orderData.deliveryAddress,
                    totalAmount: (orderData.pricing?.total || 0) / 100,
                    items: orderData.items
                } : null
            }
        };

        await apiGateway.send(new PostToConnectionCommand({
            ConnectionId: connectionId,
            Data: JSON.stringify(message)
        }));

        console.log(`✅ Sent ${result} confirmation to driver: ${connectionId}`);

    } catch (error) {
        console.error(`❌ Failed to send confirmation to driver:`, error);
    }
}

/**
 * Cancel offers for all other drivers
 */
async function cancelOffersForOtherDrivers(orderId, assignedDriverId) {
    try {
        console.log(`🚫 Cancelling offers for other drivers (order ${orderId} assigned to ${assignedDriverId})`);

        const driversConnectionsTable = process.env.DRIVERS_CONNECTIONS_TABLE;
        const driversWebsocketEndpoint = process.env.DRIVERS_WEBSOCKET_MANAGEMENT_ENDPOINT ||
            (process.env.DRIVERS_WEBSOCKET_ENDPOINT ? process.env.DRIVERS_WEBSOCKET_ENDPOINT.replace('wss://', 'https://') : undefined);

        if (!driversConnectionsTable || !driversWebsocketEndpoint) {
            console.warn('⚠️ Cancel offers skipped (missing DRIVERS_CONNECTIONS_TABLE or DRIVERS_WEBSOCKET_* env vars)');
            return;
        }
        
        // Get all connected drivers
        const connectionsResult = await docClient.send(new ScanCommand({
            TableName: driversConnectionsTable,
            FilterExpression: '#status = :status',
            ExpressionAttributeNames: {
                '#status': 'status'
            },
            ExpressionAttributeValues: {
                ':status': 'connected'
            }
        }));

        const apiGateway = new ApiGatewayManagementApiClient({
            endpoint: driversWebsocketEndpoint
        });

        const cancelMessage = {
            type: 'order_offer_cancelled',
            data: {
                orderId,
                reason: 'assigned_to_another_driver',
                timestamp: new Date().toISOString()
            }
        };

        // Send cancellation to all drivers except the assigned one
        let cancelledCount = 0;
        for (const connection of connectionsResult.Items || []) {
            if (connection.driverId !== assignedDriverId) {
                try {
                    await apiGateway.send(new PostToConnectionCommand({
                        ConnectionId: connection.connectionId,
                        Data: JSON.stringify(cancelMessage)
                    }));
                    cancelledCount++;
                } catch (error) {
                    console.error(`Failed to send cancellation to ${connection.driverId}:`, error.message);
                }
            }
        }

        console.log(`✅ Cancelled offers for ${cancelledCount} other drivers`);

    } catch (error) {
        console.error(`❌ Error cancelling offers:`, error);
    }
}

/**
 * Send order update to user
 */
async function sendUserOrderUpdate(orderId, orderData, driverId) {
    try {
        // This would send WebSocket update to user app
        // Implementation depends on user WebSocket system
        console.log(`📱 Sending order update to user for order ${orderId} (assigned to ${driverId})`);
        
        // TODO: Implement user WebSocket notification
        
    } catch (error) {
        console.error(`❌ Error sending user update:`, error);
    }
}

module.exports = {
    processDriverResponse,
    sendDriverConfirmation,
    cancelOffersForOtherDrivers,
    sendUserOrderUpdate
};