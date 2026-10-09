const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, DeleteCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');
const { LambdaClient, InvokeCommand } = require('@aws-sdk/client-lambda');

const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const lambdaClient = new LambdaClient({ region: process.env.AWS_REGION });

exports.handler = async (event) => {
  console.log('🔄 Enhanced DynamoDB Stream event received:', JSON.stringify(event));

  const websocketEndpoint = process.env.WEBSOCKET_ENDPOINT;
  const websocketTable = process.env.WEBSOCKET_TABLE;
  const unifiedNotificationFunction = process.env.UNIFIED_NOTIFICATION_FUNCTION;

  if (!websocketEndpoint || !websocketTable) {
    console.error('❌ Missing required environment variables');
    return;
  }

  console.log('📡 Configuration:', {
    websocketEndpoint,
    websocketTable,
    unifiedNotificationFunction
  });

  for (const record of event.Records) {
    try {
      await processRecord(record, docClient, websocketEndpoint, websocketTable, unifiedNotificationFunction, lambdaClient);
    } catch (error) {
      console.error('❌ Error processing record:', error);
      // Continue processing other records even if one fails
    }
  }
};

async function processRecord(record, docClient, websocketEndpoint, websocketTable, unifiedNotificationFunction, lambdaClient) {
  const eventName = record.eventName;
  
  if (!eventName || !record.dynamodb) {
    console.log('⚠️ Skipping record without eventName or dynamodb data');
    return;
  }

  console.log(`🔍 Processing ${eventName} event for record:`, JSON.stringify(record.dynamodb));

  // Extract order information from the stream record
  const newImage = record.dynamodb.NewImage;
  const oldImage = record.dynamodb.OldImage;
  
  // Get order data from new image (for INSERT/MODIFY) or old image (for REMOVE)
  const orderData = newImage || oldImage;
  
  if (!orderData) {
    console.log('⚠️ No order data found in stream record');
    return;
  }

  const orderId = orderData.orderId?.S || orderData.id?.S;
  const status = newImage?.status?.S || oldImage?.status?.S;
  const businessId = orderData.businessId?.S || orderData.storeId?.S;
  const userId = orderData.userId?.S;
  const customerName = orderData.customerName?.S;
  const totalAmount = orderData.totalAmount?.N;

  if (!orderId) {
    console.log('⚠️ No orderId found in stream record');
    return;
  }

  console.log(`📋 Processing order update: ${orderId}, status: ${status}, businessId: ${businessId}, eventName: ${eventName}`);

  // Create notification payload
  const notification = {
    type: eventName === 'INSERT' ? 'NEW_ORDER' : 'order_update',
    orderId,
    status: status || 'unknown',
    businessId,
    userId,
    customerName,
    totalAmount: totalAmount ? parseFloat(totalAmount) : 0,
    updatedAt: new Date().toISOString(),
    eventName,
    data: {
      orderId,
      businessId,
      status,
      customerName,
      totalAmount: totalAmount ? parseFloat(totalAmount) : 0,
      items: orderData.items?.L || [],
      createdAt: orderData.createdAt?.S,
      updatedAt: new Date().toISOString()
    }
  };

  console.log('📤 Notification payload:', JSON.stringify(notification, null, 2));

  // Send notification via Unified Notification Sender if available
  if (unifiedNotificationFunction) {
    try {
      console.log('🚀 Invoking Unified Notification Sender:', unifiedNotificationFunction);
      
      const invokeParams = {
        FunctionName: unifiedNotificationFunction,
        InvocationType: 'Event', // Asynchronous invocation
        Payload: JSON.stringify({
          source: 'enhanced-order-stream-processor',
          notification,
          websocketEndpoint,
          websocketTable
        })
      };

      await lambdaClient.send(new InvokeCommand(invokeParams));
      console.log('✅ Unified Notification Sender invoked successfully');
      
    } catch (error) {
      console.error('❌ Failed to invoke Unified Notification Sender:', error);
    }
  }

  // Also try direct WebSocket notification as fallback
  try {
    await sendDirectWebSocketNotifications(docClient, websocketEndpoint, websocketTable, notification);
  } catch (error) {
    console.error('❌ Failed to send direct WebSocket notifications:', error);
  }
}

