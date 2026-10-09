const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, UpdateCommand, GetCommand, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');
const https = require('https');

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const TABLE_NAME = process.env.WIZZORDERS_TABLE;
const WEBSOCKET_TABLE = process.env.WEBSOCKET_TABLE || process.env.CONNECTIONS_TABLE;
const WEBSOCKET_ENDPOINT = process.env.WEBSOCKET_MANAGEMENT_ENDPOINT || (process.env.WEBSOCKET_ENDPOINT ? process.env.WEBSOCKET_ENDPOINT.replace('wss://', 'https://') : undefined);

// Shared WizzUser WebSocket infrastructure for merchant notifications
const MERCHANT_CONNECTIONS_TABLE = process.env.WEBSOCKET_CONNECTIONS_TABLE || process.env.CONNECTIONS_TABLE;
const MERCHANT_WEBSOCKET_ENDPOINT = process.env.MERCHANT_WEBSOCKET_ENDPOINT || process.env.WEBSOCKET_ENDPOINT;

// Order Service configuration
const ORDER_SERVICE_URL = process.env.ORDER_SERVICE_URL;
const SERVICE_TOKEN = process.env.SERVICE_TOKEN;

/**
 * Call Order Service to cancel order
 * Order Service will handle:
 * - Validating order can be cancelled
 * - Releasing Hold from driver wallet (if exists)
 * - Updating order status
 * - Sending notifications
 */
async function callOrderService(orderId, reason, userId) {
    if (!ORDER_SERVICE_URL) {
        throw new Error('Missing required environment variable: ORDER_SERVICE_URL');
    }

    return new Promise((resolve, reject) => {
        const postData = JSON.stringify({
            orderId: orderId,
            canceledBy: 'customer',
            reason: reason,
            requestedBy: userId  // Send userId without prefix
        });

        const url = new URL('/order/cancel', ORDER_SERVICE_URL);
        console.log(`[CancelOrder] Using Order Service URL: ${ORDER_SERVICE_URL}`);
        
        const options = {
            hostname: url.hostname,
            port: url.port || 443,
            path: url.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData),
                ...(SERVICE_TOKEN ? { 'x-service-token': SERVICE_TOKEN } : {})
            }
        };

        console.log(`📞 Calling Order Service to cancel order ${orderId}`);
        console.log(`   URL: ${ORDER_SERVICE_URL}/order/cancel`);
        console.log(`   Body:`, JSON.parse(postData));

        const req = https.request(options, (res) => {
            let data = '';

            res.on('data', (chunk) => {
                data += chunk;
            });

            res.on('end', () => {
                console.log(`📞 Order Service response status: ${res.statusCode}`);
                console.log(`📞 Order Service response body:`, data);

                if (res.statusCode === 200) {
                    try {
                        const response = JSON.parse(data);
                        console.log(`✅ Order Service: Order ${orderId} cancelled successfully`);
                        if (response.holdReleased) {
                            console.log(`💰 Order Service: Hold released from driver wallet`);
                        }
                        resolve(response);
                    } catch (e) {
                        console.error('❌ Failed to parse Order Service response:', e);
                        reject(new Error('Invalid response from Order Service'));
                    }
                } else {
                    const errorMsg = `Order Service returned ${res.statusCode}: ${data}`;
                    console.error(`❌ ${errorMsg}`);
                    reject(new Error(errorMsg));
                }
            });
        });

        req.on('error', (error) => {
            console.error('❌ Error calling Order Service:', error);
            reject(error);
        });

        req.write(postData);
        req.end();
    });
}

