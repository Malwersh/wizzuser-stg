import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, QueryCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';

const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = DynamoDBDocumentClient.from(dynamoClient);

interface WebSocketConnection {
  connectionId: string;
  userId?: string;
  businessId?: string;
  orderId?: string;
  entityType?: string;
  connectedAt: string;
}

interface OrderNotification {
  type: 'NEW_ORDER' | 'ORDER_STATUS_UPDATE';
  orderId: string;
  orderNumber?: string;
  status: string;
  businessId?: string;
  userId?: string;
  customerName?: string;
  customerPhone?: string;
  total?: number;
  updatedAt: string;
  message?: string;
}

export const handler = async (event: any): Promise<any> => {
  console.log('📡 Enhanced Unified Notification Sender triggered:', JSON.stringify(event, null, 2));

  const websocketEndpoint = process.env.WEBSOCKET_ENDPOINT;
  const websocketTable = process.env.WEBSOCKET_TABLE;

  if (!websocketEndpoint || !websocketTable) {
    console.error('❌ Missing required environment variables');
    throw new Error('Missing WEBSOCKET_ENDPOINT or WEBSOCKET_TABLE');
  }

  const { orderId, orderData, eventType, status, businessId, userId } = event;

  if (!orderId || !orderData) {
    console.error('❌ Missing required event data');
    throw new Error('Missing orderId or orderData');
  }

  console.log(`🔄 Processing notification for order: ${orderId}, business: ${businessId}, event: ${eventType}`);

  // Initialize API Gateway Management API client
  const apiGwClient = new ApiGatewayManagementApiClient({
    endpoint: websocketEndpoint,
    region: process.env.AWS_REGION
  });

  try {
    // Find all relevant connections
    const connections = await findAllRelevantConnections(
      docClient, 
      websocketTable, 
      orderId, 
      businessId, 
      userId, 
      eventType
    );

    if (connections.length === 0) {
      console.log('⚠️ No active connections found for this notification');
      return {
        statusCode: 200,
        body: JSON.stringify({
          success: true,
          message: 'No active connections to notify',
          orderId,
          businessId
        })
      };
    }

    // Create appropriate notification based on event type
    const notification: OrderNotification = {
      type: eventType === 'INSERT' && status === 'pending' ? 'NEW_ORDER' : 'ORDER_STATUS_UPDATE',
      orderId,
      orderNumber: orderData.orderNumber || `ORD${orderId.substring(0, 8)}`,
      status: status || orderData.status || 'unknown',
      businessId,
      userId,
      customerName: orderData.customerName,
      customerPhone: orderData.customerPhone,
      total: orderData.total,
      updatedAt: new Date().toISOString(),
      message: getStatusMessage(status || orderData.status)
    };

    console.log(`📤 Sending ${notification.type} to ${connections.length} connections`);

    // Send notifications to all connections
    const sendResults = await Promise.allSettled(
      connections.map(connection => 
        sendNotificationToConnection(apiGwClient, connection, notification, docClient, websocketTable)
      )
    );

    // Count successful sends
    const successCount = sendResults.filter(result => result.status === 'fulfilled').length;
    const failureCount = sendResults.length - successCount;

    console.log(`✅ Notification sent to ${successCount}/${connections.length} connections`);

    if (failureCount > 0) {
      console.log(`⚠️ ${failureCount} connections failed to receive notification`);
    }

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: 'Notifications sent successfully',
        orderId,
        businessId,
        totalConnections: connections.length,
        successCount,
        failureCount
      })
    };

  } catch (error) {
    console.error('❌ Error sending notifications:', error);
    throw error;
  }
};

