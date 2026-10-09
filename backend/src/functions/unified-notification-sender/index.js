/**
 * Unified Notification Sender
 * Sends notifications to both customers (WizzUser) and merchants (WizzBusiness)
 * Called by DynamoDB stream processor or status update functions
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

function toManagementEndpoint(endpoint) {
    if (!endpoint) return endpoint;
    return endpoint.replace('wss://', 'https://');
}

// Environment variables
const WIZZUSER_WEBSOCKET_ENDPOINT = requireEnv('WIZZUSER_WEBSOCKET_ENDPOINT');
const WIZZBUSINESS_WEBSOCKET_ENDPOINT = requireEnv('WIZZBUSINESS_WEBSOCKET_ENDPOINT');
const WIZZUSER_CONNECTIONS_TABLE = requireEnv('WIZZUSER_CONNECTIONS_TABLE');
const WIZZBUSINESS_CONNECTIONS_TABLE = process.env.WIZZBUSINESS_CONNECTIONS_TABLE;

/**
 * Lambda handler for unified notification sending
 * @param {Object} event - Lambda event containing notification data
 * @returns {Object} - Lambda response
 */
exports.handler = async (event) => {
    console.log('🔔 Unified Notification Sender triggered:', JSON.stringify(event, null, 2));
    
    try {
        const { orderId, orderData, eventType, status, businessId, userId } = event;
        
        if (!orderId) {
            throw new Error('orderId is required');
        }
        
        // Send notifications to both systems in parallel
        const [customerResult, merchantResult] = await Promise.allSettled([
            sendCustomerNotification(orderId, orderData, eventType, status, userId),
            sendMerchantNotification(orderId, orderData, eventType, status, businessId)
        ]);
        
        console.log('🔔 Customer notification result:', customerResult);
        console.log('🔔 Merchant notification result:', merchantResult);
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                success: true,
                orderId: orderId,
                customerNotificationSent: customerResult.status === 'fulfilled',
                merchantNotificationSent: merchantResult.status === 'fulfilled',
                message: 'Notifications processed'
            })
        };
        
    } catch (error) {
        console.error('🔔 Error in unified notification sender:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({
                success: false,
                error: error.message
            })
        };
    }
};

/**
 * Send notification to customer (WizzUser WebSocket)
 * @param {string} orderId - Order ID
 * @param {Object} orderData - Order data
 * @param {string} eventType - Event type (INSERT, MODIFY, REMOVE)
 * @param {string} status - Order status
 * @param {string} userId - User ID
 */
async function sendCustomerNotification(orderId, orderData, eventType, status, userId) {
    console.log('📱 Sending customer notification for order:', orderId);
    
    try {
        const dynamoClient = new DynamoDBClient({});
        const docClient = DynamoDBDocumentClient.from(dynamoClient);
        
        // Find customer WebSocket connections subscribed to this order
        const queryParams = {
            TableName: WIZZUSER_CONNECTIONS_TABLE,
            IndexName: 'GSI1',
            KeyConditionExpression: 'GSI1PK = :orderPK',
            ExpressionAttributeValues: {
                ':orderPK': `ORDER#${orderId}`
            }
        };
        
        console.log('📱 Querying customer connections:', JSON.stringify(queryParams, null, 2));
        
        const queryResult = await docClient.send(new QueryCommand(queryParams));
        const connections = queryResult.Items || [];
        
        console.log(`📱 Found ${connections.length} customer connections for order ${orderId}`);
        
        if (connections.length === 0) {
            console.log('📱 No customer WebSocket connections found for order, skipping');
            return;
        }
        
        // Initialize WebSocket API client for WizzUser
        const apiGwClient = new ApiGatewayManagementApiClient({
            endpoint: WIZZUSER_WEBSOCKET_ENDPOINT.replace('wss://', 'https://'),
            region: process.env.AWS_REGION || 'us-east-1'
        });
        
        // Prepare customer notification
        const customerNotification = {
            type: 'ORDER_STATUS_UPDATE',
            orderId: orderId,
            orderNumber: orderData?.orderNumber || '',
            status: status,
            message: getCustomerStatusMessage(status),
            estimatedDeliveryTime: orderData?.estimatedDeliveryTime || null,
            timestamp: new Date().toISOString(),
            eventType: eventType
        };
        
        const messageData = JSON.stringify(customerNotification);
        
        // Send to all customer connections
        const sendPromises = connections.map(async (connection) => {
            try {
                const command = new PostToConnectionCommand({
                    ConnectionId: connection.connectionId,
                    Data: messageData
                });
                
                await apiGwClient.send(command);
                console.log(`📱 Customer notification sent to: ${connection.connectionId}`);
                
            } catch (error) {
                console.error(`📱 Failed to send to customer connection ${connection.connectionId}:`, error);
                
                // Clean up stale connections
                if (error.statusCode === 410) {
                    await cleanupStaleConnection(docClient, WIZZUSER_CONNECTIONS_TABLE, connection.connectionId);
                }
            }
        });
        
        await Promise.allSettled(sendPromises);
        console.log(`📱 Customer notifications completed for ${connections.length} connections`);
        
    } catch (error) {
        console.error('📱 Error sending customer notification:', error);
        throw error;
    }
}

