const {connectionScopedClient}=require('./subscription-lifecycle');
const {driverStateUpdate}=require('../../websocket-driver-state');
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
  console.log('WebSocket route received', {routeKey:event.requestContext?.routeKey});
  
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
    
    console.log(`WebSocket message: ${connectionId}, route: ${routeKey}`);

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
    const docClient = require('../../merchant-realtime-scope-345').scopedClient(connectionScopedClient(DynamoDBDocumentClient.from(dynamoClient),{connectionId}));
    const SUBSCRIPTIONS_TABLE = requireEnv('WEBSOCKET_SUBSCRIPTIONS_TABLE');

    // Parse the message if it exists
    let message;
    if (body) {
      try {
        message = JSON.parse(body);
        console.log('Parsed WebSocket action', {type:message.type||message.action});
      } catch (e) {
        console.log('Failed to parse message body:', body);
        message = { type: 'unknown', body };
      }
    }
    
    // Handle different message types (support both 'type' and 'action' fields)
    const messageType = message?.type || message?.action;
    if (messageType) {
      switch (messageType) {
        case 'authenticate':
          // Handle driver authentication for unified websocket system
          const { userId, userType, driverId, token } = message;
          console.log(`🔐 Driver authentication request: connectionId=${connectionId}, userId=${userId}, userType=${userType}`);
          
          if (userType === 'driver' && userId && driverId) {
            try {
              // Use universal websocket manager to update connection record
              const { UniversalWebSocketManager } = require('../../universal_websocket_manager');
              const universalManager = new UniversalWebSocketManager();
              
              // Create a dummy event for handleConnect if connection doesn't exist
              const connectEvent = {
                queryStringParameters: {
                  userId: userId,
                  userType: 'driver',
                  entityType: 'driver',
                  driverId: driverId,
                  deviceId: message.deviceId || `driver_device_${driverId}`,
                  platform: message.platform || 'ios',
                  appVersion: message.appVersion || '1.0.0',
                  businessId: message.businessId,
                  token: token
                },
                headers: {},
                requestContext: {
                  connectionId: connectionId,
                  apiId: effectiveApiId
                }
              };
              
              // Ensure connection record exists with correct driver metadata
              await universalManager.handleConnect(connectionId, connectEvent);
              
              console.log(`✅ Driver authenticated successfully: ${userId} on connection ${connectionId}`);
              
              // Send auth_success response
              const authResponse = {
                type: 'auth_success',
                userId: userId,
                userType: 'driver',
                driverId: driverId,
                timestamp: new Date().toISOString(),
                message: 'Driver authentication successful'
              };
              
              const command = new PostToConnectionCommand({
                ConnectionId: connectionId,
                Data: JSON.stringify(authResponse)
              });
              
              await apiGatewayClient.send(command);
              console.log(`✅ Auth success sent to driver ${connectionId}`);
              
            } catch (authError) {
              console.error(`❌ Driver authentication failed:`, authError);
              
              const errorResponse = {
                type: 'auth_error',
                message: 'Authentication failed',
                error: authError.message,
                timestamp: new Date().toISOString()
              };
              
              try {
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(errorResponse)
                });
                await apiGatewayClient.send(command);
              } catch (sendError) {
                console.error(`❌ Failed to send auth error:`, sendError);
              }
            }
          } else {
            console.warn(`⚠️ Invalid driver authentication request: userType=${userType}, userId=${userId}, driverId=${driverId}`);
            
            const errorResponse = {
              type: 'auth_error',
              message: 'Invalid driver authentication data',
              timestamp: new Date().toISOString()
            };
            
            try {
              const command = new PostToConnectionCommand({
                ConnectionId: connectionId,
                Data: JSON.stringify(errorResponse)
              });
              await apiGatewayClient.send(command);
            } catch (sendError) {
              console.error(`❌ Failed to send auth error:`, sendError);
            }
          }
          break;

        case 'connect':
          // Handle driver connect messages (alias for authenticate)
          if (message.userType === 'driver') {
            console.log(`🔗 Driver connect request (treating as authenticate): connectionId=${connectionId}`);
            // Reprocess as authenticate
            message.type = 'authenticate';
            message.action = 'authenticate';
            // Call the authenticate handler above by falling through
            const authMessage = { ...message, type: 'authenticate', action: 'authenticate' };
            const authEvent = { ...event, body: JSON.stringify(authMessage) };
            return await exports.handler(authEvent);
          }
          // For non-driver connect messages, fall through to default
          break;

        case 'heartbeat':
        case 'ping':
          // Handle heartbeat/ping messages AND UPDATE DYNAMODB
          console.log(`💓 Heartbeat from ${connectionId} - UPDATING DYNAMODB`);
          try {
            const now = new Date().toISOString();

            // Schema-aware heartbeat update via universal manager
            const { UniversalWebSocketManager } = require('../../universal_websocket_manager');
            const universalManager = new UniversalWebSocketManager();
            const updateResult = await universalManager.updateHeartbeat(connectionId);
            console.log(`✅ DynamoDB heartbeat updated for ${connectionId}:`, updateResult);
            
            // Send heartbeat acknowledgment
            const heartbeatResponse = {
              type: 'heartbeat_ack',
              timestamp: now,
              connectionId: connectionId,
              status: 'active'
            };
            
            const command = new PostToConnectionCommand({
              ConnectionId: connectionId,
              Data: JSON.stringify(heartbeatResponse)
            });
            
            await apiGatewayClient.send(command);
            console.log(`✅ Heartbeat ACK sent to ${connectionId}`);
          } catch (error) {
            console.error(`❌ Failed to process heartbeat for ${connectionId}:`, error);
          }
          break;

        case 'start_searching':
        case 'driver_searching':
        case 'driver_online':
