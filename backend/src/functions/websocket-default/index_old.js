const { 
  ApiGatewayManagementApiClient, 
  PostToConnectionCommand 
} = require('@aws-sdk/client-apigatewaymanagementapi');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, ScanCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

exports.handler = async (event) => {
  console.log('WebSocket Default Handler started');
  console.log('Full event received:', JSON.stringify(event, null, 2));
  
  try {
    // Defensive access to event properties
    const connectionId = event.requestContext?.connectionId;
    const routeKey = event.requestContext?.routeKey;
    const body = event.body;
    const apiId = event.requestContext?.apiId;
    
    console.log(`Extracted values: connectionId=${connectionId}, routeKey=${routeKey}, apiId=${apiId}`);
    
    if (!connectionId) {
      console.error('Missing connectionId in event.requestContext');
      return {
        statusCode: 400,
        body: JSON.stringify({ error: 'Missing connectionId' })
      };
    }
    
    console.log(`WebSocket message: ${connectionId}, route: ${routeKey}, body: ${body}`);

    // Initialize API Gateway Management API client
    const region = process.env.AWS_REGION || 'us-east-1';
    const stage = event.requestContext?.stage || process.env.WEBSOCKET_STAGE;
    const effectiveApiId = apiId || process.env.WEBSOCKET_API_ID;

    if (!effectiveApiId) {
      throw new Error('Missing requestContext.apiId and WEBSOCKET_API_ID env var');
    }
    if (!stage) {
      throw new Error('Missing requestContext.stage and WEBSOCKET_STAGE env var');
    }

    const apiGatewayClient = new ApiGatewayManagementApiClient({
      endpoint: `https://${effectiveApiId}.execute-api.${region}.amazonaws.com/${stage}`
    });

    // Initialize DynamoDB client
    const dynamoClient = new DynamoDBClient({ region: 'us-east-1' });
    const docClient = DynamoDBDocumentClient.from(dynamoClient);
    const SUBSCRIPTIONS_TABLE = requireEnv('WEBSOCKET_SUBSCRIPTIONS_TABLE');

    // Parse the message if it exists
    let message;
    if (body) {
      try {
        message = JSON.parse(body);
        console.log('Parsed message:', JSON.stringify(message));
      } catch (e) {
        console.log('Failed to parse message body:', body);
        message = { type: 'unknown', body };
      }
    }
    
    // Handle different message types (support both 'type' and 'action' fields)
    const messageType = message?.type || message?.action;
    if (messageType) {
      switch (messageType) {
            case 'subscribe':
            case 'subscribe_business_status':
              const businessId = message.business_id || message.businessId;
              const subUserId = message.user_id || message.userId;
              console.log(`Subscribing connection ${connectionId} to business status ${businessId} for user ${subUserId}`);
              
              // Store this subscription in DynamoDB
              try {
                const subscriptionItem = {
                  subscriptionId: `${connectionId}_${businessId}`, // Primary key
                  connectionId: connectionId,
                  businessId: businessId,
                  userId: subUserId,
                  subscriptionType: 'business_status',
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
                };
                
                await docClient.send(new PutCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Item: subscriptionItem
                }));
                
                console.log(`Stored business status subscription for ${connectionId} -> ${businessId}`);
              } catch (dbError) {
                console.error(`Failed to store subscription in DynamoDB:`, dbError);
              }
              
              // Send acknowledgment back to client
              try {
                const ackResponse = {
                  type: 'subscription_ack',
                  action: 'subscribe_business_status',
                  businessId: businessId,
                  timestamp: new Date().toISOString(),
                  connectionId: connectionId
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(ackResponse)
                });
                
                await apiGatewayClient.send(command);
                console.log(`Business status subscription acknowledgment sent to ${connectionId}`);
              } catch (ackError) {
                console.error(`Failed to send subscription ack to ${connectionId}:`, ackError);
              }
              break;
            case 'unsubscribe':
            case 'unsubscribe_business_status':
              const unsubBusinessId = message.business_id || message.businessId;
              console.log(`Unsubscribing connection ${connectionId} from business status ${unsubBusinessId}`);
              
              // Remove subscription from DynamoDB
              try {
                await docClient.send(new DeleteCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Key: {
                    subscriptionId: `${connectionId}_${unsubBusinessId}`
                  }
                }));
                console.log(`Removed business status subscription for ${connectionId} -> ${unsubBusinessId}`);
              } catch (dbError) {
                console.error(`Failed to remove subscription from DynamoDB:`, dbError);
              }
              break;
            case 'subscribe_order':
              const orderId = message.order_id || message.orderId;
              const userId = message.user_id || message.userId;
              console.log(`Subscribing connection ${connectionId} to order ${orderId} for user ${userId}`);
              // In a real implementation, you would store this subscription
              break;
            case 'unsubscribe_order':
              const unsubOrderId = message.order_id || message.orderId;
              console.log(`Unsubscribing connection ${connectionId} from order ${unsubOrderId}`);
              break;
            case 'subscribe_business_status':
              const businessId = message.business_id || message.businessId;
              const subUserId = message.user_id || message.userId;
              console.log(`Subscribing connection ${connectionId} to business status ${businessId} for user ${subUserId}`);
              
              // Store this subscription in DynamoDB
              try {
                const subscriptionItem = {
                  subscriptionId: `${connectionId}_${businessId}`, // Primary key
                  connectionId: connectionId,
                  businessId: businessId,
                  userId: subUserId,
                  subscriptionType: 'business_status',
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
                };
                
                await docClient.send(new PutCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Item: subscriptionItem
                }));
                
                console.log(`Stored business status subscription for ${connectionId} -> ${businessId}`);
              } catch (dbError) {
                console.error(`Failed to store subscription in DynamoDB:`, dbError);
              }
              
              // Send acknowledgment back to client
              try {
                const ackResponse = {
                  type: 'subscription_ack',
                  action: 'subscribe_business_status',
                  businessId: businessId,
                  timestamp: new Date().toISOString(),
                  connectionId: connectionId
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(ackResponse)
                });
                
                await apiGatewayClient.send(command);
                console.log(`Business status subscription acknowledgment sent to ${connectionId}`);
              } catch (ackError) {
                console.error(`Failed to send subscription ack to ${connectionId}:`, ackError);
              }
              break;
            case 'unsubscribe_business_status':
              const unsubBusinessId = message.business_id || message.businessId;
              console.log(`Unsubscribing connection ${connectionId} from business status ${unsubBusinessId}`);
              
              // Remove subscription from DynamoDB
              try {
                await docClient.send(new DeleteCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Key: {
                    connectionId: connectionId,
                    businessId: unsubBusinessId
                  }
                }));
                console.log(`Removed business status subscription for ${connectionId} -> ${unsubBusinessId}`);
              } catch (dbError) {
                console.error(`Failed to remove subscription from DynamoDB:`, dbError);
              }
              break;
            case 'BUSINESS_BUSY_STATUS_UPDATE':
              console.log(`Received business busy status update:`, message);
              const updateBusinessId = message.business_id || message.businessId;
              const isBusy = message.isBusy;
              const updateUserId = message.user_id || message.userId;
              
              if (updateBusinessId && typeof isBusy === 'boolean') {
                console.log(`Processing status update for business ${updateBusinessId}: isBusy=${isBusy}`);
                
                // Broadcast this update to all subscribed customers
                console.log(`Business ${updateBusinessId} status update processed: ${isBusy ? 'BUSY' : 'AVAILABLE'}`);
                
                // Create the broadcast message for customers
                const customerUpdateMessage = {
                  type: 'BUSINESS_STATUS_UPDATE',
                  businessId: updateBusinessId,
                  isBusy: isBusy,
                  status: isBusy ? 'BUSY' : 'AVAILABLE',
                  timestamp: new Date().toISOString()
                };
                
                console.log(`Would broadcast to customers: ${JSON.stringify(customerUpdateMessage)}`);
                
                // Query DynamoDB to find all customers subscribed to this business
                try {
                  console.log(`Querying subscriptions for business: ${updateBusinessId}`);
                  
                  // Use ScanCommand instead of QueryCommand since we don't have GSI yet
                  const scanParams = {
                    TableName: SUBSCRIPTIONS_TABLE,
                    FilterExpression: 'businessId = :businessId AND subscriptionType = :subType',
                    ExpressionAttributeValues: {
                      ':businessId': updateBusinessId,
                      ':subType': 'business_status'
                    }
                  };
                  
                  const result = await docClient.send(new ScanCommand(scanParams));
                  const subscriptions = result.Items || [];
                  
                  console.log(`Found ${subscriptions.length} subscriptions for business ${updateBusinessId}`);
                  
                  // Send the update to each subscribed customer
                  const broadcastPromises = subscriptions.map(async (subscription) => {
                    try {
                      const customerConnectionId = subscription.connectionId;
                      console.log(`Sending update to customer connection: ${customerConnectionId}`);
                      
                      const command = new PostToConnectionCommand({
                        ConnectionId: customerConnectionId,
                        Data: JSON.stringify(customerUpdateMessage)
                      });
                      
                      await apiGatewayClient.send(command);
                      console.log(`✅ Sent business status update to ${customerConnectionId}`);
                      return { success: true, connectionId: customerConnectionId };
                    } catch (sendError) {
                      console.error(`❌ Failed to send update to ${subscription.connectionId}:`, sendError);
                      
                      // If connection is stale, remove the subscription
                      if (sendError.name === 'GoneException') {
                        try {
                          await docClient.send(new DeleteCommand({
                            TableName: SUBSCRIPTIONS_TABLE,
                            Key: {
                              connectionId: subscription.connectionId,
                              businessId: updateBusinessId
                            }
                          }));
                          console.log(`Removed stale subscription: ${subscription.connectionId}`);
                        } catch (deleteError) {
                          console.error(`Failed to remove stale subscription:`, deleteError);
                        }
                      }
                      return { success: false, connectionId: subscription.connectionId, error: sendError.message };
                    }
                  });
                  
                  const broadcastResults = await Promise.all(broadcastPromises);
                  const successCount = broadcastResults.filter((r) => r.success).length;
                  console.log(`📡 Broadcast complete: ${successCount}/${subscriptions.length} customers notified`);
                  
                } catch (queryError) {
                  console.error(`Failed to query subscriptions:`, queryError);
                  console.log(`Broadcasting business status update to subscribed customers failed due to query error`);
                }
                
                // Send acknowledgment back to the business app
                try {
                  const ackResponse = {
                    type: 'business_status_update_ack',
                    businessId: updateBusinessId,
                    isBusy: isBusy,
                    timestamp: new Date().toISOString(),
                    processed: true
                  };
                  
                  const command = new PostToConnectionCommand({
                    ConnectionId: connectionId,
                    Data: JSON.stringify(ackResponse)
                  });
                  
                  await apiGatewayClient.send(command);
                  console.log(`Business status update acknowledgment sent to ${connectionId}`);
                } catch (ackError) {
                  console.error(`Failed to send status update ack to ${connectionId}:`, ackError);
                }
              } else {
                console.error(`Invalid business status update message:`, message);
              }
              break;
            case 'heartbeat':
            case 'ping':
              console.log(`Heartbeat/Ping from connection ${connectionId}`);
              // Send heartbeat response back to client
              try {
                const heartbeatResponse = {
                  type: 'heartbeat_response',
                  timestamp: new Date().toISOString(),
                  connectionId: connectionId
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(heartbeatResponse)
                });
                
                await apiGatewayClient.send(command);
                console.log(`Heartbeat response sent to ${connectionId}`);
              } catch (heartbeatError) {
                console.error(`Failed to send heartbeat response to ${connectionId}:`, heartbeatError);
              }
              break;
            default:
              console.log(`Unknown message type: ${messageType}`);
          }
    }

    return {
      statusCode: 200,
      body: 'Message received'
    };
    
  } catch (error) {
    console.error('Error handling WebSocket message:', error);
    console.error('Error stack:', error instanceof Error ? error.stack : 'No stack trace');
    console.error('Error type:', typeof error);
    console.error('Error details:', JSON.stringify(error, null, 2));
    
    // Try to send error message back to client if possible
    try {
      const connectionId = event.requestContext?.connectionId;
      const apiId = event.requestContext?.apiId || process.env.WEBSOCKET_API_ID;
      const stage = event.requestContext?.stage || process.env.WEBSOCKET_STAGE;
      const region = process.env.AWS_REGION || 'us-east-1';
      
      if (connectionId && apiId && stage) {
        const apiGatewayClient = new ApiGatewayManagementApiClient({
          endpoint: `https://${apiId}.execute-api.${region}.amazonaws.com/${stage}`
        });
        
        const errorResponse = {
          type: 'error',
          message: 'Internal server error',
          timestamp: new Date().toISOString(),
          connectionId: connectionId
        };
        
        const command = new PostToConnectionCommand({
          ConnectionId: connectionId,
          Data: JSON.stringify(errorResponse)
        });
        
        await apiGatewayClient.send(command);
        console.log('Error response sent to client');
      }
    } catch (sendError) {
      console.error('Failed to send error response to client:', sendError);
    }
    
    return {
      statusCode: 500,
      body: JSON.stringify({ 
        error: 'Failed to process message',
        details: error instanceof Error ? error.message : 'Unknown error'
      })
    };
  }
};