// WebSocket notification helper
async function sendWebSocketNotification({ userId, orderId, type, order }) {
    try {
        console.log(`Sending WebSocket notification for ${type} to user ${userId}`);

        if (!WEBSOCKET_TABLE || !WEBSOCKET_ENDPOINT) {
            console.warn('⚠️ User WebSocket notification skipped (missing WEBSOCKET_TABLE/CONNECTIONS_TABLE or WEBSOCKET endpoint env vars)');
            return;
        }
        
        // Get user connections from WebSocket table
        const queryCommand = new QueryCommand({
            TableName: WEBSOCKET_TABLE,
            IndexName: 'UserIdIndex', // Assuming we have a GSI on userId
            KeyConditionExpression: 'userId = :userId',
            ExpressionAttributeValues: {
                ':userId': userId
            }
        });

        const connections = await dynamoDb.send(queryCommand);
        
        if (!connections.Items || connections.Items.length === 0) {
            console.log(`No WebSocket connections found for user ${userId}`);
            return;
        }

        const apiGw = new ApiGatewayManagementApiClient({
            endpoint: WEBSOCKET_ENDPOINT
        });

        const notificationData = {
            type: type,
            orderId: orderId,
            order: order,
            timestamp: new Date().toISOString()
        };

        const promises = connections.Items.map(async (connection) => {
            try {
                const command = new PostToConnectionCommand({
                    ConnectionId: connection.connectionId,
                    Data: JSON.stringify(notificationData)
                });
                
                await apiGw.send(command);
                console.log(`WebSocket notification sent to connection ${connection.connectionId}`);
            } catch (error) {
                if (error.statusCode === 410) {
                    // Connection is stale, remove it
                    console.log(`Removing stale connection ${connection.connectionId}`);
                    // TODO: Remove stale connection from DynamoDB
                } else {
                    console.error(`Failed to send to connection ${connection.connectionId}:`, error);
                }
            }
        });

        await Promise.allSettled(promises);
        console.log(`WebSocket notifications processed for ${promises.length} connections`);
        
    } catch (error) {
        console.error('Error in sendWebSocketNotification:', error);
        throw error;
    }
}

/**
 * Send ORDER_CANCELLED notification to merchant via WebSocket
 * Uses shared WizzUser WebSocket infrastructure (same as NEW_ORDER notifications)
 * @param {Object} params - Notification parameters
 * @param {string} params.storeId - Merchant's store/business ID
 * @param {string} params.orderId - Order ID that was cancelled
 * @param {string} params.type - Notification type (e.g., 'ORDER_CANCELLED')
 * @param {string} params.status - New order status (should be 'cancelled')
 * @param {string} params.cancelReason - Reason for cancellation
 * @param {Object} params.order - Full order object with all details
 * @returns {Promise} - Promise that resolves when notification is sent
 */