async function findAllRelevantConnections(
  docClient: DynamoDBDocumentClient,
  websocketTable: string,
  orderId: string,
  businessId?: string,
  userId?: string,
  eventType?: string
): Promise<WebSocketConnection[]> {
  const connections: WebSocketConnection[] = [];
  const seenConnectionIds = new Set<string>();

  try {
    // 1. For NEW_ORDER events, prioritize merchant connections
    if (eventType === 'INSERT' && businessId) {
      console.log(`🏪 Finding merchant connections for business: ${businessId}`);
      
      // Method 1: Query using GSI1 with BUSINESS# prefix
      try {
        const businessQuery = {
          TableName: websocketTable,
          IndexName: 'GSI1',
          KeyConditionExpression: 'GSI1PK = :businessPK',
          ExpressionAttributeValues: {
            ':businessPK': `BUSINESS#${businessId}`
          }
        };

        const businessResult = await docClient.send(new QueryCommand(businessQuery));
        
        if (businessResult.Items) {
          businessResult.Items.forEach(item => {
            if (!seenConnectionIds.has(item.connectionId)) {
              connections.push({
                connectionId: item.connectionId,
                userId: item.userId,
                businessId: item.businessId,
                orderId: item.orderId,
                entityType: item.entityType,
                connectedAt: item.connectedAt
              });
              seenConnectionIds.add(item.connectionId);
            }
          });
          console.log(`Found ${businessResult.Items.length} merchant connections via GSI1`);
        }
      } catch (error) {
        console.error('Error querying merchant connections via GSI1:', error);
      }

      // Method 2: Scan for businessId field and merchant entityType
      try {
        const merchantScanQuery = {
          TableName: websocketTable,
          FilterExpression: 'businessId = :businessId OR (entityType = :merchantType AND (userId = :businessId OR businessId = :businessId2))',
          ExpressionAttributeValues: {
            ':businessId': businessId,
            ':businessId2': businessId,
            ':merchantType': 'merchant'
          }
        };

        const merchantScanResult = await docClient.send(new ScanCommand(merchantScanQuery));
        
        if (merchantScanResult.Items) {
          merchantScanResult.Items.forEach(item => {
            if (!seenConnectionIds.has(item.connectionId)) {
              connections.push({
                connectionId: item.connectionId,
                userId: item.userId,
                businessId: item.businessId,
                orderId: item.orderId,
                entityType: item.entityType,
                connectedAt: item.connectedAt
              });
              seenConnectionIds.add(item.connectionId);
            }
          });
          console.log(`Found ${merchantScanResult.Items.length} additional merchant connections via scan`);
        }
      } catch (error) {
        console.error('Error scanning for merchant connections:', error);
      }
    }

    // 2. Find connections subscribed to this specific order
    if (orderId) {
      try {
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
          orderResult.Items.forEach(item => {
            if (!seenConnectionIds.has(item.connectionId)) {
              connections.push({
                connectionId: item.connectionId,
                userId: item.userId,
                businessId: item.businessId,
                orderId: item.orderId,
                entityType: item.entityType,
                connectedAt: item.connectedAt
              });
              seenConnectionIds.add(item.connectionId);
            }
          });
          console.log(`Found ${orderResult.Items.length} order-specific connections`);
        }
      } catch (error) {
        console.error('Error querying order-specific connections:', error);
      }
    }

    // 3. Find customer connections for order status updates
    if (userId && eventType !== 'INSERT') {
      try {
        const userQuery = {
          TableName: websocketTable,
          FilterExpression: 'userId = :userId AND entityType <> :merchantType',
          ExpressionAttributeValues: {
            ':userId': userId,
            ':merchantType': 'merchant'
          }
        };

        const userResult = await docClient.send(new ScanCommand(userQuery));
        
        if (userResult.Items) {
          userResult.Items.forEach(item => {
            if (!seenConnectionIds.has(item.connectionId)) {
              connections.push({
                connectionId: item.connectionId,
                userId: item.userId,
                businessId: item.businessId,
                orderId: item.orderId,
                entityType: item.entityType,
                connectedAt: item.connectedAt
              });
              seenConnectionIds.add(item.connectionId);
            }
          });
          console.log(`Found ${userResult.Items.length} customer connections`);
        }
      } catch (error) {
        console.error('Error querying customer connections:', error);
      }
    }

    console.log(`🔍 Total unique connections found: ${connections.length}`);
    
    // Log connection details for debugging
    connections.forEach((conn, index) => {
      console.log(`   ${index + 1}. ${conn.connectionId} (${conn.entityType || 'user'}) - Business: ${conn.businessId || 'N/A'}, User: ${conn.userId || 'N/A'}`);
    });

  } catch (error) {
    console.error('Error finding relevant connections:', error);
  }

  return connections;
}

async function sendNotificationToConnection(
  apiGwClient: ApiGatewayManagementApiClient,
  connection: WebSocketConnection,
  notification: OrderNotification,
  docClient: DynamoDBDocumentClient,
  websocketTable: string
): Promise<void> {
  try {
    const command = new PostToConnectionCommand({
      ConnectionId: connection.connectionId,
      Data: JSON.stringify(notification)
    });

    await apiGwClient.send(command);
    console.log(`✅ Notification sent to connection ${connection.connectionId} (${connection.entityType || 'user'})`);
    
  } catch (error: any) {
    console.error(`❌ Failed to send notification to connection ${connection.connectionId}:`, error);
    
    // If connection is stale (410 error), remove it from the table
    if (error.statusCode === 410) {
      console.log(`🧹 Removing stale connection ${connection.connectionId}`);
      await removeStaleConnection(docClient, websocketTable, connection.connectionId);
    }
    
    throw error;
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
    console.error(`Failed to remove stale connection ${connectionId}:`, error);
  }
}

function getStatusMessage(status: string): string {
  const statusMessages: { [key: string]: string } = {
    'pending': 'طلبك قيد المراجعة',
    'confirmed': 'تم تأكيد طلبك',
    'preparing': 'يتم تحضير طلبك',
    'ready': 'طلبك جاهز للاستلام',
    'on_the_way': 'السائق في الطريق إليك',
    'delivered': 'تم تسليم طلبك',
    'cancelled': 'تم إلغاء طلبك',
    'rejected': 'عذراً، رفض المطعم تأكيد طلبك'
  };
  
  return statusMessages[status.toLowerCase()] || `حالة الطلب: ${status}`;
}