/**
 * Send notification to merchant (WizzBusiness WebSocket)  
 * @param {string} orderId - Order ID
 * @param {Object} orderData - Order data
 * @param {string} eventType - Event type (INSERT, MODIFY, REMOVE)
 * @param {string} status - Order status  
 * @param {string} businessId - Business ID
 */
async function sendMerchantNotification(orderId, orderData, eventType, status, businessId) {
    console.log('🏪 Sending merchant notification for order:', orderId);
    
    try {
        const dynamoClient = new DynamoDBClient({});
        const docClient = DynamoDBDocumentClient.from(dynamoClient);
        
        // Find merchant WebSocket connections using GSI1 index in WizzUser connections table
        const queryParams = {
            TableName: WIZZUSER_CONNECTIONS_TABLE,
            IndexName: 'GSI1',
            KeyConditionExpression: 'GSI1PK = :gsi1pk',
            FilterExpression: 'entityType = :entityType AND isActive = :active',
            ExpressionAttributeValues: {
                ':gsi1pk': `BUSINESS#${businessId}`,
                ':entityType': 'business',
                ':active': true
            }
        };
        
        console.log('🏪 Querying merchant connections with GSI1:', JSON.stringify(queryParams, null, 2));
        
        const queryResult = await docClient.send(new QueryCommand(queryParams));
        const connections = queryResult.Items || [];
        
        console.log(`🏪 Found ${connections.length} merchant connections for business ${businessId}`);
        
        if (connections.length === 0) {
            console.log('🏪 No merchant WebSocket connections found, skipping');
            return;
        }
        
        // Initialize dual WebSocket API clients for both endpoints
        const wizzuserWebSocketEndpoint = toManagementEndpoint(WIZZUSER_WEBSOCKET_ENDPOINT);
        const businessWebSocketEndpoint = toManagementEndpoint(WIZZBUSINESS_WEBSOCKET_ENDPOINT);
        
        const wizzuserApiGwClient = new ApiGatewayManagementApiClient({
            endpoint: wizzuserWebSocketEndpoint,
            region: process.env.AWS_REGION || 'us-east-1'
        });
        
        const businessApiGwClient = new ApiGatewayManagementApiClient({
            endpoint: businessWebSocketEndpoint,
            region: process.env.AWS_REGION || 'us-east-1'
        });
        
        // Determine message type based on event
        const messageType = eventType === 'INSERT' ? 'NEW_ORDER' : 'ORDER_UPDATE';
        
        // Prepare merchant notification
        const merchantNotification = {
            type: messageType,
            action: eventType === 'INSERT' ? 'new_order' : 'order_update',
            data: orderData || {
                orderId: orderId,
                status: status,
                updatedAt: new Date().toISOString()
            },
            orderId: orderId,
            status: status,
            businessId: businessId,
            timestamp: new Date().toISOString(),
            eventType: eventType,
            priority: eventType === 'INSERT' ? 'HIGH' : 'NORMAL'
        };
        
        const messageData = JSON.stringify(merchantNotification);
        
        // Send to all merchant connections with dual endpoint logic
        const sendPromises = connections.map(async (connection) => {
            try {
                const command = new PostToConnectionCommand({
                    ConnectionId: connection.connectionId,
                    Data: messageData
                });
                
                // Determine which API client to use based on connection source
                let apiClient;
                let endpointName;
                
                if (connection.source === 'business_login') {
                    apiClient = businessApiGwClient;
                    endpointName = 'wizzbussiness';
                    console.log(`🏪 Using wizzbussiness WebSocket API for connection: ${connection.connectionId}`);
                } else {
                    apiClient = wizzuserApiGwClient;
                    endpointName = 'wizzuser';
                    console.log(`🏪 Using wizzuser WebSocket API for connection: ${connection.connectionId}`);
                }
                
                await apiClient.send(command);
                console.log(`🏪 Merchant notification sent to ${connection.connectionId} via ${endpointName} endpoint`);
                
            } catch (error) {
                console.error(`🏪 Failed to send to merchant connection ${connection.connectionId}:`, error);
                
                // Try alternative endpoint if the first one fails
                if (error.statusCode === 400 && error.message?.includes('Invalid connectionId')) {
                    try {
                        console.log(`🏪 Retrying with alternative WebSocket endpoint for ${connection.connectionId}`);
                        
                        const alternativeClient = connection.source === 'business_login' ? wizzuserApiGwClient : businessApiGwClient;
                        const alternativeEndpoint = connection.source === 'business_login' ? 'wizzuser' : 'wizzbussiness';
                        
                        const retryCommand = new PostToConnectionCommand({
                            ConnectionId: connection.connectionId,
                            Data: messageData
                        });
                        
                        await alternativeClient.send(retryCommand);
                        console.log(`🏪 Successfully sent notification via ${alternativeEndpoint} endpoint to ${connection.connectionId}`);
                        
                    } catch (retryError) {
                        console.error(`🏪 Alternative endpoint also failed for ${connection.connectionId}:`, retryError);
                        
                        // Mark stale connections as inactive
                        if (retryError.statusCode === 410) {
                            await removeStaleConnection(docClient, WIZZUSER_CONNECTIONS_TABLE, connection);
                        }
                    }
                } else if (error.statusCode === 410) {
                    // Mark stale connections as inactive
                    await removeStaleConnection(docClient, WIZZUSER_CONNECTIONS_TABLE, connection);
                }
            }
        });
        
        await Promise.allSettled(sendPromises);
        console.log(`🏪 Merchant notifications completed for ${connections.length} connections`);
        
    } catch (error) {
        console.error('🏪 Error sending merchant notification:', error);
        throw error;
    }
}