async function sendMerchantWebSocketNotification({ storeId, orderId, type, status, cancelReason, order }) {
    console.log('📡 Preparing merchant notification for cancelled order:', orderId);
    
    try {
        if (!MERCHANT_CONNECTIONS_TABLE || !MERCHANT_WEBSOCKET_ENDPOINT) {
            console.warn('⚠️ Merchant WebSocket notification skipped (missing MERCHANT_* env vars)');
            return;
        }
        // Find active WebSocket connections for this merchant/business
        // We scan with FilterExpression because businessId is not in any GSI key
        const scanParams = {
            TableName: MERCHANT_CONNECTIONS_TABLE,
            FilterExpression: 'businessId = :businessId AND isActive = :active',
            ExpressionAttributeValues: {
                ':businessId': storeId,
                ':active': true
            }
        };
        
        console.log('📡 Scanning for merchant WebSocket connections:', JSON.stringify(scanParams, null, 2));
        
        const scanResult = await dynamoDb.send(new ScanCommand(scanParams));
        let connections = scanResult.Items || [];
        
        // Filter out expired connections based on TTL
        const currentTime = Math.floor(Date.now() / 1000);
        connections = connections.filter(conn => !conn.ttl || conn.ttl > currentTime);
        
        console.log(`📡 Found ${connections.length} active WebSocket connections for merchant ${storeId}`);
        
        if (connections.length === 0) {
            console.log('📡 No active WebSocket connections found for merchant, skipping notification');
            return;
        }
        
        // Initialize WebSocket API client with correct endpoint
        const apiGwClient = new ApiGatewayManagementApiClient({
            endpoint: MERCHANT_WEBSOCKET_ENDPOINT.replace('wss://', 'https://'),
            region: process.env.AWS_REGION || 'us-east-1'
        });
        
        // Prepare notification message matching RealtimeOrderService format
        const notification = {
            type: type,
            action: 'order_cancelled', // For compatibility
            data: {
                orderId: orderId,
                orderNumber: order.orderNumber_gsi,
                storeId: order.storeId,
                storeName: order.storeName,
                customerName: order.customerName,
                customerPhone: order.customerPhone,
                items: order.items,
                pricing: order.pricing,
                total: order.pricing?.total ? order.pricing.total / 1000 : 0, // Convert fils to IQD
                deliveryAddress: order.deliveryAddress,
                deliveryType: order.deliveryType,
                paymentMethod: order.paymentMethod,
                notes: order.notes,
                createdAt: order.createdAt,
                updatedAt: order.updatedAt,
                canceledAt: order.canceledAt,
                canceledBy: order.canceledBy,
                cancelReason: cancelReason,
                status: status,
                isGuestOrder: order.isGuestOrder,
                channel: order.channel,
                currency: order.currency
            },
            timestamp: new Date().toISOString(),
            priority: 'HIGH' // Mark as high priority for immediate processing
        };
        
        const messageData = JSON.stringify(notification);
        console.log('📡 Prepared cancellation notification message:', messageData.substring(0, 300) + '...');
        
        // Send notification to all active connections
        const sendPromises = connections.map(async (connection) => {
            try {
                const command = new PostToConnectionCommand({
                    ConnectionId: connection.connectionId,
                    Data: messageData
                });
                
                await apiGwClient.send(command);
                console.log(`📡 ✅ Cancellation notification sent successfully to merchant connection: ${connection.connectionId}`);
                
            } catch (error) {
                console.error(`📡 ❌ Failed to send cancellation notification to connection ${connection.connectionId}:`, error);
                
                // If connection is stale (410 Gone error), mark it as inactive
                if (error.statusCode === 410 || error.$metadata?.httpStatusCode === 410) {
                    console.log(`📡 Marking stale connection as inactive: ${connection.connectionId}`);
                    try {
                        await dynamoDb.send(new UpdateCommand({
                            TableName: MERCHANT_CONNECTIONS_TABLE,
                            Key: {
                                connectionId: connection.connectionId
                            },
                            UpdateExpression: 'SET isActive = :active',
                            ExpressionAttributeValues: {
                                ':active': false
                            }
                        }));
                        console.log(`📡 Marked connection ${connection.connectionId} as inactive`);
                    } catch (updateError) {
                        console.error('📡 Failed to mark connection as inactive:', updateError);
                    }
                }
            }
        });
        
        await Promise.allSettled(sendPromises);
        console.log(`📡 Merchant cancellation notifications processed for ${sendPromises.length} connections`);
        
    } catch (error) {
        console.error('📡 ❌ Error in sendMerchantWebSocketNotification:', error);
        // Don't throw error to prevent breaking the cancel operation
    }
}

/**
 * Lambda handler for cancelling user orders
 * Updated: 2025-12-22 - Integrated with Order Service for Hold release
 * 
 * Changes:
 * - Now calls Order Service API instead of direct DynamoDB update
 * - Order Service handles Hold release from driver wallet automatically
 * - Allows cancellation even after driver accepts (status: 'accepted')
 * - Returns holdReleased flag in response
 */
