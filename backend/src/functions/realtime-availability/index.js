// Real-time Availability Updates via WebSocket
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, DeleteCommand, UpdateCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');
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

const WEBSOCKET_CONNECTIONS_TABLE = requireEnv('WEBSOCKET_CONNECTIONS_TABLE');
const AVAILABILITY_SUBSCRIPTIONS_TABLE = requireEnv('AVAILABILITY_SUBSCRIPTIONS_TABLE');
const WEBSOCKET_ENDPOINT = requireEnv('WEBSOCKET_ENDPOINT');

// Create API Gateway Management API client
const apiGatewayClient = new ApiGatewayManagementApiClient({
  endpoint: WEBSOCKET_ENDPOINT.replace('wss://', 'https://')
});

exports.handler = async (event) => {
  console.log('WebSocket event:', JSON.stringify(event, null, 2));

  const { connectionId, routeKey } = event.requestContext;

  try {
    switch (routeKey) {
      case '$connect':
        return await handleConnect(connectionId);
      
      case '$disconnect':
        return await handleDisconnect(connectionId);
      
      case 'subscribe':
        return await handleSubscribe(connectionId, event.body || null);
      
      case 'unsubscribe':
        return await handleUnsubscribe(connectionId, event.body || null);
      
      case 'ping':
        return await handlePing(connectionId);
      
      default:
        console.log(`Unknown route: ${routeKey}`);
        return { statusCode: 400, body: 'Unknown route' };
    }

  } catch (error) {
    console.error('WebSocket handler error:', error);
    return { statusCode: 500, body: 'Internal server error' };
  }
};

async function handleConnect(connectionId) {
  try {
    const timestamp = new Date().toISOString();
    
    const connectionData = {
      connectionId,
      connectedAt: timestamp,
      lastActivity: timestamp,
      ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60)
    };

    await docClient.send(new PutCommand({
      TableName: WEBSOCKET_CONNECTIONS_TABLE,
      Item: connectionData
    }));

    console.log(`Connection ${connectionId} established`);
    return { statusCode: 200, body: 'Connected' };

  } catch (error) {
    console.error('Error handling connect:', error);
    return { statusCode: 500, body: 'Failed to connect' };
  }
}

async function handleDisconnect(connectionId) {
  try {
    // Remove connection
    await docClient.send(new DeleteCommand({
      TableName: WEBSOCKET_CONNECTIONS_TABLE,
      Key: { connectionId }
    }));

    // Remove all subscriptions for this connection
    const subscriptions = await docClient.send(new ScanCommand({
      TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
      FilterExpression: 'connectionId = :connectionId',
      ExpressionAttributeValues: {
        ':connectionId': connectionId
      }
    }));
    
    if (subscriptions.Items) {
      for (const subscription of subscriptions.Items) {
        await docClient.send(new DeleteCommand({
          TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
          Key: { subscriptionId: subscription.subscriptionId }
        }));
      }
    }

    console.log(`Connection ${connectionId} disconnected and cleaned up`);
    return { statusCode: 200, body: 'Disconnected' };

  } catch (error) {
    console.error('Error handling disconnect:', error);
    return { statusCode: 500, body: 'Failed to disconnect' };
  }
}

async function handleSubscribe(connectionId, body) {
  try {
    if (!body) {
      return await sendErrorToConnection(connectionId, 'Subscription request body is required');
    }

    const request = JSON.parse(body);
    
    if (request.action !== 'subscribe') {
      return await sendErrorToConnection(connectionId, 'Invalid action');
    }

    const subscriptionId = `${connectionId}-${Date.now()}`;
    const subscription = {
      subscriptionId,
      connectionId,
      businessIds: request.businessIds || [],
      location: request.location,
      filters: request.filters || {},
      createdAt: new Date().toISOString(),
      ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60)
    };

    await docClient.send(new PutCommand({
      TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
      Item: subscription
    }));

    await updateConnectionActivity(connectionId);

    await sendMessageToConnection(connectionId, {
      type: 'subscription_confirmed',
      subscriptionId,
      businessIds: request.businessIds,
      timestamp: new Date().toISOString()
    });

    console.log(`Subscription ${subscriptionId} created for connection ${connectionId}`);
    return { statusCode: 200, body: 'Subscribed' };

  } catch (error) {
    console.error('Error handling subscribe:', error);
    await sendErrorToConnection(connectionId, 'Failed to subscribe');
    return { statusCode: 500, body: 'Failed to subscribe' };
  }
}