/**
 * Get customer-friendly status message
 * @param {string} status - Order status
 * @returns {string} - Customer message
 */
function getCustomerStatusMessage(status) {
    const statusMessages = {
        'pending': 'Your order is being processed',
        'confirmed': 'Your order has been confirmed by the restaurant',
        'preparing': 'Your order is being prepared',
        'ready': 'Your order is ready for pickup',
        'on_the_way': 'Your order is on the way',
        'delivered': 'Your order has been delivered',
        'cancelled': 'Your order has been cancelled',
        'rejected': 'Your order has been declined'
    };
    
    return statusMessages[status] || `Order status updated to: ${status}`;
}

/**
 * Clean up stale customer connection
 * @param {Object} docClient - DynamoDB client
 * @param {string} tableName - Table name
 * @param {string} connectionId - Connection ID to remove
 */
async function cleanupStaleConnection(docClient, tableName, connectionId) {
    try {
        const { DeleteCommand } = require('@aws-sdk/lib-dynamodb');
        
        await docClient.send(new DeleteCommand({
            TableName: tableName,
            Key: {
                PK: `CONNECTION#${connectionId}`,
                SK: `CONNECTION#${connectionId}`
            }
        }));
        
        console.log(`🧹 Removed stale customer connection: ${connectionId}`);
    } catch (error) {
        console.error(`🧹 Failed to cleanup customer connection ${connectionId}:`, error);
    }
}

/**
 * Remove stale connection from WebSocket connections table
 * @param {Object} docClient - DynamoDB client
 * @param {string} tableName - Table name
 * @param {Object} connection - Connection object
 */
async function removeStaleConnection(docClient, tableName, connection) {
    try {
        const { DeleteCommand } = require('@aws-sdk/lib-dynamodb');
        
        await docClient.send(new DeleteCommand({
            TableName: tableName,
            Key: {
                PK: connection.PK,
                SK: connection.SK
            }
        }));
        
        console.log(`🧹 Removed stale connection: ${connection.connectionId}`);
    } catch (error) {
        console.error(`🧹 Failed to remove stale connection ${connection.connectionId}:`, error);
    }
}

/**
 * Mark merchant connection as inactive
 * @param {Object} docClient - DynamoDB client
 * @param {string} tableName - Table name
 * @param {Object} connection - Connection object
 */
async function markConnectionInactive(docClient, tableName, connection) {
    try {
        const { UpdateCommand } = require('@aws-sdk/lib-dynamodb');
        
        await docClient.send(new UpdateCommand({
            TableName: tableName,
            Key: {
                businessId: connection.businessId,
                endpointId: connection.endpointId
            },
            UpdateExpression: 'SET isActive = :active',
            ExpressionAttributeValues: {
                ':active': false
            }
        }));
        
        console.log(`🧹 Marked merchant connection as inactive: ${connection.connectionId}`);
    } catch (error) {
        console.error(`🧹 Failed to mark merchant connection as inactive:`, error);
    }
}