exports.handler = async (event) => {
    console.log('📥 Cancel order event received:', JSON.stringify(event, null, 2));
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'
    };
    
    try {
        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: headers,
                body: JSON.stringify({ message: 'CORS preflight successful' })
            };
        }

        // Get order ID from path parameters
        const orderId = event.pathParameters?.orderId || event.pathParameters?.id;
        
        if (!orderId) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order ID is required',
                    success: false
                })
            };
        }

        // Parse request body for cancellation reason
        let body = {};
        if (event.body) {
            try {
                body = JSON.parse(event.body);
            } catch (parseError) {
                console.error('Failed to parse request body:', parseError);
                body = {};
            }
        }

        const { reason = 'Order cancelled by user' } = body;

        console.log('Cancelling order:', orderId, 'with reason:', reason);

        // First, get the current order to verify it exists and can be cancelled
        const getCommand = new GetCommand({
            TableName: TABLE_NAME,
            Key: {
                PK: `ORDER#${orderId}`,
                SK: 'META'
            }
        });

        const currentOrderResult = await dynamoDb.send(getCommand);

        if (!currentOrderResult.Item) {
            return {
                statusCode: 404,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order not found',
                    success: false
                })
            };
        }

        const currentOrder = currentOrderResult.Item;
        const userId = currentOrder.customerId || currentOrder.userId;

        // Check if order can be cancelled based on current status
        // ✅ UPDATED: Now allows cancellation even after driver accepts
        // Order Service will handle Hold release automatically
        const allowedCancellationStatuses = [
            'pending',      // Order placed, waiting for restaurant
            'confirmed',    // Restaurant confirmed, waiting for driver
            'accepted'      // Driver accepted - Hold exists, will be released
        ];
        
        if (!allowedCancellationStatuses.includes(currentOrder.status)) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: `Cannot cancel order in ${currentOrder.status} status`,
                    success: false,
                    currentStatus: currentOrder.status
                })
            };
        }

        // ✅ Call Order Service to handle cancellation with Hold release
        console.log(`🔄 Calling Order Service to cancel order ${orderId}`);
        
        let orderServiceResponse;
        try {
            orderServiceResponse = await callOrderService(orderId, reason, userId);
        } catch (orderServiceError) {
            console.error('❌ Order Service call failed:', orderServiceError);
            
            return {
                statusCode: 500,
                headers: headers,
                body: JSON.stringify({
                    error: 'Failed to cancel order via Order Service',
                    message: orderServiceError.message,
                    success: false
                })
            };
        }

        console.log('✅ Order Service: Order cancelled successfully');
        if (orderServiceResponse.holdReleased) {
            console.log('💰 Order Service: Hold released from driver wallet');
        }

        console.log('✅ Order Service: Order cancelled successfully');
        if (orderServiceResponse.holdReleased) {
            console.log('💰 Order Service: Hold released from driver wallet');
        }

        // Get updated order details after cancellation
        const updatedOrderResult = await dynamoDb.send(getCommand);
        const updatedOrder = updatedOrderResult.Item;

        // Send WebSocket notification to user for real-time UI update
        try {
            await sendWebSocketNotification({
                userId: userId,
                orderId: orderId,
                type: 'order_cancelled',
                order: updatedOrder
            });
            console.log('✅ WebSocket notification sent to user for order cancellation');
        } catch (wsError) {
            console.error('❌ Failed to send WebSocket notification to user:', wsError);
            // Don't fail the entire operation for WebSocket errors
        }

        // Send WebSocket notification to merchant for real-time order update
        try {
            await sendMerchantWebSocketNotification({
                storeId: updatedOrder.storeId,
                orderId: orderId,
                type: 'ORDER_STATUS_UPDATE',
                status: updatedOrder.status,
                cancelReason: reason,
                order: updatedOrder
            });
            console.log('✅ WebSocket notification sent to merchant for order cancellation');
        } catch (merchantWsError) {
            console.error('❌ Failed to send WebSocket notification to merchant:', merchantWsError);
            // Don't fail the entire operation for WebSocket errors
        }

        console.log('Order cancelled successfully:', orderId);

        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                success: true,
                message: orderServiceResponse.holdReleased 
                    ? 'تم إلغاء الطلب وإعادة المبلغ المحجوز إلى محفظة السائق'
                    : 'تم إلغاء الطلب بنجاح',
                order: updatedOrder,
                orderId: orderId,
                status: updatedOrder.status,
                holdReleased: orderServiceResponse.holdReleased || false
            })
        };

    } catch (error) {
        console.error('Error cancelling order:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                error: 'Failed to cancel order',
                message: error.message,
                success: false
            })
        };
    }
};
