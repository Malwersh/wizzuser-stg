const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, ScanCommand, DeleteCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');

const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);

const ORDERS_TABLE = process.env.ORDERS_TABLE || 'WizzOrders';
const SUBSCRIPTIONS_TABLE = process.env.WEBSOCKET_SUBSCRIPTIONS_TABLE || 'WizzUser_websocket_subscriptions_dev';

/**
 * Enhanced order update function that sends to all relevant subscriptions:
 * 1. Individual order subscriptions
 * 2. User orders subscriptions  
 * 3. Guest orders subscriptions
 */
async function sendEnhancedOrderUpdate(orderId, updateData, websocketEndpoint) {
  try {
    console.log(`🚀 Enhanced order update for order: ${orderId}`);
    
    // Get order details to determine userId or guestToken
    const orderDetails = await getOrderDetails(orderId);
    if (!orderDetails) {
      console.error(`❌ Order not found: ${orderId}`);
      return;
    }
    
    const userId = orderDetails.userId;
    const guestToken = orderDetails.guestToken;
    
    console.log(`📋 Order details - userId: ${userId}, guestToken: ${guestToken}`);
    
    // Initialize API Gateway Management API client
    const apiGatewayClient = new ApiGatewayManagementApiClient({
      endpoint: websocketEndpoint
    });
    
    // Prepare the WebSocket message
    const message = {
      type: 'ORDER_STATUS_UPDATE',
      orderId: orderId,
      orderNumber: updateData.orderNumber || '',
      status: updateData.status,
      estimatedDeliveryTime: updateData.estimatedDeliveryTime,
      deliveryTime: updateData.deliveryTime,
      message: getStatusMessage(updateData.status),
      timestamp: new Date().toISOString(),
      userId: userId,
      guestToken: guestToken
    };
    
    const messageData = JSON.stringify(message);
    console.log(`📤 Message to send: ${messageData}`);
    
    // Collection to track all connections to notify
    const connectionsToNotify = new Set();
    
    // 1. Find individual order subscriptions
    console.log(`🔍 Finding individual order subscriptions for order ${orderId}`);
    try {
      const orderSubscriptions = await findOrderSubscriptions(orderId);
      console.log(`📋 Found ${orderSubscriptions.length} individual order subscriptions`);
      
      orderSubscriptions.forEach(sub => {
        if (sub.connectionId) {
          connectionsToNotify.add(sub.connectionId);
        }
      });
    } catch (error) {
      console.error(`❌ Error finding order subscriptions: ${error}`);
    }
    
    // 2. Find user orders subscriptions (for registered users)
    if (userId && userId !== 'guest') {
      console.log(`🎯 Finding user orders subscriptions for user ${userId}`);
      try {
        const userSubscriptions = await findUserOrdersSubscriptions(userId);
        console.log(`👤 Found ${userSubscriptions.length} user orders subscriptions`);
        
        userSubscriptions.forEach(sub => {
          if (sub.connectionId) {
            connectionsToNotify.add(sub.connectionId);
          }
        });
      } catch (error) {
        console.error(`❌ Error finding user orders subscriptions: ${error}`);
      }
    }
    
    // 3. Find guest orders subscriptions (for guest users)
    if (guestToken) {
      console.log(`🎭 Finding guest orders subscriptions for token ${guestToken}`);
      try {
        const guestSubscriptions = await findGuestOrdersSubscriptions(guestToken);
        console.log(`🎭 Found ${guestSubscriptions.length} guest orders subscriptions`);
        
        guestSubscriptions.forEach(sub => {
          if (sub.connectionId) {
            connectionsToNotify.add(sub.connectionId);
          }
        });
      } catch (error) {
        console.error(`❌ Error finding guest orders subscriptions: ${error}`);
      }
    }
    
    console.log(`📡 Total unique connections to notify: ${connectionsToNotify.size}`);
    
    if (connectionsToNotify.size === 0) {
      console.log(`⚠️ No active connections found for order: ${orderId}`);
      return;
    }
    
    // Send message to all connections
    const sendPromises = Array.from(connectionsToNotify).map(async (connectionId) => {
      try {
        const postCommand = new PostToConnectionCommand({
          ConnectionId: connectionId,
          Data: messageData
        });
        
        await apiGatewayClient.send(postCommand);
        console.log(`✅ Message sent to connection: ${connectionId}`);
        return { success: true, connectionId };
      } catch (error) {
        console.error(`❌ Failed to send message to connection ${connectionId}:`, error);
        
        // If connection is stale (410 error), clean up
        if (error.$metadata?.httpStatusCode === 410 || error.name === 'GoneException') {
          console.log(`🧹 Cleaning up stale connection: ${connectionId}`);
          await cleanupStaleConnection(connectionId);
        }
        
        return { success: false, connectionId, error: error.message };
      }
    });
    
    const results = await Promise.all(sendPromises);
    const successCount = results.filter(r => r.success).length;
    const failureCount = results.filter(r => !r.success).length;
    
    console.log(`📊 Notification results: ${successCount} succeeded, ${failureCount} failed`);
    
  } catch (error) {
    console.error(`❌ Error in enhanced order update:`, error);
    throw error;
  }
}