async function sendDirectWebSocketNotifications(docClient, websocketEndpoint, websocketTable, notification) {
  console.log('🔗 Attempting direct WebSocket notifications...');
  
  // Determine the correct WebSocket API endpoint based on connection source
  // Business connections may come from wizzbussiness app with different endpoint
  const businessWebSocketEndpoint = process.env.BUSINESS_WEBSOCKET_MANAGEMENT_ENDPOINT || websocketEndpoint;
  
  // Initialize API Gateway Management API client
  const apiGwClient = new ApiGatewayManagementApiClient({
    endpoint: websocketEndpoint, // Default to wizzuser endpoint
    region: process.env.AWS_REGION,
    requestHandler: {
      httpOptions: {
        timeout: 30000
      }
    }
  });

  // Initialize business-specific client for business connections
  const businessApiGwClient = new ApiGatewayManagementApiClient({
    endpoint: businessWebSocketEndpoint,
    region: process.env.AWS_REGION,
    requestHandler: {
      httpOptions: {
        timeout: 30000
      }
    }
  });

  // Find WebSocket connections that should receive this notification
  const connections = await findRelevantConnections(docClient, websocketTable, notification.orderId, notification.businessId);
  
  console.log(`🔍 Found ${connections.length} relevant connections for order ${notification.orderId}`);
  
  // Log full connection details with encoding analysis
  connections.forEach((conn, index) => {
    console.log(`🔗 Connection ${index + 1}: Full ID = "${conn.connectionId}"`);
    console.log(`   BusinessId = ${conn.businessId}`);
    console.log(`   Length = ${conn.connectionId.length}`);
    console.log(`   Contains '=' = ${conn.connectionId.includes('=')}`);
    console.log(`   Contains '/' = ${conn.connectionId.includes('/')}`);
    console.log(`   URL Encoded = "${encodeURIComponent(conn.connectionId)}"`);
  });

  // Send notifications to all relevant connections with individual error handling
  const notificationResults = await Promise.allSettled(
    connections.map(connection => {
      // Determine correct API client based on connection source
      // Business connections (entityType: 'business') use wizzbussiness WebSocket API
      const isBusinessConnection = connection.entityType === 'business' || connection.source === 'business_login';
      const selectedClient = isBusinessConnection ? businessApiGwClient : apiGwClient;
      
      console.log(`🔌 Using ${isBusinessConnection ? 'wizzbussiness' : 'wizzuser'} WebSocket API for connection ${connection.connectionId.substring(0, 8)}...`);
      
      return sendNotificationToConnection(selectedClient, connection.connectionId, notification, docClient, websocketTable);
    })
  );

  // Log results summary
  const successful = notificationResults.filter(result => result.status === 'fulfilled').length;
  const failed = notificationResults.filter(result => result.status === 'rejected').length;
  console.log(`📊 Notification summary: ${successful} successful, ${failed} failed out of ${connections.length} connections`);
}

async function findRelevantConnections(docClient, websocketTable, orderId, businessId) {
  const connections = [];
  const connectionMap = new Map(); // Prevent duplicates

  try {
    // Query connections by businessId using GSI1 index (EFFICIENT FOR RESTAURANTS)
    if (businessId) {
      console.log('🔍 Searching for connections by businessId:', businessId);
      
      const businessQuery = {
        TableName: websocketTable,
        IndexName: 'GSI1',
        KeyConditionExpression: 'GSI1PK = :pk',
        FilterExpression: 'isActive = :active AND (entityType = :business OR entityType = :merchant)',
        ExpressionAttributeValues: {
          ':pk': `BUSINESS#${businessId}`,
          ':active': true,
          ':business': 'business',
          ':merchant': 'merchant'
        }
      };

      const businessResult = await docClient.send(new QueryCommand(businessQuery));
      if (businessResult.Items) {
        businessResult.Items.forEach(item => {
          if (!connectionMap.has(item.connectionId)) {
            connectionMap.set(item.connectionId, {
              connectionId: item.connectionId,
              userId: item.userId,
              businessId: item.businessId || item.storeId,
              entityType: item.entityType,
              connectedAt: item.connectedAt,
              platform: item.platform,
              isActive: item.isActive
            });
          }
        });
      }
    }

    // Also search for general merchant connections if needed (fallback)
    if (connectionMap.size === 0) {
      console.log('🔍 No business-specific connections found, searching for general merchant connections');
      const merchantQuery = {
        TableName: websocketTable,
        FilterExpression: '(entityType = :entityType OR entityType = :business) AND isActive = :active',
        ExpressionAttributeValues: {
          ':entityType': 'merchant',
          ':business': 'business',
          ':active': true
        }
      };

      const merchantResult = await docClient.send(new ScanCommand(merchantQuery));
      if (merchantResult.Items) {
        merchantResult.Items.forEach(item => {
          if (!connectionMap.has(item.connectionId)) {
            connectionMap.set(item.connectionId, {
              connectionId: item.connectionId,
              userId: item.userId,
              businessId: item.businessId || item.storeId,
              entityType: item.entityType,
              connectedAt: item.connectedAt,
              platform: item.platform,
              isActive: item.isActive
            });
          }
        });
      }
    }

    const connectionsArray = Array.from(connectionMap.values());
    console.log(`🔍 Found ${connectionsArray.length} unique connections for order ${orderId}`);
    console.log('🔍 Connection details:', connectionsArray.map(c => ({
      id: c.connectionId.substring(0, 8) + '...',
      businessId: c.businessId,
      entityType: c.entityType,
      platform: c.platform,
      isActive: c.isActive
    })));
    
    return connectionsArray;
    
  } catch (error) {
    console.error('❌ Error querying WebSocket connections:', error);
    return [];
  }
}

