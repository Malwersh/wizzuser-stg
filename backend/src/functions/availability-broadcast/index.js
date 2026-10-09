// Real-time Availability Broadcast System
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, ScanCommand, PutCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const CONNECTIONS_TABLE = requireEnv('WEBSOCKET_CONNECTIONS_TABLE');
const AVAILABILITY_SUBSCRIPTIONS_TABLE = requireEnv('AVAILABILITY_SUBSCRIPTIONS_TABLE');

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
};

exports.handler = async (event) => {
  console.log('🔔 Availability Broadcast Event:', JSON.stringify(event, null, 2));

  try {
    // Handle different event sources
    if (event.httpMethod) {
      // HTTP API call
      return await handleHttpRequest(event);
    } else if (event.Records) {
      // DynamoDB Stream or other AWS service trigger
      return await handleStreamEvent(event);
    } else {
      // Direct invocation for broadcasting
      return await handleDirectBroadcast(event);
    }

  } catch (error) {
    console.error('❌ Error in availability broadcast:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'Internal server error',
        error: process.env.NODE_ENV === 'development' ? error.message : undefined
      })
    };
  }
};

async function handleHttpRequest(event) {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 200, headers, body: '' };
  }

  const action = event.pathParameters?.action;
  const requestBody = event.body ? JSON.parse(event.body) : {};

  switch (action) {
    case 'subscribe':
      return await handleSubscribe(event, requestBody);
    case 'unsubscribe':
      return await handleUnsubscribe(event, requestBody);
    case 'broadcast':
      return await handleBroadcastRequest(event, requestBody);
    default:
      return {
        statusCode: 404,
        headers,
        body: JSON.stringify({ success: false, message: 'Action not found' })
      };
  }
}

async function handleSubscribe(event, requestBody) {
  const { connectionId, storeIds, userLocation } = requestBody;
  
  if (!connectionId || !storeIds || !Array.isArray(storeIds)) {
    return {
      statusCode: 400,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'connectionId and storeIds array are required'
      })
    };
  }

  try {
    // Store subscription for each store
    const subscriptionPromises = storeIds.map(async (storeId) => {
      const subscription = {
        connectionId,
        storeId,
        userLocation,
        subscribedAt: new Date().toISOString(),
        lastPing: new Date().toISOString(),
        ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
      };

      return docClient.send(new PutCommand({
        TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
        Item: subscription
      }));
    });

    await Promise.all(subscriptionPromises);

    console.log(`✅ Subscribed connection ${connectionId} to ${storeIds.length} stores`);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        message: `Subscribed to ${storeIds.length} stores`,
        connectionId,
        storeIds
      })
    };

  } catch (error) {
    console.error('❌ Error handling subscription:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'Failed to subscribe',
        error: error.message
      })
    };
  }
}

async function handleUnsubscribe(event, requestBody) {
  const { connectionId, storeIds } = requestBody;
  
  if (!connectionId) {
    return {
      statusCode: 400,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'connectionId is required'
      })
    };
  }

  try {
    if (storeIds && Array.isArray(storeIds)) {
      // Unsubscribe from specific stores
      const deletePromises = storeIds.map(async (storeId) => {
        return docClient.send(new DeleteCommand({
          TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
          Key: { connectionId, storeId }
        }));
      });

      await Promise.all(deletePromises);
      console.log(`✅ Unsubscribed connection ${connectionId} from ${storeIds.length} stores`);

    } else {
      // Unsubscribe from all stores
      const queryCommand = new QueryCommand({
        TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
        KeyConditionExpression: 'connectionId = :connectionId',
        ExpressionAttributeValues: {
          ':connectionId': connectionId
        }
      });

      const result = await docClient.send(queryCommand);
      
      if (result.Items && result.Items.length > 0) {
        const deletePromises = result.Items.map(async (item) => {
          return docClient.send(new DeleteCommand({
            TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
            Key: { connectionId: item.connectionId, storeId: item.storeId }
          }));
        });

        await Promise.all(deletePromises);
        console.log(`✅ Unsubscribed connection ${connectionId} from all stores`);
      }
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        message: 'Unsubscribed successfully',
        connectionId
      })
    };

  } catch (error) {
    console.error('❌ Error handling unsubscription:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'Failed to unsubscribe',
        error: error.message
      })
    };
  }
}

async function handleBroadcastRequest(event, requestBody) {
  const { storeId, availabilityData, targetLocation } = requestBody;
  
  if (!storeId || !availabilityData) {
    return {
      statusCode: 400,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'storeId and availabilityData are required'
      })
    };
  }

  try {
    const result = await broadcastAvailabilityUpdate(storeId, availabilityData, targetLocation);
    
    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        message: `Broadcast sent to ${result.sentCount} connections`,
        ...result
      })
    };

  } catch (error) {
    console.error('❌ Error handling broadcast request:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'Failed to broadcast',
        error: error.message
      })
    };
  }
}

async function handleStreamEvent(event) {
  console.log('📊 Processing stream event');
  
  for (const record of event.Records) {
    if (record.eventSource === 'aws:dynamodb') {
      await processDynamoDBRecord(record);
    }
  }

  return { statusCode: 200 };
}

