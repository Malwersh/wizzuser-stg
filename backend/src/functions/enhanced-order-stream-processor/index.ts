import { DynamoDBStreamEvent, DynamoDBRecord } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand, DeleteCommand, ScanCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';

const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const lambdaClient = new LambdaClient({ region: process.env.AWS_REGION });

interface OrderUpdateNotification {
  type: 'order_update' | 'NEW_ORDER';
  orderId: string;
  status: string;
  businessId?: string;
  userId?: string;
  updatedAt: string;
  eventName: string; // INSERT, MODIFY, REMOVE
}

interface WebSocketConnection {
  connectionId: string;
  userId?: string;
  orderId?: string;
  connectedAt: string;
}

export const handler = async (event: DynamoDBStreamEvent): Promise<void> => {
  console.log('🔄 Enhanced DynamoDB Stream event received:', JSON.stringify(event));

  const websocketEndpoint = process.env.WEBSOCKET_ENDPOINT;
  const websocketTable = process.env.WEBSOCKET_TABLE;

  if (!websocketEndpoint || !websocketTable) {
    console.error('Missing required environment variables');
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
      console.error('Error processing record:', error);
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
  
  if (!eventName || !record.dynamodb) {
    console.log('Skipping record without eventName or dynamodb data');
    return;
  }

  console.log(`🔄 Processing ${eventName} event for record:`, JSON.stringify(record.dynamodb));

  // Extract order information from the stream record
  const newImage = record.dynamodb.NewImage;
  const oldImage = record.dynamodb.OldImage;
  
  // Get order data from new image (for INSERT/MODIFY) or old image (for REMOVE)
  const orderData = newImage || oldImage;
  
  if (!orderData) {
    console.log('No order data found in stream record');
    return;
  }

  const orderId = orderData.orderId?.S;
  const status = newImage?.status?.S || oldImage?.status?.S;
  const businessId = orderData.businessId?.S || orderData.storeId?.S;
  const userId = orderData.userId?.S;

  if (!orderId) {
    console.log('No orderId found in stream record');
    return;
  }

  console.log(`🔄 Processing order update: ${orderId}, status: ${status}, eventName: ${eventName}, businessId: ${businessId}`);

  // Try to use unified notification system first
  try {
    console.log('📡 Triggering unified notification system...');
    
    // Prepare full order data if available
    const fullOrderData: any = {
      orderId: orderId,
      orderNumber: orderData.orderNumber_gsi?.S || `ORD${orderId.substring(0, 8)}`,
      status: status,
      businessId: businessId,
      userId: userId,
      updatedAt: new Date().toISOString()
    };

    // Add additional fields if available
    if (orderData.customerName?.S) fullOrderData.customerName = orderData.customerName.S;
    if (orderData.customerPhone?.S) fullOrderData.customerPhone = orderData.customerPhone.S;
    if (orderData.total?.N) fullOrderData.total = parseFloat(orderData.total.N);
    if (orderData.pricing?.M?.total?.N) fullOrderData.total = parseFloat(orderData.pricing.M.total.N) / 1000; // Convert fils to IQD

    const payload = {
      orderId: orderId,
      orderData: fullOrderData,
      eventType: eventName,
      status: status,
      businessId: businessId,
      userId: userId
    };
    
    const command = new InvokeCommand({
      FunctionName: 'WizzUser-UnifiedNotificationSender-dev',
      InvocationType: 'Event', // Async invocation
      Payload: JSON.stringify(payload)
    });
    
    await lambdaClient.send(command);
    console.log('📡 Unified notification system triggered successfully');
    
  } catch (unifiedError) {
    console.error('📡 Failed to trigger unified notification system:', unifiedError);
    
    // Fallback to direct WebSocket notifications for BOTH customers AND merchants
    console.log('📡 Falling back to direct WebSocket notifications for customers AND merchants...');
    
    // Create notification payload
    const notification: OrderUpdateNotification = {
      type: eventName === 'INSERT' && status === 'pending' ? 'NEW_ORDER' : 'order_update',
      orderId,
      status: status || 'unknown',
      businessId,
      userId,
      updatedAt: new Date().toISOString(),
      eventName
    };

    // Find WebSocket connections for both customers AND merchants
    const connections = await findRelevantConnections(docClient, websocketTable, orderId, userId, businessId);
    
    console.log(`Found ${connections.length} relevant customer connections for order ${orderId}`);

    // Send notifications to all relevant customer connections
    const notificationPromises = connections.map(connection => 
      sendNotificationToConnection(apiGwClient, connection.connectionId, notification, docClient, websocketTable)
    );

    await Promise.allSettled(notificationPromises);
  }
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
    // 1. Query connections subscribed to this specific order
    if (orderId) {
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
      
      console.log(`Found ${orderResult.Items?.length || 0} connections subscribed to order ${orderId}`);
    }

    // 2. Find merchant connections for this business - COMPREHENSIVE SEARCH
    if (businessId) {
      try {
        console.log(`🔍 Searching for merchant connections for business: ${businessId}`);
        
        // Method 1: Query using GSI1 with BUSINESS# prefix 
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
          const merchantConnections = businessResult.Items
            .filter(item => !connections.find(conn => conn.connectionId === item.connectionId))
            .map(item => ({
              connectionId: item.connectionId,
              userId: item.userId,
              orderId: item.orderId,
              connectedAt: item.connectedAt
            }));
            
          connections.push(...merchantConnections);
          console.log(`✅ Found ${merchantConnections.length} merchant connections via GSI1 BUSINESS# for ${businessId}`);
        }

        // Method 2: Scan for businessId field directly
        const businessIdScanQuery = {
          TableName: websocketTable,
          FilterExpression: 'businessId = :businessId',
          ExpressionAttributeValues: {
            ':businessId': businessId
          }
        };

        const businessIdScanResult = await docClient.send(new ScanCommand(businessIdScanQuery));
        
        if (businessIdScanResult.Items) {
          const businessIdConnections = businessIdScanResult.Items
            .filter(item => !connections.find(conn => conn.connectionId === item.connectionId))
            .map(item => ({
              connectionId: item.connectionId,
              userId: item.userId,
              orderId: item.orderId,
              connectedAt: item.connectedAt
            }));
            
          connections.push(...businessIdConnections);
          console.log(`✅ Found ${businessIdConnections.length} connections via businessId field scan for ${businessId}`);
        }

        // Method 3: Scan for merchant entityType with matching userId
        const merchantEntityScanQuery = {
          TableName: websocketTable,
          FilterExpression: 'entityType = :merchantType AND userId = :businessId',
          ExpressionAttributeValues: {
            ':merchantType': 'merchant',
            ':businessId': businessId
          }
        };

        const merchantEntityScanResult = await docClient.send(new ScanCommand(merchantEntityScanQuery));
        
        if (merchantEntityScanResult.Items) {
          const merchantEntityConnections = merchantEntityScanResult.Items
            .filter(item => !connections.find(conn => conn.connectionId === item.connectionId))
            .map(item => ({
              connectionId: item.connectionId,
              userId: item.userId,
              orderId: item.orderId,
              connectedAt: item.connectedAt
            }));
            
          connections.push(...merchantEntityConnections);
          console.log(`✅ Found ${merchantEntityConnections.length} connections via merchant entityType scan for ${businessId}`);
        }

        // Method 4: Broad merchant scan (fallback for any merchant connections)
        const broadMerchantScanQuery = {
          TableName: websocketTable,
          FilterExpression: 'entityType = :merchantType OR userType = :merchantType',
          ExpressionAttributeValues: {
            ':merchantType': 'merchant'
          }
        };

        const broadMerchantScanResult = await docClient.send(new ScanCommand(broadMerchantScanQuery));
        
        if (broadMerchantScanResult.Items) {
          const broadMerchantConnections = broadMerchantScanResult.Items
            .filter(item => !connections.find(conn => conn.connectionId === item.connectionId))
            .map(item => ({
              connectionId: item.connectionId,
              userId: item.userId,
              orderId: item.orderId,
              connectedAt: item.connectedAt
            }));
            
          connections.push(...broadMerchantConnections);
          console.log(`✅ Found ${broadMerchantConnections.length} connections via broad merchant scan (fallback)`);
        }

        console.log(`🎯 Total merchant connections found for ${businessId}: ${connections.filter(c => c.userId?.includes(businessId) || c.userId === businessId).length}`);
        
      } catch (merchantError) {
        console.error('❌ Error querying merchant connections:', merchantError);
      }
    }

    // 3. Find user connections for this specific user (customer notifications)
    if (userId) {
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
          const userConnections = userResult.Items
            .filter(item => !connections.find(conn => conn.connectionId === item.connectionId))
            .map(item => ({
              connectionId: item.connectionId,
              userId: item.userId,
              orderId: item.orderId,
              connectedAt: item.connectedAt
            }));
            
          connections.push(...userConnections);
          console.log(`Found ${userConnections.length} user connections for user ${userId}`);
        }
      } catch (userError) {
        console.error('Error querying user connections:', userError);
      }
    }

    console.log(`🔍 Total connections found: ${connections.length} (Order: ${orderId}, Business: ${businessId}, User: ${userId})`);
    
  } catch (error) {
    console.error('Error querying WebSocket connections:', error);
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
    console.log(`Notification sent to connection ${connectionId}`);
    
  } catch (error: any) {
    console.error(`Failed to send notification to connection ${connectionId}:`, error);
    
    // If connection is stale (410 error), remove it from the table
    if (error.statusCode === 410) {
      console.log(`Removing stale connection ${connectionId}`);
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
    
    console.log(`Removed stale connection: ${connectionId}`);
    
  } catch (error) {
    console.error(`Failed to remove stale connection ${connectionId}:`, error);
  }
}
