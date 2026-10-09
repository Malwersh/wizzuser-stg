const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, ScanCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');

const CENTRAL_NOTIFICATIONS_BASE_URL = String(process.env.CENTRAL_NOTIFICATIONS_BASE_URL || '').trim();
const CENTRAL_NOTIFICATIONS_INTERNAL_KEY = String(process.env.CENTRAL_NOTIFICATIONS_INTERNAL_KEY || '').trim();

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = DynamoDBDocumentClient.from(dynamoClient);

exports.handler = async (event) => {
  console.log('🔄 Order Stream Processor - DynamoDB Stream event received:', JSON.stringify(event, null, 2));

  const websocketTable = process.env.WEBSOCKET_TABLE || requireEnv('CONNECTIONS_TABLE');
  const websocketEndpoint =
    process.env.WEBSOCKET_MANAGEMENT_ENDPOINT ||
    (process.env.WEBSOCKET_ENDPOINT ? process.env.WEBSOCKET_ENDPOINT.replace('wss://', 'https://') : requireEnv('WEBSOCKET_MANAGEMENT_ENDPOINT'));

  console.log('🔗 Using WebSocket endpoint:', websocketEndpoint);
  console.log('🗄️ Using WebSocket table:', websocketTable);

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

function extractString(orderData, ...paths) {
  for (const p of paths) {
    const v = p(orderData);
    if (typeof v === 'string' && v.trim()) return v.trim();
  }
  return undefined;
}

async function sendOrderUpdatePush(payload) {
  if (!CENTRAL_NOTIFICATIONS_BASE_URL || !CENTRAL_NOTIFICATIONS_INTERNAL_KEY) {
    console.log('ℹ️ Central push not configured; skipping push send');
    return;
  }

  const url = `${CENTRAL_NOTIFICATIONS_BASE_URL.replace(/\/$/, '')}/push/send/order-update`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6000);

  try {
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-internal-key': CENTRAL_NOTIFICATIONS_INTERNAL_KEY
      },
      body: JSON.stringify(payload),
      signal: controller.signal
    });

    const text = await resp.text();
    if (!resp.ok) {
      console.error('❌ Central push failed', { status: resp.status, body: text.slice(0, 500) });
      return;
    }
    console.log('✅ Central push sent', text.slice(0, 500));
  } catch (e) {
    console.error('❌ Central push error', e?.message || String(e));
  } finally {
    clearTimeout(timeout);
  }
}

async function processRecord(record, docClient, apiGwClient, websocketTable) {
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
  const previousStatus = oldImage?.status?.S;
  const businessId = orderData?.businessId?.S;
  const userId = orderData?.userId?.S;
  const userSub = orderData?.userSub?.S;
  const guestToken = orderData?.guestToken?.S;

  if (!orderId) {
    console.log('⚠️ No orderId found in stream record');
    return;
  }

  console.log(`📦 Processing order update: ${orderId}, status: ${status}, eventName: ${eventName}`);

  // Only push on meaningful status changes to avoid spamming users.
  const statusChanged = Boolean(status) && status !== previousStatus;
  const shouldSendPush = (eventName === 'INSERT' && Boolean(status)) || (eventName === 'MODIFY' && statusChanged);

  const guestSubjectId = guestToken ? `GUEST_${guestToken}` : null;
  const targetSubjectId = userSub || userId || guestSubjectId;
  if (shouldSendPush && targetSubjectId) {
    const orderNumber = extractString(
      orderData,
      (d) => d?.orderNumber?.S,
      (d) => d?.orderNumber_gsi?.S,
      (d) => d?.orderNo?.S
    );
    const businessName = extractString(
      orderData,
      (d) => d?.businessName?.S,
      (d) => d?.storeName?.S,
      (d) => d?.restaurantName?.S
    );

    await sendOrderUpdatePush({
      userId: targetSubjectId,
      orderId,
      orderNumber: orderNumber || '',
      status: status || '',
      businessName: businessName || '',
      updatedAt: new Date().toISOString()
    });
  }

  // Create notification payload with Arabic message
  const notification = {
    type: 'order_update',
    orderId,
    status: status || 'unknown',
    businessId,
    userId: targetSubjectId,
    updatedAt: new Date().toISOString(),
    eventName: eventName || 'MODIFY',
    message: getArabicStatusMessage(status || 'unknown')
  };

  // Find WebSocket connections that should receive this notification
  const connections = await findRelevantConnections(docClient, websocketTable, orderId, userId, businessId);
  
  console.log(`🔍 Found ${connections.length} relevant connections for order ${orderId}`);

  // Send notifications to all relevant connections
  const notificationPromises = connections.map(connection => 
    sendNotificationToConnection(apiGwClient, connection.connectionId, notification, docClient, websocketTable)
  );

  await Promise.allSettled(notificationPromises);
}