async function processDynamoDBRecord(record) {
  const eventName = record.eventName;
  const tableName = record.eventSourceARN.split('/')[1];
  
  console.log(`📝 DynamoDB ${eventName} on table ${tableName}`);

  // Handle business table changes (accepting orders, etc.)
  if (tableName.includes('businesses') && (eventName === 'MODIFY' || eventName === 'INSERT')) {
    const newImage = record.dynamodb.NewImage;
    const oldImage = record.dynamodb.OldImage;
    
    if (newImage && newImage.businessId) {
      const storeId = newImage.businessId.S;
      
      // Check if acceptingOrders changed
      const newAcceptingOrders = newImage.acceptingOrders?.BOOL;
      const oldAcceptingOrders = oldImage?.acceptingOrders?.BOOL;
      
      if (newAcceptingOrders !== oldAcceptingOrders) {
        console.log(`🔄 Store ${storeId} acceptingOrders changed: ${oldAcceptingOrders} → ${newAcceptingOrders}`);
        
        // Broadcast availability change
        await broadcastAvailabilityUpdate(storeId, {
          acceptingOrders: newAcceptingOrders,
          status: newAcceptingOrders ? 'OPEN' : 'PAUSED_BY_MERCHANT',
          canOrderNow: newAcceptingOrders,
          lastUpdated: new Date().toISOString()
        });
      }
    }
  }

  // Handle working hours changes
  if (tableName.includes('working-hours') && (eventName === 'MODIFY' || eventName === 'INSERT')) {
    const newImage = record.dynamodb.NewImage;
    
    if (newImage && newImage.business_id) {
      const storeId = newImage.business_id.S;
      
      console.log(`🕐 Working hours changed for store ${storeId}`);
      
      // Broadcast working hours change
      await broadcastAvailabilityUpdate(storeId, {
        workingHoursUpdated: true,
        lastUpdated: new Date().toISOString()
      });
    }
  }
}

async function handleDirectBroadcast(event) {
  const { storeId, availabilityData, targetLocation } = event;
  
  if (!storeId || !availabilityData) {
    throw new Error('storeId and availabilityData are required for direct broadcast');
  }

  const result = await broadcastAvailabilityUpdate(storeId, availabilityData, targetLocation);
  
  return {
    statusCode: 200,
    result
  };
}

async function broadcastAvailabilityUpdate(storeId, availabilityData, targetLocation) {
  console.log(`📡 Broadcasting availability update for store ${storeId}`);

  try {
    // Get all subscriptions for this store
    const queryCommand = new QueryCommand({
      TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
      IndexName: 'storeId-index', // Assumes GSI exists
      KeyConditionExpression: 'storeId = :storeId',
      ExpressionAttributeValues: {
        ':storeId': storeId
      }
    });

    const result = await docClient.send(queryCommand);
    const subscriptions = result.Items || [];

    if (subscriptions.length === 0) {
      console.log(`📪 No subscriptions found for store ${storeId}`);
      return { sentCount: 0, failedCount: 0 };
    }

    console.log(`📨 Found ${subscriptions.length} subscriptions for store ${storeId}`);

    // Get WebSocket endpoint from environment
    const websocketEndpoint = process.env.WEBSOCKET_ENDPOINT;
    if (!websocketEndpoint) {
      throw new Error('WEBSOCKET_ENDPOINT environment variable not set');
    }

    const apiGatewayClient = new ApiGatewayManagementApiClient({
      endpoint: websocketEndpoint
    });

    // Prepare message
    const message = {
      type: 'availability_update',
      storeId,
      timestamp: new Date().toISOString(),
      data: availabilityData
    };

    let sentCount = 0;
    let failedCount = 0;

    // Send to each connection
    const sendPromises = subscriptions.map(async (subscription) => {
      try {
        // Filter by location if targetLocation is specified
        if (targetLocation && subscription.userLocation) {
          const distance = calculateDistance(targetLocation, subscription.userLocation);
          if (distance > 50) { // 50km radius filter
            return;
          }
        }

        await apiGatewayClient.send(new PostToConnectionCommand({
          ConnectionId: subscription.connectionId,
          Data: JSON.stringify(message)
        }));

        sentCount++;
        console.log(`✅ Sent to connection ${subscription.connectionId}`);

      } catch (error) {
        failedCount++;
        console.error(`❌ Failed to send to connection ${subscription.connectionId}:`, error.message);

        // If connection is stale, clean it up
        if (error.statusCode === 410) {
          await cleanupStaleConnection(subscription.connectionId);
        }
      }
    });

    await Promise.all(sendPromises);

    console.log(`📊 Broadcast complete: ${sentCount} sent, ${failedCount} failed`);

    return { sentCount, failedCount, totalSubscriptions: subscriptions.length };

  } catch (error) {
    console.error('❌ Error broadcasting availability update:', error);
    throw error;
  }
}

async function cleanupStaleConnection(connectionId) {
  try {
    // Delete all subscriptions for this connection
    const queryCommand = new QueryCommand({
      TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
      KeyConditionExpression: 'connectionId = :connectionId',
      ExpressionAttributeValues: {
        ':connectionId': connectionId
      }
    });

    const result = await docClient.send(queryCommand);
    
    if (result.Items && result.Items.length > 0) {
      const deletePromises = result.Items.map(async (item) => {
        return docClient.send(new DeleteCommand({
          TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
          Key: { connectionId: item.connectionId, storeId: item.storeId }
        }));
      });

      await Promise.all(deletePromises);
      console.log(`🧹 Cleaned up ${result.Items.length} subscriptions for stale connection ${connectionId}`);
    }

  } catch (error) {
    console.error(`❌ Error cleaning up stale connection ${connectionId}:`, error);
  }
}

function calculateDistance(location1, location2) {
  if (!location1 || !location2) return 0;
  
  try {
    const [lat1, lon1] = location1.split(',').map(Number);
    const [lat2, lon2] = location2.split(',').map(Number);
    
    const R = 6371; // Earth's radius in kilometers
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
  } catch (error) {
    console.error('Error calculating distance:', error);
    return 0;
  }
}
