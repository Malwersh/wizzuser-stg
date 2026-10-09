import { DynamoDBStreamEvent, DynamoDBRecord } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';

const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = DynamoDBDocumentClient.from(dynamoClient);

interface OrderUpdateNotification {
  type: 'order_update';
  orderId: string;
  status: string;
  businessId?: string;
  userId?: string;
  updatedAt: string;
  eventName: string;
  message: string;
}

interface WebSocketConnection {
  connectionId: string;
  userId?: string;
  orderId?: string;
  connectedAt: string;
}

export const handler = async (event: DynamoDBStreamEvent): Promise<void> => {
  console.log('🔄 Order Stream Processor - DynamoDB Stream event received:', JSON.stringify(event, null, 2));

  const websocketEndpoint = process.env.WEBSOCKET_ENDPOINT;
  const websocketTable = process.env.WEBSOCKET_TABLE;

  if (!websocketEndpoint || !websocketTable) {
    console.error('❌ Missing required environment variables');
    return;
  }

  // Initialize API Gateway Management API client
  const apiGwClient = new ApiGatewayManagementApiClient({
    endpoint: websocketEndpoint,
    region: process.env.AWS_REGION
  });

  for (const record of event.Records) {
    try {
      await processRecord(record, docClient, apiGwClient, websocketTable);
    } catch (error) {
      console.error('❌ Error processing record:', error);
      // Continue processing other records even if one fails
    }
  }
};

async function processRecord(
  record: DynamoDBRecord,
  docClient: DynamoDBDocumentClient,
  apiGwClient: ApiGatewayManagementApiClient,
  websocketTable: string
): Promise<void> {
  const eventName = record.eventName;
  const newImage = record.dynamodb?.NewImage;
  const oldImage = record.dynamodb?.OldImage;

  if (!newImage && !oldImage) {
    console.log('⚠️ No image data in record');
    return;
  }

  const orderData = newImage || oldImage;
  const orderId = orderData?.PK?.S?.replace('ORDER#', '') || orderData?.orderId?.S;
  const status = newImage?.status?.S || oldImage?.status?.S;
  const businessId = orderData?.businessId?.S;
  const userId = orderData?.userId?.S;

  if (!orderId) {
    console.log('⚠️ No orderId found in stream record');
    return;
  }

  console.log(`📦 Processing order update: ${orderId}, status: ${status}, eventName: ${eventName}`);

  // Create notification payload with Arabic message
  const notification: OrderUpdateNotification = {
    type: 'order_update',
    orderId,
    status: status || 'unknown',
    businessId,
    userId,
    updatedAt: new Date().toISOString(),
    eventName: eventName || 'MODIFY',
    message: getArabicStatusMessage(status || 'unknown')
  };

  // Find WebSocket connections that should receive this notification
  // Pass businessId to find merchant connections in shared WebSocket table
  const connections = await findRelevantConnections(docClient, websocketTable, orderId, userId, businessId);
  
  console.log(`🔍 Found ${connections.length} relevant connections for order ${orderId}`);

  // Send notifications to all relevant connections
  const notificationPromises = connections.map(connection => 
    sendNotificationToConnection(apiGwClient, connection.connectionId, notification, docClient, websocketTable)
  );

  await Promise.allSettled(notificationPromises);
}