async function findRelevantConnections(docClient, websocketTable, orderId, userId, businessId) {
  const connections = [];

  try {
    console.log(`🔍 Looking for WebSocket connections for:`, {
      orderId,
      userId,
      businessId
    });

    // Since the schema uses PK=CONNECTION#id and SK=CONNECTION#id or MERCHANT#businessId,
    // we need to scan the table to find relevant connections
    const scanParams = {
      TableName: websocketTable,
      ProjectionExpression: 'PK, SK, connectionId, userId, orderId, connectedAt, GSI1PK, GSI1SK'
    };

    const scanResult = await docClient.send(new ScanCommand(scanParams));
    
    if (scanResult.Items) {
      console.log(`📊 Total items in WebSocket table: ${scanResult.Items.length}`);
      
      // Log sample data structure
      if (scanResult.Items.length > 0) {
        console.log('📋 Sample WebSocket connection structure:', scanResult.Items[0]);
      }

      const relevantConnections = scanResult.Items
        .filter(item => {
          // Extract connectionId from PK (format: CONNECTION#connectionId)
          const connectionId = item.PK?.replace('CONNECTION#', '');
          
          // Check if this is a valid connection record (not merchant metadata)
          const isConnectionRecord = item.SK?.startsWith('CONNECTION#');
          
          if (!isConnectionRecord || !connectionId) {
            return false;
          }

          // Include connections that match userId, orderId, or are subscribed to the business
          const matchesUser = userId && item.userId === userId;
          const matchesOrder = orderId && item.orderId === orderId;
          const matchesBusiness = businessId && (
            item.GSI1PK === `MERCHANT#${businessId}` ||
            item.SK === `MERCHANT#${businessId}`
          );

          const shouldInclude = matchesUser || matchesOrder || matchesBusiness;
          
          if (shouldInclude) {
            console.log(`✅ Including connection ${connectionId}:`, {
              userId: item.userId,
              orderId: item.orderId,
              gsi1pk: item.GSI1PK,
              sk: item.SK,
              reason: matchesUser ? 'user match' : matchesOrder ? 'order match' : 'business match'
            });
          }
          
          return shouldInclude;
        })
        .map(item => ({
          connectionId: item.PK?.replace('CONNECTION#', '') || item.connectionId,
          userId: item.userId,
          orderId: item.orderId,
          connectedAt: item.connectedAt,
          pk: item.PK,
          sk: item.SK,
          gsi1pk: item.GSI1PK
        }));

      connections.push(...relevantConnections);
      
      // Remove duplicates based on connectionId
      const uniqueConnections = connections.filter((conn, index, self) => 
        index === self.findIndex(c => c.connectionId === conn.connectionId)
      );
      
      console.log(`🔗 Found ${uniqueConnections.length} relevant connections for order ${orderId}`);
      uniqueConnections.forEach(conn => {
        console.log(`  - Connection: ${conn.connectionId}, User: ${conn.userId}, Order: ${conn.orderId}`);
      });
      
      return uniqueConnections;
    } else {
      console.log('⚠️ No WebSocket connections found in table');
    }

  } catch (error) {
    console.error('❌ Error scanning WebSocket connections:', error);
  }

  return connections;
}

async function sendNotificationToConnection(agmApiClient, connectionId, notification, docClient, websocketTable) {
  try {
    const command = new PostToConnectionCommand({
      ConnectionId: connectionId,
      Data: JSON.stringify(notification)
    });

    await agmApiClient.send(command);
    console.log(`✅ Notification sent to connection ${connectionId} for order ${notification.orderId}`);
    
  } catch (error) {
    console.error(`❌ Failed to send notification to connection ${connectionId}:`, error);
    
    // If connection is stale (410 error), remove it from the table
    if (error.statusCode === 410) {
      console.log(`🧹 Removing stale connection ${connectionId}`);
      await removeStaleConnection(docClient, websocketTable, connectionId);
    }
  }
}

async function removeStaleConnection(docClient, websocketTable, connectionId) {
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

function getArabicStatusMessage(status) {
  const statusMessages = {
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