case 'driverOnline':
          // Handle driver start searching
          console.log(`🔍 Driver start searching from ${connectionId}:`, message);
          try {
            const { UpdateCommand: DDBUpdateCommand } = require('@aws-sdk/lib-dynamodb');
            const driverId = message.driverId || message.userId;
            const lat = message.lat;
            const lng = message.lng;
            
            if (driverId) {
              // Update WizzDriverLiveState table
              const envName = process.env.WEBSOCKET_STAGE || process.env.ENVIRONMENT || process.env.Environment || 'dev';
              const DRIVER_LIVE_STATE_TABLE = process.env.DRIVER_LIVE_STATE_TABLE || `WizzDriverLiveState_${envName}`;
              const updateParams = {
                TableName: DRIVER_LIVE_STATE_TABLE,
                Key: { driverId: driverId },
                UpdateExpression: 'SET #status = :available, isSearching = :searching, searchStartedAt = :startTime, lastUpdated = :updated, connectionStatus = :connected, connectionId = :connId',
                ExpressionAttributeNames: {
                  '#status': 'status'
                },
                ExpressionAttributeValues: {
                  ':available': 'available',
                  ':searching': true,
                  ':startTime': new Date().toISOString(),
                  ':updated': new Date().toISOString(),
                  ':connected': 'connected',
                  ':connId': connectionId
                }
              };
              
              // Add GPS if provided
              if (lat && lng) {
                updateParams.UpdateExpression += ', lat = :lat, lng = :lng, lastLocationUpdate = :locTime';
                updateParams.ExpressionAttributeValues[':lat'] = lat;
                updateParams.ExpressionAttributeValues[':lng'] = lng;
                updateParams.ExpressionAttributeValues[':locTime'] = new Date().toISOString();
              }
              
              await driverStateUpdate(docClient, connectionId, driverId, updateParams);
              console.log(`✅ Driver ${driverId} started searching - WizzDriverLiveState updated`);
              
              // Send confirmation
              const confirmMessage = {
                type: 'search_started_confirmed',
                action: 'search_started',
                driverId: driverId,
                searchingActive: true,
                timestamp: new Date().toISOString(),
                message: 'تم بدء البحث عن الطلبات بنجاح'
              };
              
              const command = new PostToConnectionCommand({
                ConnectionId: connectionId,
                Data: JSON.stringify(confirmMessage)
              });
              await apiGatewayClient.send(command);
              console.log(`✅ Start searching confirmation sent to ${connectionId}`);
            }
          } catch (error) {
            console.error(`❌ Failed to handle start_searching for ${connectionId}:`, error);
          }
          break;

        case 'stop_searching':
        case 'driver_stop_searching':
        case 'driver_offline':
          // Handle driver stop searching
          console.log(`🛑 Driver stop searching from ${connectionId}:`, message);
          try {
            const { UpdateCommand: DDBUpdateCommand } = require('@aws-sdk/lib-dynamodb');
            const driverId = message.driverId || message.userId;
            
            if (driverId) {
              // Update WizzDriverLiveState table
              const envName = process.env.WEBSOCKET_STAGE || process.env.ENVIRONMENT || process.env.Environment || 'dev';
              const DRIVER_LIVE_STATE_TABLE = process.env.DRIVER_LIVE_STATE_TABLE || `WizzDriverLiveState_${envName}`;
              await driverStateUpdate(docClient, connectionId, driverId, {
                TableName: DRIVER_LIVE_STATE_TABLE,
                Key: { driverId: driverId },
                UpdateExpression: 'SET #status = :offline, isSearching = :searching, searchStoppedAt = :stopTime, lastUpdated = :updated',
                ExpressionAttributeNames: {
                  '#status': 'status'
                },
                ExpressionAttributeValues: {
                  ':offline': 'offline',
                  ':searching': false,
                  ':stopTime': new Date().toISOString(),
                  ':updated': new Date().toISOString()
                }
              });
              console.log(`✅ Driver ${driverId} stopped searching - WizzDriverLiveState updated`);
              
              // Send confirmation
              const confirmMessage = {
                type: 'search_stopped_confirmed',
                action: 'search_stopped',
                driverId: driverId,
                searchingActive: false,
                timestamp: new Date().toISOString(),
                message: 'تم إيقاف البحث بنجاح'
              };
              
              const command = new PostToConnectionCommand({
                ConnectionId: connectionId,
                Data: JSON.stringify(confirmMessage)
              });
              await apiGatewayClient.send(command);
              console.log(`✅ Stop searching confirmation sent to ${connectionId}`);
            }
          } catch (error) {
            console.error(`❌ Failed to handle stop_searching for ${connectionId}:`, error);
          }
          break;

        case 'driver_status':
        case 'subscribe_driver_offers':
          // Handle driver-specific messages
          console.log(`🚗 Driver message (${messageType}) from ${connectionId}`);
          try {
            const driverResponse = {
              type: `${messageType}_ack`,
              timestamp: new Date().toISOString(),
              connectionId: connectionId,
              message: `${messageType} received`
            };
            
            const command = new PostToConnectionCommand({
              ConnectionId: connectionId,
              Data: JSON.stringify(driverResponse)
            });
            
            await apiGatewayClient.send(command);
            console.log(`✅ Driver ${messageType} ack sent to ${connectionId}`);
          } catch (error) {
            console.error(`❌ Failed to send driver ${messageType} ack to ${connectionId}:`, error);
          }
          break;

            case 'subscribe_order':
          const orderId = message.order_id || message.orderId;
          const orderUserId = message.user_id || message.userId;
          console.log(`🔔 Subscribing connection ${connectionId} to order updates for order ${orderId}, user: ${orderUserId}`);
          
          // Store order subscription in DynamoDB
          try {
            const subscriptionItem = {
              subscriptionId: `${connectionId}_${orderId}`, // Primary key
              connectionId: connectionId,
              orderId: orderId,
              userId: orderUserId,
              subscriptionType: 'order_tracking',
              timestamp: new Date().toISOString(),
              ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
            };
            
            await docClient.send(new PutCommand({
              TableName: SUBSCRIPTIONS_TABLE,
              Item: subscriptionItem
            }));
            
            console.log(`✅ Stored order tracking subscription for ${connectionId} -> order ${orderId}`);
          } catch (dbError) {
            console.error(`❌ Failed to store order subscription in DynamoDB:`, dbError);
          }
          
          // Send acknowledgment back to client
          try {
            const ackResponse = {
              type: 'subscription_ack',
              action: 'subscribe_order',
              orderId: orderId,
              timestamp: new Date().toISOString(),
              connectionId: connectionId,
              message: 'Successfully subscribed to order updates'
            };
            
            const command = new PostToConnectionCommand({
              ConnectionId: connectionId,
              Data: JSON.stringify(ackResponse)
            });
            
            await apiGatewayClient.send(command);
            console.log(`✅ Order subscription acknowledgment sent to ${connectionId}`);
          } catch (ackError) {
            console.error(`❌ Failed to send order subscription acknowledgment to ${connectionId}:`, ackError);
          }
          break;

        case 'subscribe':
        case 'subscribe_business_status':
          const businessId = message.business_id || message.businessId || message.id;
          const businessUserId = message.user_id || message.userId;
          console.log(`Subscribing connection ${connectionId} to business status ${businessId} for user ${businessUserId}`);
          
          // Store this subscription in DynamoDB
          try {
            const subscriptionId = businessId ? `${connectionId}_${businessId}` : `${connectionId}_general`;
            const subscriptionItem = {
              subscriptionId: subscriptionId, // Primary key
              connectionId: connectionId,
              businessId: businessId || null,
              userId: businessUserId,
              subscriptionType: businessId ? 'business_status' : 'general',
              timestamp: new Date().toISOString(),
              ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
            };
            
            await docClient.send(new PutCommand({
              TableName: SUBSCRIPTIONS_TABLE,
              Item: subscriptionItem
            }));
            
            console.log(`✅ Stored ${businessId ? 'business status' : 'general'} subscription for ${connectionId} -> ${businessId || 'general'}`);
          } catch (dbError) {
            console.error(`❌ Failed to store subscription in DynamoDB:`, dbError);
          }
          
          // Send acknowledgment back to client
          try {
            const ackResponse = {
              type: 'subscription_ack',
              action: businessId ? 'subscribe_business_status' : 'subscribe',
              businessId: businessId,
              timestamp: new Date().toISOString(),
              connectionId: connectionId,
              message: `Successfully subscribed to ${businessId ? 'business status updates' : 'general updates'}`
            };
            
            const command = new PostToConnectionCommand({
              ConnectionId: connectionId,
              Data: JSON.stringify(ackResponse)
            });
                
                await apiGatewayClient.send(command);
                console.log(`✅ ${businessId ? 'Business status' : 'General'} subscription acknowledgment sent to ${connectionId}`);
              } catch (ackError) {
                console.error(`❌ Failed to send subscription ack to ${connectionId}:`, ackError);
              }
              break;

            case 'unsubscribe':
            case 'unsubscribe_business_status':
              const unsubBusinessId = message.business_id || message.businessId || message.id;
              console.log(`Unsubscribing connection ${connectionId} from ${unsubBusinessId ? `business status ${unsubBusinessId}` : 'general subscriptions'}`);
              
              // Remove subscription from DynamoDB
              try {
                const subscriptionId = unsubBusinessId ? `${connectionId}_${unsubBusinessId}` : `${connectionId}_general`;
                await docClient.send(new DeleteCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Key: {
                    subscriptionId: subscriptionId
                  }
                }));
                console.log(`✅ Removed ${unsubBusinessId ? 'business status' : 'general'} subscription for ${connectionId} -> ${unsubBusinessId || 'general'}`);
                
                // Send acknowledgment back to client
                try {
                  const ackResponse = {
                    type: 'unsubscribe_ack',
                    action: unsubBusinessId ? 'unsubscribe_business_status' : 'unsubscribe',
                    businessId: unsubBusinessId,
                    timestamp: new Date().toISOString(),
                    connectionId: connectionId,
                    message: `Successfully unsubscribed from ${unsubBusinessId ? 'business status updates' : 'general updates'}`
                  };
                  
                  const command = new PostToConnectionCommand({
                    ConnectionId: connectionId,
                    Data: JSON.stringify(ackResponse)
                  });
                  
                  await apiGatewayClient.send(command);
                  console.log(`✅ Unsubscribe acknowledgment sent to ${connectionId}`);
                } catch (ackError) {
                  console.error(`❌ Failed to send unsubscribe ack to ${connectionId}:`, ackError);
                }
              } catch (dbError) {
                console.error(`❌ Failed to remove subscription from DynamoDB:`, dbError);
              }
              break;

            case 'unsubscribe_order':
              const unsubOrderId = message.order_id || message.orderId;
              console.log(`Unsubscribing connection ${connectionId} from order ${unsubOrderId}`);
              break;

            case 'subscribe_user_orders':
              const subscribeUserId = message.user_id;
              console.log(`🎯 Subscribing connection ${connectionId} to all orders for user: ${subscribeUserId}`);
              
              // Store user orders subscription in DynamoDB
              try {
                const subscriptionItem = {
                  subscriptionId: `${connectionId}_user_orders_${subscribeUserId}`,
                  connectionId: connectionId,
                  userId: subscribeUserId,
                  subscriptionType: 'user_orders',
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
                };
                
                await docClient.send(new PutCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Item: subscriptionItem
                }));
                
                console.log(`✅ Stored user orders subscription for ${connectionId} -> user ${userId}`);
                
                // Send acknowledgment
                const ackResponse = {
                  type: 'subscription_ack',
                  action: 'subscribe_user_orders',
                  userId: userId,
                  timestamp: new Date().toISOString(),
                  message: 'Successfully subscribed to user orders'
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(ackResponse)
                });
                
                await apiGatewayClient.send(command);
                console.log(`User orders subscription acknowledgment sent to ${connectionId}`);
              } catch (error) {
                console.error(`❌ Failed to store user orders subscription:`, error);
              }
              break;

            case 'subscribe_guest_orders':
              const guestToken = message.guest_token;
              console.log(`🎭 Subscribing connection ${connectionId} to all orders for guest: ${guestToken}`);
              
              // Store guest orders subscription in DynamoDB
              try {
                const subscriptionItem = {
                  subscriptionId: `${connectionId}_guest_orders_${guestToken}`,
                  connectionId: connectionId,
                  guestToken: guestToken,
                  subscriptionType: 'guest_orders',
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
                };
                
                await docClient.send(new PutCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Item: subscriptionItem
                }));
                
                console.log(`✅ Stored guest orders subscription for ${connectionId} -> guest ${guestToken}`);
                
                // Send acknowledgment
                const ackResponse = {
                  type: 'subscription_ack',
                  action: 'subscribe_guest_orders',
                  guestToken: guestToken,
                  timestamp: new Date().toISOString(),
                  message: 'Successfully subscribed to guest orders'
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(ackResponse)
                });
                
                await apiGatewayClient.send(command);
                console.log(`Guest orders subscription acknowledgment sent to ${connectionId}`);
              } catch (error) {
                console.error(`❌ Failed to store guest orders subscription:`, error);
              }
              break;

            case 'unsubscribe_user_orders':
              const unsubUserId = message.user_id;
              console.log(`Unsubscribing connection ${connectionId} from user orders ${unsubUserId}`);
              
              try {
                await docClient.send(new DeleteCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Key: {
                    subscriptionId: `${connectionId}_user_orders_${unsubUserId}`
                  }
                }));
                console.log(`Removed user orders subscription for ${connectionId} -> ${unsubUserId}`);
              } catch (dbError) {
                console.error(`Failed to remove user orders subscription:`, dbError);
              }
              break;

            case 'unsubscribe_guest_orders':
              const unsubGuestToken = message.guest_token;
              console.log(`Unsubscribing connection ${connectionId} from guest orders ${unsubGuestToken}`);
              
              try {
                await docClient.send(new DeleteCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Key: {
                    subscriptionId: `${connectionId}_guest_orders_${unsubGuestToken}`
                  }
                }));
                console.log(`Removed guest orders subscription for ${connectionId} -> ${unsubGuestToken}`);
              } catch (dbError) {
                console.error(`Failed to remove guest orders subscription:`, dbError);
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
                              subscriptionId: `${subscription.connectionId}_${updateBusinessId}`
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

            case 'WORKING_HOURS_UPDATE':
            case 'working_hours_update':
              const whUpdateBusinessId = message.business_id || message.businessId;
              const workingHours = message.working_hours || message.workingHours;
              const whUpdateUserId = message.user_id || message.userId;
              
              if (whUpdateBusinessId && workingHours) {
                console.log(`Processing working hours update for business ${whUpdateBusinessId}`);
                
                // Create the broadcast message for customers
                const customerWorkingHoursMessage = {
                  type: 'WORKING_HOURS_UPDATE',
                  businessId: whUpdateBusinessId,
                  workingHours: workingHours,
                  timestamp: new Date().toISOString()
                };
                
                console.log(`Broadcasting working hours update: ${JSON.stringify(customerWorkingHoursMessage)}`);
                
                // Query DynamoDB to find all customers subscribed to this business
                try {
                  console.log(`Querying subscriptions for business working hours: ${whUpdateBusinessId}`);
                  
                  const scanParams = {
                    TableName: SUBSCRIPTIONS_TABLE,
                    FilterExpression: 'businessId = :businessId AND subscriptionType = :subType',
                    ExpressionAttributeValues: {
                      ':businessId': whUpdateBusinessId,
                      ':subType': 'business_status'
                    }
                  };
                  
                  const result = await docClient.send(new ScanCommand(scanParams));
                  const subscriptions = result.Items || [];
                  
                  console.log(`Found ${subscriptions.length} subscriptions for business ${whUpdateBusinessId} working hours update`);
                  
                  // Send the working hours update to each subscribed customer
                  const broadcastPromises = subscriptions.map(async (subscription) => {
                    try {
                      const customerConnectionId = subscription.connectionId;
                      console.log(`Sending working hours update to customer connection: ${customerConnectionId}`);
                      
                      const command = new PostToConnectionCommand({
                        ConnectionId: customerConnectionId,
                        Data: JSON.stringify(customerWorkingHoursMessage)
                      });
                      
                      await apiGatewayClient.send(command);
                      console.log(`✅ Sent working hours update to ${customerConnectionId}`);
                      return { success: true, connectionId: customerConnectionId };
                    } catch (sendError) {
                      console.error(`❌ Failed to send working hours update to ${subscription.connectionId}:`, sendError);
                      
                      // If connection is stale, remove the subscription
                      if (sendError.name === 'GoneException') {
                        try {
                          await docClient.send(new DeleteCommand({
                            TableName: SUBSCRIPTIONS_TABLE,
                            Key: {
                              subscriptionId: `${subscription.connectionId}_${whUpdateBusinessId}`
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
                  console.log(`📡 Working hours broadcast complete: ${successCount}/${subscriptions.length} customers notified`);
                  
                } catch (queryError) {
                  console.error(`Failed to query subscriptions for working hours update:`, queryError);
                }
                
                // Send acknowledgment back to the business app
                try {
                  const ackResponse = {
                    type: 'working_hours_update_ack',
                    businessId: whUpdateBusinessId,
                    timestamp: new Date().toISOString(),
                    processed: true
                  };
                  
                  const command = new PostToConnectionCommand({
                    ConnectionId: connectionId,
                    Data: JSON.stringify(ackResponse)
                  });
                  
                  await apiGatewayClient.send(command);
                  console.log(`Working hours update acknowledgment sent to ${connectionId}`);
                } catch (ackError) {
                  console.error(`Failed to send working hours update ack to ${connectionId}:`, ackError);
                }
              } else {
                console.error(`Invalid working hours update message:`, message);
              }
              break;

            case 'REGISTER_CONNECTION':
            case 'register_connection':
              const merchantId = message.merchant_id || message.merchantId || message.businessId || message.business_id;
              const deviceInfo = message.device_info || message.deviceInfo || {};
              console.log(`Registering merchant connection ${connectionId} for merchant ${merchantId}`);
              
              // Validate merchantId
              if (!merchantId) {
                console.error(`Missing merchantId in registration message:`, message);
                try {
                  const errorResponse = {
                    type: 'REGISTRATION_ERROR',
                    error: 'Missing merchant_id in registration message',
                    timestamp: new Date().toISOString()
                  };
                  
                  const errorCommand = new PostToConnectionCommand({
                    ConnectionId: connectionId,
                    Data: JSON.stringify(errorResponse)
                  });
                  
                  await apiGatewayClient.send(errorCommand);
                } catch (errorSendFail) {
                  console.error(`Failed to send registration error:`, errorSendFail);
                }
                break;
              }
              
              // Store merchant connection in DynamoDB connections table
              try {
                const connectionItem = {
                  PK: `CONNECTION#${connectionId}`,
                  SK: `MERCHANT#${merchantId}`,
                  GSI1PK: `MERCHANT#${merchantId}`,
                  GSI1SK: `CONNECTION#${connectionId}`,
                  connectionId: connectionId,
                  merchantId: merchantId,
                  deviceInfo: deviceInfo,
                  connectionType: 'merchant',
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
                };
                
                // Store in the connections table (not subscriptions table)
                const CONNECTIONS_TABLE = process.env.WEBSOCKET_CONNECTIONS_TABLE || process.env.CONNECTIONS_TABLE || requireEnv('WEBSOCKET_CONNECTIONS_TABLE');
                await docClient.send(new PutCommand({
                  TableName: CONNECTIONS_TABLE,
                  Item: connectionItem
                }));
                
                console.log(`Stored merchant connection for ${connectionId} -> merchant ${merchantId}`);
                
                // Send registration acknowledgment back to merchant
                const regResponse = {
                  type: 'REGISTRATION_ACK',
                  merchantId: merchantId,
                  connectionId: connectionId,
                  timestamp: new Date().toISOString(),
                  status: 'registered'
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(regResponse)
                });
                
                await apiGatewayClient.send(command);
                console.log(`Registration acknowledgment sent to merchant ${connectionId}`);
                
              } catch (regError) {
                console.error(`Failed to register merchant connection:`, regError);
                
                // Send error response
                try {
                  const errorResponse = {
                    type: 'REGISTRATION_ERROR',
                    error: 'Failed to register connection',
                    timestamp: new Date().toISOString()
                  };
                  
                  const errorCommand = new PostToConnectionCommand({
                    ConnectionId: connectionId,
                    Data: JSON.stringify(errorResponse)
                  });
                  
                  await apiGatewayClient.send(errorCommand);
                } catch (errorSendFail) {
                  console.error(`Failed to send registration error:`, errorSendFail);
                }
              }
              break;

            case 'SUBSCRIBE_ORDERS':
            case 'subscribe_orders':
              const subMerchantId = message.merchant_id || message.merchantId || message.businessId || message.business_id;
              console.log(`Subscribing merchant connection ${connectionId} to orders for merchant ${subMerchantId}`);
              
              // Store order subscription in DynamoDB
              try {
                const orderSubscriptionItem = {
                  subscriptionId: `orders_${connectionId}_${subMerchantId}`, // Primary key
                  connectionId: connectionId,
                  merchantId: subMerchantId,
                  subscriptionType: 'merchant_orders',
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
                };
                
                await docClient.send(new PutCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Item: orderSubscriptionItem
                }));
                
                console.log(`Stored order subscription for merchant ${connectionId} -> ${subMerchantId}`);
                
                // Send subscription acknowledgment back to merchant
                const subResponse = {
                  type: 'ORDER_SUBSCRIPTION_ACK',
                  merchantId: subMerchantId,
                  connectionId: connectionId,
                  timestamp: new Date().toISOString(),
                  status: 'subscribed_to_orders'
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(subResponse)
                });
                
                await apiGatewayClient.send(command);
                console.log(`Order subscription acknowledgment sent to merchant ${connectionId}`);
                
              } catch (subError) {
                console.error(`Failed to subscribe to orders:`, subError);
                
                // Send error response
                try {
                  const errorResponse = {
                    type: 'SUBSCRIPTION_ERROR',
                    error: 'Failed to subscribe to orders',
                    timestamp: new Date().toISOString()
                  };
                  
                  const errorCommand = new PostToConnectionCommand({
                    ConnectionId: connectionId,
                    Data: JSON.stringify(errorResponse)
                  });
                  
                  await apiGatewayClient.send(errorCommand);
                } catch (errorSendFail) {
                  console.error(`Failed to send subscription error:`, errorSendFail);
                }
              }
              break;

            case 'UPDATE_ORDER_STATUS':
            case 'update_order_status':
              const statusOrderId = message.order_id || message.orderId;
              const newStatus = message.status || message.newStatus;
              const statusMerchantId = message.merchant_id || message.merchantId || message.businessId || message.business_id;
              const statusUserId = message.user_id || message.userId || message.customerId;
              
              console.log(`Received order status update: Order ${statusOrderId} -> ${newStatus} from merchant ${statusMerchantId}`);
              
              if (statusOrderId && newStatus && statusMerchantId) {
                try {
                  // Find the customer connection for this order
                  const scanParams = {
                    TableName: SUBSCRIPTIONS_TABLE,
                    FilterExpression: 'subscriptionType = :subType',
                    ExpressionAttributeValues: {
                      ':subType': 'order_tracking'
                    }
                  };
                  
                  const result = await docClient.send(new ScanCommand(scanParams));
                  const orderSubscriptions = (result.Items || []).filter(sub => 
                    sub.orderId === statusOrderId || sub.order_id === statusOrderId
                  );
                  
                  console.log(`Found ${orderSubscriptions.length} order tracking subscriptions for order ${statusOrderId}`);
                  
                  // Create customer notification message
                  const customerNotification = {
                    type: 'ORDER_STATUS_UPDATE',
                    orderId: statusOrderId,
                    status: newStatus,
                    merchantId: statusMerchantId,
                    timestamp: new Date().toISOString()
                  };
                  
                  // Send to all subscribed customers
                  const customerNotifyPromises = orderSubscriptions.map(async (subscription) => {
                    try {
                      const customerConnectionId = subscription.connectionId;
                      console.log(`Sending order status update to customer: ${customerConnectionId}`);
                      
                      const command = new PostToConnectionCommand({
                        ConnectionId: customerConnectionId,
                        Data: JSON.stringify(customerNotification)
                      });
                      
                      await apiGatewayClient.send(command);
                      console.log(`✅ Order status update sent to customer ${customerConnectionId}`);
                      return { success: true, connectionId: customerConnectionId };
                    } catch (sendError) {
                      console.error(`❌ Failed to send order update to ${subscription.connectionId}:`, sendError);
                      
                      // Clean up stale connections
                      if (sendError.name === 'GoneException') {
                        try {
                          await docClient.send(new DeleteCommand({
                            TableName: SUBSCRIPTIONS_TABLE,
                            Key: { subscriptionId: subscription.subscriptionId }
                          }));
                          console.log(`Removed stale order subscription: ${subscription.connectionId}`);
                        } catch (deleteError) {
                          console.error(`Failed to remove stale subscription:`, deleteError);
                        }
                      }
                      return { success: false, connectionId: subscription.connectionId, error: sendError.message };
                    }
                  });
                  
                  const customerResults = await Promise.all(customerNotifyPromises);
                  const customerSuccessCount = customerResults.filter(r => r.success).length;
                  console.log(`📱 Customer notification complete: ${customerSuccessCount}/${orderSubscriptions.length} customers notified`);
                  
                  // Send acknowledgment back to merchant
                  const merchantAck = {
                    type: 'ORDER_STATUS_UPDATE_ACK',
                    orderId: statusOrderId,
                    status: newStatus,
                    merchantId: statusMerchantId,
                    timestamp: new Date().toISOString(),
                    customersNotified: customerSuccessCount,
                    processed: true
                  };
                  
                  const merchantCommand = new PostToConnectionCommand({
                    ConnectionId: connectionId,
                    Data: JSON.stringify(merchantAck)
                  });
                  
                  await apiGatewayClient.send(merchantCommand);
                  console.log(`Order status update acknowledgment sent to merchant ${connectionId}`);
                  
                } catch (statusError) {
                  console.error(`Failed to process order status update:`, statusError);
                  
                  // Send error response to merchant
                  try {
                    const errorResponse = {
                      type: 'ORDER_STATUS_UPDATE_ERROR',
                      orderId: statusOrderId,
                      error: 'Failed to process status update',
                      timestamp: new Date().toISOString()
                    };
                    
                    const errorCommand = new PostToConnectionCommand({
                      ConnectionId: connectionId,
                      Data: JSON.stringify(errorResponse)
                    });
                    
                    await apiGatewayClient.send(errorCommand);
                  } catch (errorSendFail) {
                    console.error(`Failed to send status update error:`, errorSendFail);
                  }
                }
              } else {
                console.error(`Invalid order status update message - missing required fields:`, message);
              }
              break;

            case 'SUBSCRIBE_ORDER_TRACKING':
            case 'subscribe_order_tracking':
              const trackingOrderId = message.order_id || message.orderId;
              const trackingUserId = message.user_id || message.userId;
              console.log(`Subscribing customer connection ${connectionId} to order tracking for order ${trackingOrderId}`);
              
              // Store order tracking subscription in DynamoDB
              try {
                const trackingSubscriptionItem = {
                  subscriptionId: `order_tracking_${connectionId}_${trackingOrderId}`, // Primary key
                  connectionId: connectionId,
                  orderId: trackingOrderId,
                  userId: trackingUserId,
                  subscriptionType: 'order_tracking',
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (4 * 60 * 60) // 4 hours TTL (order lifetime)
                };
                
                await docClient.send(new PutCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Item: trackingSubscriptionItem
                }));
                
                console.log(`Stored order tracking subscription for customer ${connectionId} -> order ${trackingOrderId}`);
                
                // Send subscription acknowledgment back to customer
                const trackingResponse = {
                  type: 'ORDER_TRACKING_SUBSCRIPTION_ACK',
                  orderId: trackingOrderId,
                  userId: trackingUserId,
                  connectionId: connectionId,
                  timestamp: new Date().toISOString(),
                  status: 'subscribed_to_order_tracking'
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(trackingResponse)
                });
                
                await apiGatewayClient.send(command);
                console.log(`Order tracking subscription acknowledgment sent to customer ${connectionId}`);
                
              } catch (trackingError) {
                console.error(`Failed to subscribe to order tracking:`, trackingError);
                
                // Send error response
                try {
                  const errorResponse = {
                    type: 'ORDER_TRACKING_SUBSCRIPTION_ERROR',
                    orderId: trackingOrderId,
                    error: 'Failed to subscribe to order tracking',
                    timestamp: new Date().toISOString()
                  };
                  
                  const errorCommand = new PostToConnectionCommand({
                    ConnectionId: connectionId,
                    Data: JSON.stringify(errorResponse)
                  });
                  
                  await apiGatewayClient.send(errorCommand);
                } catch (errorSendFail) {
                  console.error(`Failed to send order tracking subscription error:`, errorSendFail);
                }
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

            // Driver WebSocket Connection Registration (NEW - for driver app compatibility)
            case 'connection':
            case 'connect':
              console.log(`🚗 Driver connection request: ${message.driverId || message.userId}`);
              try {
                const driverId = message.driverId || message.userId;
                const userType = message.userType || 'driver';
                
                // Store driver connection in DynamoDB subscriptions table
                const connectionItem = {
                  subscriptionId: `driver_connection_${connectionId}_${driverId}`,
                  connectionId: connectionId,
                  userId: driverId,
                  userType: userType,
                  subscriptionType: 'driver_connection',
                  entityType: userType,
                  platform: message.platform || 'ios',
                  appVersion: message.appVersion || '1.0.0',
                  deviceId: message.deviceId || `driver_device_${driverId}`,
                  businessId: message.businessId,
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
                };
                
                await docClient.send(new PutCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Item: connectionItem
                }));
                
                console.log(`✅ Driver connection stored: ${connectionId} -> ${driverId}`);
                
                const response = {
                  type: 'connection_ack',
                  action: 'connect',
                  message: 'Driver connection registered successfully',
                  driverId: driverId,
                  userType: userType,
                  timestamp: new Date().toISOString(),
                  connectionId: connectionId
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(response)
                });
                
                await apiGatewayClient.send(command);
                console.log(`✅ Driver connection acknowledgment sent to ${connectionId}`);
              } catch (error) {
                console.error(`❌ Failed to register driver connection for ${connectionId}:`, error);
              }
              break;

            // Driver WebSocket Subscription Registration (NEW - for driver app compatibility)
            case 'subscription':
              console.log(`🔔 Driver subscription request: ${message.driverId || message.userId} to ${message.topic || message.subscriptionType}`);
              try {
                const driverId = message.driverId || message.userId;
                const subscriptionType = message.subscriptionType || message.topic || 'driver_orders';
                const topic = message.topic || message.subscriptionType;
                
                const subscriptionItem = {
                  subscriptionId: `driver_${subscriptionType}_${connectionId}_${driverId}`,
                  connectionId: connectionId,
                  userId: driverId,
                  userType: message.userType || 'driver',
                  subscriptionType: subscriptionType,
                  topic: topic,
                  timestamp: new Date().toISOString(),
                  ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
                };
                
                await docClient.send(new PutCommand({
                  TableName: SUBSCRIPTIONS_TABLE,
                  Item: subscriptionItem
                }));
                
                console.log(`✅ Driver subscription stored: ${connectionId} -> ${subscriptionType}`);
                
                const response = {
                  type: 'subscription_ack',
                  action: 'subscribe',
                  message: 'Driver subscribed successfully',
                  topic: topic,
                  subscriptionType: subscriptionType,
                  timestamp: new Date().toISOString(),
                  connectionId: connectionId
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(response)
                });
                
                await apiGatewayClient.send(command);
                console.log(`✅ Driver subscription acknowledgment sent to ${connectionId}`);
              } catch (error) {
                console.error(`❌ Failed to subscribe driver for ${connectionId}:`, error);
              }
              break;

            // Driver Registration (NEW - for driver app compatibility)
            case 'register':
              console.log(`🚗 Driver registration: ${message.driverId || message.userId}`);
              try {
                const driverId = message.driverId || message.userId;
                
                const response = {
                  type: 'registration_ack',
                  action: 'register',
                  message: 'Driver registered successfully',
                  driverId: driverId,
                  userType: message.userType || 'driver',
                  status: 'registered',
                  timestamp: new Date().toISOString(),
                  connectionId: connectionId
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(response)
                });
                
                await apiGatewayClient.send(command);
                console.log(`✅ Driver registration acknowledgment sent to ${connectionId}`);
              } catch (error) {
                console.error(`❌ Failed to send driver registration ack to ${connectionId}:`, error);
              }
              break;

            // Driver Availability (NEW - for driver app compatibility)
            case 'driver_available':
            case 'driver_unavailable':
              console.log(`🚗 Driver availability update: ${message.driverId || message.userId} -> ${messageType}`);
              try {
                const driverId = message.driverId || message.userId;
                const isAvailable = messageType === 'driver_available';
                
                const response = {
                  type: 'availability_ack',
                  action: messageType,
                  message: `Driver ${isAvailable ? 'available' : 'unavailable'} status updated`,
                  driverId: driverId,
                  availability: isAvailable,
                  timestamp: new Date().toISOString(),
                  connectionId: connectionId
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(response)
                });
                
                await apiGatewayClient.send(command);
                console.log(`✅ Driver availability acknowledgment sent to ${connectionId}`);
              } catch (error) {
                console.error(`❌ Failed to send driver availability ack to ${connectionId}:`, error);
              }
              break;

          default:
            console.log(`Unknown message type: ${messageType}`);
            
            // Handle special messages from Central Platform for drivers
            if (message.action === 'driver_assigned' && message.order_id) {
              console.log(`🎯 Driver assignment notification: ${message.order_id}`);
              try {
                // This is a driver assignment from the Central Platform
                // Forward it directly to the driver as a new order notification
                const driverOrderNotification = {
                  type: 'new_order_assignment',
                  action: 'driver_assigned',
                  order_id: message.order_id,
                  assignment_id: message.assignment_id || `ASSIGN_${Date.now()}`,
                  timeout: message.timeout || 30,
                  customer_name: message.customer_name || 'عميل',
                  restaurant_name: message.restaurant_name || 'مطعم',
                  delivery_address: message.delivery_address || 'عنوان التسليم',
                  total_amount: message.total_amount || 0,
                  currency: message.currency || 'IQD',
                  estimated_distance: message.estimated_distance || '2.5',
                  pickup_location: message.pickup_location || {},
                  delivery_location: message.delivery_location || {},
                  timestamp: new Date().toISOString(),
                  connectionId: connectionId
                };
                
                const command = new PostToConnectionCommand({
                  ConnectionId: connectionId,
                  Data: JSON.stringify(driverOrderNotification)
                });
                
                await apiGatewayClient.send(command);
                console.log(`✅ Driver order assignment forwarded to ${connectionId}`);
              } catch (error) {
                console.error(`❌ Failed to forward driver assignment to ${connectionId}:`, error);
              }
              break;
            }
            
            // Send a generic acknowledgment for unknown messages
            try {
              const unknownResponse = {
                type: 'unknown_message_ack',
                receivedType: messageType,
                timestamp: new Date().toISOString(),
                connectionId: connectionId,
                message: 'Message received but type not recognized'
              };
              
              const command = new PostToConnectionCommand({
                ConnectionId: connectionId,
                Data: JSON.stringify(unknownResponse)
              });
              
              await apiGatewayClient.send(command);
              console.log(`Unknown message acknowledgment sent to ${connectionId}`);
            } catch (ackError) {
              console.error(`Failed to send unknown message ack to ${connectionId}:`, ackError);
            }
            break;
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
    // Safe error logging
    try {
      console.error('Error details:', JSON.stringify(error, Object.getOwnPropertyNames(error), 2));
    } catch (jsonError) {
      console.error('Error details (safe):', error instanceof Error ? error.message : String(error));
    }
    
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
exports.handler = require('../../merchant-realtime-scope-345').guardDefault(exports.handler);