async function handleUnsubscribe(connectionId, body) {
  try {
    if (!body) {
      return await sendErrorToConnection(connectionId, 'Unsubscribe request body is required');
    }

    const request = JSON.parse(body);
    
    if (request.action !== 'unsubscribe') {
      return await sendErrorToConnection(connectionId, 'Invalid action');
    }

    const result = await docClient.send(new ScanCommand({
      TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
      FilterExpression: 'connectionId = :connectionId',
      ExpressionAttributeValues: {
        ':connectionId': connectionId
      }
    }));
    
    if (result.Items) {
      for (const subscription of result.Items) {
        await docClient.send(new DeleteCommand({
          TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
          Key: { subscriptionId: subscription.subscriptionId }
        }));
      }
    }

    await updateConnectionActivity(connectionId);

    await sendMessageToConnection(connectionId, {
      type: 'unsubscribe_confirmed',
      timestamp: new Date().toISOString()
    });

    console.log(`Unsubscribed connection ${connectionId}`);
    return { statusCode: 200, body: 'Unsubscribed' };

  } catch (error) {
    console.error('Error handling unsubscribe:', error);
    await sendErrorToConnection(connectionId, 'Failed to unsubscribe');
    return { statusCode: 500, body: 'Failed to unsubscribe' };
  }
}

async function handlePing(connectionId) {
  try {
    await updateConnectionActivity(connectionId);
    
    await sendMessageToConnection(connectionId, {
      type: 'pong',
      timestamp: new Date().toISOString()
    });

    return { statusCode: 200, body: 'Pong' };

  } catch (error) {
    console.error('Error handling ping:', error);
    return { statusCode: 500, body: 'Failed to ping' };
  }
}

async function sendMessageToConnection(connectionId, message) {
  try {
    const command = new PostToConnectionCommand({
      ConnectionId: connectionId,
      Data: Buffer.from(JSON.stringify(message))
    });

    await apiGatewayClient.send(command);

  } catch (error) {
    console.error(`Failed to send message to connection ${connectionId}:`, error);
    
    if (error.name === 'GoneException') {
      await cleanupConnection(connectionId);
    }
    
    throw error;
  }
}

async function sendErrorToConnection(connectionId, errorMessage) {
  try {
    await sendMessageToConnection(connectionId, {
      type: 'error',
      message: errorMessage,
      timestamp: new Date().toISOString()
    });

    return { statusCode: 400, body: errorMessage };

  } catch (error) {
    console.error('Failed to send error to connection:', error);
    return { statusCode: 500, body: 'Failed to send error' };
  }
}

async function updateConnectionActivity(connectionId) {
  try {
    await docClient.send(new UpdateCommand({
      TableName: WEBSOCKET_CONNECTIONS_TABLE,
      Key: { connectionId },
      UpdateExpression: 'SET lastActivity = :timestamp, #ttl = :ttl',
      ExpressionAttributeNames: {
        '#ttl': 'ttl'
      },
      ExpressionAttributeValues: {
        ':timestamp': new Date().toISOString(),
        ':ttl': Math.floor(Date.now() / 1000) + (24 * 60 * 60)
      }
    }));

  } catch (error) {
    console.error('Error updating connection activity:', error);
  }
}

async function cleanupConnection(connectionId) {
  try {
    await docClient.send(new DeleteCommand({
      TableName: WEBSOCKET_CONNECTIONS_TABLE,
      Key: { connectionId }
    }));

    const subscriptionsResult = await docClient.send(new ScanCommand({
      TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
      FilterExpression: 'connectionId = :connectionId',
      ExpressionAttributeValues: {
        ':connectionId': connectionId
      }
    }));

    if (subscriptionsResult.Items) {
      for (const subscription of subscriptionsResult.Items) {
        await docClient.send(new DeleteCommand({
          TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
          Key: { subscriptionId: subscription.subscriptionId }
        }));
      }
    }

    console.log(`Cleaned up connection ${connectionId}`);

  } catch (error) {
    console.error('Error cleaning up connection:', error);
  }
}

exports.broadcastAvailabilityUpdate = async (update) => {
  try {
    const subscriptions = await getRelevantSubscriptions(update.businessId);
    
    if (subscriptions.length === 0) {
      console.log(`No subscriptions found for business ${update.businessId}`);
      return;
    }

    const message = {
      type: 'availability_update',
      update,
      timestamp: new Date().toISOString()
    };

    const sendPromises = subscriptions.map(subscription => 
      sendMessageToConnection(subscription.connectionId, message)
        .catch(error => {
          console.error(`Failed to send to ${subscription.connectionId}:`, error);
        })
    );

    await Promise.allSettled(sendPromises);
    console.log(`Broadcast sent to ${subscriptions.length} subscribers for business ${update.businessId}`);

  } catch (error) {
    console.error('Error broadcasting availability update:', error);
  }
};

async function getRelevantSubscriptions(businessId) {
  try {
    const result = await docClient.send(new ScanCommand({
      TableName: AVAILABILITY_SUBSCRIPTIONS_TABLE,
      FilterExpression: 'contains(businessIds, :businessId) OR size(businessIds) = :zero',
      ExpressionAttributeValues: {
        ':businessId': businessId,
        ':zero': 0
      }
    }));

    return result.Items || [];

  } catch (error) {
    console.error('Error getting relevant subscriptions:', error);
    return [];
  }
}