async function findRelevantConnections(
  docClient: DynamoDBDocumentClient,
  websocketTable: string,
  orderId: string,
  userId?: string,
  businessId?: string
): Promise<WebSocketConnection[]> {
  const connections: WebSocketConnection[] = [];

  try {
    // Query connections subscribed to this specific order
    const orderQuery = {
      TableName: websocketTable,
      IndexName: 'GSI1',
      KeyConditionExpression: 'GSI1PK = :orderPK',
      ExpressionAttributeValues: {
        ':orderPK': `ORDER#${orderId}`
      }
    };

    const orderResult = await docClient.send(new QueryCommand(orderQuery));
    if (orderResult.Items) {
      connections.push(...orderResult.Items.map(item => ({
        connectionId: item.connectionId,
        userId: item.userId,
        orderId: item.orderId,
        connectedAt: item.connectedAt
      })));
    }

    console.log(`🔗 Found ${connections.length} connections subscribed to order ${orderId}`);

    // Also find connections by userId if available
    if (userId) {
      const userQuery = {
        TableName: websocketTable,
        FilterExpression: 'userId = :userId',
        ExpressionAttributeValues: {
          ':userId': userId
        }
      };

      const userResult = await docClient.send(new QueryCommand(userQuery));
      if (userResult.Items) {
        const userConnections = userResult.Items.map(item => ({
          connectionId: item.connectionId,
          userId: item.userId,
          orderId: item.orderId,
          connectedAt: item.connectedAt
        }));

        // Add user connections that aren't already in the list
        userConnections.forEach(userConn => {
          if (!connections.some(conn => conn.connectionId === userConn.connectionId)) {
            connections.push(userConn);
          }
        });
      }

      console.log(`👤 Total connections after adding user connections: ${connections.length}`);
    }

    // 🔥 NEW: Find merchant/business connections in shared WizzUser WebSocket table
    if (businessId) {
      try {
        const merchantTable = websocketTable; // Shared WebSocket table
        console.log(`🏪 Searching for merchant connections for businessId: ${businessId}`);
        
        // Query using GSI1 (GSI1PK = BUSINESS#businessId)
        const merchantQuery = {
          TableName: merchantTable,
          IndexName: 'GSI1',
          KeyConditionExpression: 'GSI1PK = :businessPK',
          FilterExpression: 'isActive = :isActive AND (entityType = :merchant OR attribute_not_exists(entityType))',
          ExpressionAttributeValues: {
            ':businessPK': `BUSINESS#${businessId}`,
            ':isActive': true,
            ':merchant': 'merchant'
          }
        };

        const merchantResult = await docClient.send(new QueryCommand(merchantQuery));
        if (merchantResult.Items && merchantResult.Items.length > 0) {
          const merchantConnections = merchantResult.Items.map(item => ({
            connectionId: item.connectionId || item.PK?.replace('CONNECTION#', ''),
            userId: item.userId || businessId,
            orderId: orderId,
            connectedAt: item.connectedAt || item.createdAt
          }));

          // Add merchant connections that aren't already in the list
          merchantConnections.forEach(merchantConn => {
            if (merchantConn.connectionId && !connections.some(conn => conn.connectionId === merchantConn.connectionId)) {
              connections.push(merchantConn);
              console.log(`🏪 Added merchant connection: ${merchantConn.connectionId}`);
            }
          });

          console.log(`🏪 Found ${merchantResult.Items.length} active merchant connections for business ${businessId}`);
        } else {
          console.log(`⚠️  No active merchant connections found for business ${businessId}`);
        }
      } catch (merchantError) {
        console.error('⚠️  Error querying merchant connections:', merchantError);
        // Continue processing even if merchant query fails
      }
    }

    console.log(`📊 Total connections to notify: ${connections.length}`);

  } catch (error) {
    console.error('❌ Error querying WebSocket connections:', error);
  }

  return connections;
}

async function sendNotificationToConnection(
  agmApiClient: ApiGatewayManagementApiClient,
  connectionId: string,
  notification: OrderUpdateNotification,
  docClient: DynamoDBDocumentClient,
  websocketTable: string
): Promise<void> {
  try {
    const command = new PostToConnectionCommand({
      ConnectionId: connectionId,
      Data: JSON.stringify(notification)
    });

    await agmApiClient.send(command);
    console.log(`✅ Notification sent to connection ${connectionId} for order ${notification.orderId}`);
    
  } catch (error: any) {
    console.error(`❌ Failed to send notification to connection ${connectionId}:`, error);
    
    // If connection is stale (410 error), remove it from the table
    if (error.statusCode === 410) {
      console.log(`🧹 Removing stale connection ${connectionId}`);
      await removeStaleConnection(docClient, websocketTable, connectionId);
    }
  }
}

async function removeStaleConnection(
  docClient: DynamoDBDocumentClient,
  websocketTable: string,
  connectionId: string
): Promise<void> {
  try {
    await docClient.send(new DeleteCommand({
      TableName: websocketTable,
      Key: {
        PK: `CONNECTION#${connectionId}`,
        SK: `CONNECTION#${connectionId}`
      }
    }));
    console.log(`🗑️ Removed stale connection: ${connectionId}`);
  } catch (error) {
    console.error(`❌ Error removing stale connection ${connectionId}:`, error);
  }
}

function getArabicStatusMessage(status: string): string {
  const statusMessages: { [key: string]: string } = {
    'pending': 'تم استلام طلبك وننتظر موافقة المطعم',
    'confirmed': 'تم تأكيد طلبك من المطعم وسيبدأ التحضير قريباً',
    'preparing': 'يتم تحضير طلبك الآن في المطعم',
    'ready': 'طلبك جاهز للتوصيل',
    'on_the_way': 'السائق في الطريق إليك',
    'delivered': 'تم توصيل طلبك بنجاح',
    'cancelled': 'تم إلغاء الطلب',
    'failed': 'فشل في معالجة الطلب'
  };

  return statusMessages[status] || `تم تحديث حالة الطلب إلى: ${status}`;
}