/**
 * Get order details from DynamoDB
 */
async function getOrderDetails(orderId) {
  try {
    const result = await docClient.send(new GetCommand({
      TableName: ORDERS_TABLE,
      Key: {
        PK: `ORDER#${orderId}`,
        SK: `ORDER#${orderId}`
      }
    }));
    
    return result.Item || null;
  } catch (error) {
    console.error(`Error fetching order details for ${orderId}:`, error);
    throw error;
  }
}

/**
 * Find individual order subscriptions
 */
async function findOrderSubscriptions(orderId) {
  try {
    const result = await docClient.send(new ScanCommand({
      TableName: SUBSCRIPTIONS_TABLE,
      FilterExpression: 'orderId = :orderId AND subscriptionType = :subType',
      ExpressionAttributeValues: {
        ':orderId': orderId,
        ':subType': 'order_tracking'
      }
    }));
    
    return result.Items || [];
  } catch (error) {
    console.error(`Error finding order subscriptions:`, error);
    return [];
  }
}

/**
 * Find user orders subscriptions
 */
async function findUserOrdersSubscriptions(userId) {
  try {
    const result = await docClient.send(new ScanCommand({
      TableName: SUBSCRIPTIONS_TABLE,
      FilterExpression: 'userId = :userId AND subscriptionType = :subType',
      ExpressionAttributeValues: {
        ':userId': userId,
        ':subType': 'user_orders'
      }
    }));
    
    return result.Items || [];
  } catch (error) {
    console.error(`Error finding user orders subscriptions:`, error);
    return [];
  }
}

/**
 * Find guest orders subscriptions
 */
async function findGuestOrdersSubscriptions(guestToken) {
  try {
    const result = await docClient.send(new ScanCommand({
      TableName: SUBSCRIPTIONS_TABLE,
      FilterExpression: 'guestToken = :guestToken AND subscriptionType = :subType',
      ExpressionAttributeValues: {
        ':guestToken': guestToken,
        ':subType': 'guest_orders'
      }
    }));
    
    return result.Items || [];
  } catch (error) {
    console.error(`Error finding guest orders subscriptions:`, error);
    return [];
  }
}

/**
 * Clean up stale connection from subscriptions
 */
async function cleanupStaleConnection(connectionId) {
  try {
    // Find all subscriptions for this connection
    const result = await docClient.send(new ScanCommand({
      TableName: SUBSCRIPTIONS_TABLE,
      FilterExpression: 'connectionId = :connId',
      ExpressionAttributeValues: {
        ':connId': connectionId
      }
    }));
    
    // Delete all subscriptions for this connection
    const deletePromises = (result.Items || []).map(item => 
      docClient.send(new DeleteCommand({
        TableName: SUBSCRIPTIONS_TABLE,
        Key: {
          subscriptionId: item.subscriptionId
        }
      }))
    );
    
    await Promise.all(deletePromises);
    console.log(`🧹 Cleaned up ${deletePromises.length} stale subscriptions for connection ${connectionId}`);
  } catch (error) {
    console.error(`Error cleaning up stale connection ${connectionId}:`, error);
  }
}

/**
 * Get status message in Arabic
 */
function getStatusMessage(status) {
  const statusMessages = {
    'pending': 'تم استلام طلبك وننتظر موافقة المطعم',
    'confirmed': 'تم تأكيد طلبك من المطعم',
    'preparing': 'يتم تحضير طلبك الآن',
    'ready': 'طلبك جاهز للتوصيل',
    'on_the_way': 'السائق في الطريق إليك',
    'delivered': 'تم توصيل طلبك بنجاح',
    'cancelled': 'تم إلغاء الطلب',
    'expired': 'انتهت صلاحية الطلب',
    'failed': 'فشل في معالجة الطلب'
  };
  return statusMessages[status] || 'تحديث حالة الطلب';
}

/**
 * Lambda handler that uses the enhanced function
 */
exports.handler = async (event) => {
  console.log('Enhanced WebSocket Send Update Handler');
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    const { orderId, updateData, websocketEndpoint } = event;
    
    if (!orderId || !updateData || !websocketEndpoint) {
      throw new Error('Missing required parameters: orderId, updateData, or websocketEndpoint');
    }
    
    await sendEnhancedOrderUpdate(orderId, updateData, websocketEndpoint);
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: 'Enhanced order update sent successfully'
      })
    };
  } catch (error) {
    console.error('Enhanced WebSocket Send Update Error:', error);
    
    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: error.message
      })
    };
  }
};

// Export the enhanced function for use in other modules
exports.sendEnhancedOrderUpdate = sendEnhancedOrderUpdate;