async function sendNotificationToConnection(agmApiClient, connectionId, notification, docClient, websocketTable) {
  try {
    console.log(`📤 Sending notification to connection ${connectionId.substring(0, 8)}...`);
    console.log(`📤 Notification type: ${notification.type}, orderId: ${notification.orderId}`);
    
    // Handle connectionId with Base64 special characters properly
    console.log(`🔧 Full connectionId: "${connectionId}"`);
    console.log(`🔧 ConnectionId length: ${connectionId.length}, contains special chars: ${/[\/=]/.test(connectionId)}`);
    
    // Use connectionId directly - AWS SDK handles encoding internally
    // The BadRequestException suggests the connectionId itself is invalid/stale
    console.log(`🔧 Testing connectionId: "${connectionId}"`);
    
    const command = new PostToConnectionCommand({
      ConnectionId: connectionId,
      Data: JSON.stringify(notification)
    });

    await agmApiClient.send(command);
    console.log(`✅ Notification sent successfully to connection ${connectionId.substring(0, 8)}...`);
    
  } catch (error) {
    console.error(`❌ Failed to send notification to connection ${connectionId.substring(0, 8)}...:`, error);
    console.error(`❌ Error details:`, {
      name: error.name,
      message: error.message,
      statusCode: error.$metadata?.httpStatusCode || error.statusCode,
      connectionId: connectionId
    });
    
    // Handle different error types appropriately
    if (error.$metadata?.httpStatusCode === 410 || error.statusCode === 410 || error.name === 'GoneException') {
      console.log(`🧹 Connection gone (410) - removing stale connection ${connectionId.substring(0, 8)}...`);
      await removeStaleConnection(docClient, websocketTable, connectionId);
    } else if (error.$metadata?.httpStatusCode === 400 || error.name === 'BadRequestException') {
      console.log(`🧹 Invalid connectionId (400) - likely stale, removing ${connectionId.substring(0, 8)}...`);
      await removeStaleConnection(docClient, websocketTable, connectionId);
    } else if (error.$metadata?.httpStatusCode === 404 || error.name === 'NotFoundException') {
      console.log(`🧹 Connection not found (404) - removing from table ${connectionId.substring(0, 8)}...`);
      await removeStaleConnection(docClient, websocketTable, connectionId);
    }
  }
}

async function removeStaleConnection(docClient, websocketTable, connectionId) {
  try {
    // Use correct primary key structure: PK and SK
    const deleteParams = {
      TableName: websocketTable,
      Key: {
        PK: `CONNECTION#${connectionId}`,
        SK: `CONNECTION#${connectionId}`
      }
    };
    
    await docClient.send(new DeleteCommand(deleteParams));
    console.log(`🗑️ Successfully removed stale connection ${connectionId.substring(0, 8)}...`);
    
  } catch (error) {
    console.error(`❌ Error removing stale connection ${connectionId.substring(0, 8)}...:`, error);
  }
}
