// WebSocket Helper - Updated 2025-08-21
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, DeleteCommand, PutCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';

const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(dynamoClient);

const CONNECTIONS_TABLE = process.env.WEBSOCKET_CONNECTIONS_TABLE;
const SUBSCRIPTIONS_TABLE = process.env.WEBSOCKET_SUBSCRIPTIONS_TABLE;

if (!CONNECTIONS_TABLE) {
  throw new Error('Missing required env var: WEBSOCKET_CONNECTIONS_TABLE');
}

if (!SUBSCRIPTIONS_TABLE) {
  throw new Error('Missing required env var: WEBSOCKET_SUBSCRIPTIONS_TABLE');
}

export interface DeviceInfo {
  platform: 'ios' | 'android' | 'web';
  appVersion: string;
  deviceId: string;
}

/**
 * البحث عن اتصالات بناءً على معرف المستخدم ونوعه
 * يعمل مع هيكل جدول wizzgo-dev-wss-onconnect المشترك
 */
export async function findConnectionsByUserId(userId: string, userType: 'customer' | 'driver' | 'restaurant' = 'customer'): Promise<any[]> {
  try {
    // تحديد GSI1PK حسب نوع المستخدم
    let gsi1PK = `USER#${userId}`;
    let entityTypeFilter = 'customer';
    
    switch (userType) {
      case 'restaurant':
        // للمطاعم قد يكون لديهم businessId، لذلك نبحث في userId والentityType
        entityTypeFilter = 'merchant';
        break;
      case 'driver':
        gsi1PK = `DRIVER#${userId}`;
        entityTypeFilter = 'driver';
        break;
      case 'customer':
      default:
        gsi1PK = `USER#${userId}`;
        entityTypeFilter = 'customer';
        break;
    }

    // البحث باستخدام GSI1 لتحسين الأداء
    console.log(`🔍 البحث عن اتصالات للمستخدم ${userId} من نوع ${userType} (GSI1PK: ${gsi1PK})`);
    
    try {
      const queryResult = await docClient.send(new QueryCommand({
        TableName: CONNECTIONS_TABLE,
        IndexName: 'GSI1',
        KeyConditionExpression: 'GSI1PK = :gsi1pk',
        FilterExpression: 'userId = :userId AND entityType = :entityType',
        ExpressionAttributeValues: {
          ':gsi1pk': gsi1PK,
          ':userId': userId,
          ':entityType': entityTypeFilter
        }
      }));

      const connections = queryResult.Items || [];
      console.log(`📊 تم العثور على ${connections.length} اتصال للمستخدم ${userId}`);
      
      return connections;
    } catch (gsiError) {
      console.warn(`⚠️ فشل البحث بـ GSI، محاولة البحث بـ Scan:`, gsiError);
      
      // Fallback to scan if GSI query fails
      const scanResult = await docClient.send(new ScanCommand({
        TableName: CONNECTIONS_TABLE,
        FilterExpression: 'userId = :userId AND entityType = :entityType',
        ExpressionAttributeValues: {
          ':userId': userId,
          ':entityType': entityTypeFilter
        }
      }));

      return scanResult.Items || [];
    }
  } catch (error) {
    console.error(`❌ خطأ في البحث عن اتصالات المستخدم ${userId} من نوع ${userType}:`, error);
    return [];
  }
}

/**
 * تنظيف جميع اتصالات واشتراكات مستخدم معين
 * يعمل مع هيكل جدول wizzgo-dev-wss-onconnect المشترك
 */
export async function cleanupUserConnections(userId: string, userType: 'customer' | 'driver' | 'restaurant' = 'customer'): Promise<{
  connectionsRemoved: number;
  subscriptionsRemoved: number;
  connectionIds: string[];
}> {
  const connectionIds: string[] = [];
  let connectionsRemoved = 0;
  let subscriptionsRemoved = 0;

  try {
    console.log(`🧹 بدء تنظيف اتصالات ${userType} للمستخدم: ${userId}`);
    
    // البحث عن جميع اتصالات المستخدم
    const connections = await findConnectionsByUserId(userId, userType);
    
    for (const connection of connections) {
      const connectionId = connection.connectionId;
      connectionIds.push(connectionId);
      
      // حذف جميع اشتراكات هذا الاتصال أولاً (إذا كان هناك جدول اشتراكات)
      try {
        const subscriptionsResult = await docClient.send(new ScanCommand({
          TableName: SUBSCRIPTIONS_TABLE,
          FilterExpression: 'connectionId = :connectionId',
          ExpressionAttributeValues: {
            ':connectionId': connectionId
          }
        }));

        if (subscriptionsResult.Items && subscriptionsResult.Items.length > 0) {
          const deletePromises = subscriptionsResult.Items.map(item => 
            docClient.send(new DeleteCommand({
              TableName: SUBSCRIPTIONS_TABLE,
              Key: { subscriptionId: item.subscriptionId } // Use correct primary key
            }))
          );

          await Promise.allSettled(deletePromises);
          subscriptionsRemoved += subscriptionsResult.Items.length;
          console.log(`🗑️ تم حذف ${subscriptionsResult.Items.length} اشتراك للاتصال ${connectionId}`);
        }
      } catch (subsError) {
        console.warn(`⚠️ تعذر حذف اشتراكات الاتصال ${connectionId}:`, subsError);
      }
      
      // حذف الاتصال نفسه
      try {
        await docClient.send(new DeleteCommand({
          TableName: CONNECTIONS_TABLE,
          Key: { connectionId: connectionId }
        }));
        connectionsRemoved++;
        console.log(`✅ تم حذف الاتصال: ${connectionId}`);
      } catch (delError) {
        console.error(`❌ فشل في حذف الاتصال ${connectionId}:`, delError);
      }
    }

    console.log(`✅ تم تنظيف ${connectionsRemoved} اتصال و ${subscriptionsRemoved} اشتراك للمستخدم: ${userId}`);
    return { connectionsRemoved, subscriptionsRemoved, connectionIds };
  } catch (error) {
    console.error(`❌ خطأ في تنظيف اتصالات المستخدم ${userId}:`, error);
    return { connectionsRemoved, subscriptionsRemoved, connectionIds };
  }
}

/**
 * إضافة اتصال WebSocket جديد مع منع الاتصالات المتعددة
 * يتوافق مع هيكل جدول wizzgo-dev-wss-onconnect المشترك
 */
export async function addConnection(connectionData: {
  connectionId: string;
  userId: string;
  userType?: 'customer' | 'driver' | 'restaurant';
  deviceInfo?: DeviceInfo;
  businessId?: string;
  [key: string]: any;
}): Promise<void> {
  try {
    // Default values for customer app
    const userType = connectionData.userType || 'customer';
    const now = new Date().toISOString();
    const ttl = Math.floor(Date.now() / 1000) + 86400; // 24 hours
    
    // تنظيف اتصالات المستخدم الموجودة (لمنع الاتصالات المتعددة)
    console.log(`🧹 تنظيف اتصالات ${userType} السابقة للمستخدم: ${connectionData.userId}`);
    await cleanupUserConnections(connectionData.userId, userType);
    
    // تحديد entityType حسب نوع المستخدم
    let entityType = 'customer';  // القيم الافتراضية
    let gsi1PK = `USER#${connectionData.userId}`;
    
    switch (userType) {
      case 'restaurant':
        entityType = 'merchant';
        gsi1PK = connectionData.businessId ? `BUSINESS#${connectionData.businessId}` : `USER#${connectionData.userId}`;
        break;
      case 'driver':
        entityType = 'driver';
        gsi1PK = `DRIVER#${connectionData.userId}`;
        break;
      case 'customer':
      default:
        entityType = 'customer';
        gsi1PK = `USER#${connectionData.userId}`;
        break;
    }

    // بناء السجل حسب هيكل الجدول الصحيح
    const connectionRecord = {
      // Primary Key Structure
      connectionId: connectionData.connectionId,
      PK: `CONNECTION#${connectionData.connectionId}`,
      SK: `CONNECTION#${connectionData.connectionId}`,
      
      // GSI1 Index for querying by user/business/driver
      GSI1PK: gsi1PK,
      GSI1SK: `CONNECTION#${connectionData.connectionId}`,
      
      // Connection Details
      userId: connectionData.userId,
      entityType: entityType,
      connectedAt: now,
      ttl: ttl,
      
      // Business ID for restaurants
      ...(connectionData.businessId && { businessId: connectionData.businessId }),
      
      // Device Info (flattened)
      platform: connectionData.deviceInfo?.platform || 'android',
      appVersion: connectionData.deviceInfo?.appVersion || '1.0.0',
      deviceId: connectionData.deviceInfo?.deviceId || 'unknown'
    };

    console.log(`📝 إضافة اتصال جديد ${entityType}:`, JSON.stringify(connectionRecord, null, 2));

    await docClient.send(new PutCommand({
      TableName: CONNECTIONS_TABLE,
      Item: connectionRecord
    }));

    console.log(`✅ تم إضافة اتصال ${entityType}: ${connectionData.connectionId}`);
    console.log(`   👤 المستخدم: ${connectionData.userId}`);
    console.log(`   📱 المنصة: ${connectionRecord.platform}`);
    console.log(`   🔍 GSI1PK: ${gsi1PK}`);

  } catch (error) {
    console.error(`❌ خطأ في إضافة اتصال WebSocket:`, error);
    throw error;
  }
}

/**
 * إضافة اشتراك WebSocket
 */
export async function addSubscription(connectionData: {
  connectionId: string;
  userId: string;
  userType?: 'customer' | 'driver' | 'restaurant';
  entityType?: string; // For backward compatibility
  subscriptionType: 'order_updates' | 'location_tracking' | 'business_status' | 'driver_orders';
  orderId?: string;
  businessId?: string;
  driverId?: string;
}): Promise<void> {
  try {
    console.log(`📋 محاولة إضافة اشتراك ${connectionData.subscriptionType} للاتصال ${connectionData.connectionId}`);
    
    const subscriptionId = `${connectionData.connectionId}_${connectionData.subscriptionType}_${Date.now()}`;
    const now = new Date().toISOString();
    
    // Create topic for GSI - format based on subscription type
    let topic: string;
    switch (connectionData.subscriptionType) {
      case 'order_updates':
        topic = connectionData.orderId ? `order:${connectionData.orderId}` : `user:${connectionData.userId}:orders`;
        break;
      case 'business_status':
        topic = connectionData.businessId ? `business:${connectionData.businessId}` : `user:${connectionData.userId}:business`;
        break;
      case 'location_tracking':
        topic = `driver:${connectionData.driverId || connectionData.userId}:location`;
        break;
      case 'driver_orders':
        topic = `driver:${connectionData.userId}:orders`;
        break;
      default:
        topic = `user:${connectionData.userId}:${connectionData.subscriptionType}`;
    }

    const subscriptionRecord = {
      subscriptionId: subscriptionId, // Correct primary key field
      connectionId: connectionData.connectionId,
      subscriptionType: connectionData.subscriptionType,
      userId: connectionData.userId,
      userType: connectionData.userType || connectionData.entityType || 'customer', // Support both fields
      topic: topic, // Required for GSI
      orderId: connectionData.orderId,
      businessId: connectionData.businessId,
      driverId: connectionData.driverId,
      isActive: true,
      createdAt: now
    };

    await docClient.send(new PutCommand({
      TableName: SUBSCRIPTIONS_TABLE,
      Item: subscriptionRecord
    }));

    console.log(`✅ تم إضافة اشتراك ${connectionData.subscriptionType}: ${subscriptionId} مع الموضوع: ${topic}`);
  } catch (error) {
    console.error(`❌ خطأ في إضافة اشتراك:`, error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.warn(`⚠️ لم يتم إضافة اشتراك ${connectionData.subscriptionType} - سيتم التجاهل: ${errorMessage}`);
    // Don't throw - let the connection proceed even if subscription fails
  }
}

/**
 * حذف اتصال معين
 * يعمل مع هيكل جدول wizzgo-dev-wss-onconnect
 */
export async function removeConnection(connectionId: string): Promise<void> {
  try {
    await docClient.send(new DeleteCommand({
      TableName: CONNECTIONS_TABLE,
      Key: { connectionId: connectionId }  // استخدام connectionId كمفتاح أساسي
    }));
    console.log(`✅ تم حذف اتصال: ${connectionId}`);
  } catch (error) {
    console.error(`❌ خطأ في حذف الاتصال ${connectionId}:`, error);
  }
}

/**
 * حذف جميع اشتراكات الاتصال
 */
export async function removeConnectionSubscriptions(connectionId: string): Promise<void> {
  try {
    // البحث عن جميع اشتراكات هذا الاتصال
    const scanResult = await docClient.send(new ScanCommand({
      TableName: SUBSCRIPTIONS_TABLE,
      FilterExpression: 'connectionId = :connectionId',
      ExpressionAttributeValues: {
        ':connectionId': connectionId
      }
    }));

    if (scanResult.Items && scanResult.Items.length > 0) {
      // حذف جميع الاشتراكات
      const deletePromises = scanResult.Items.map(item => 
        docClient.send(new DeleteCommand({
          TableName: SUBSCRIPTIONS_TABLE,
          Key: { subscriptionId: item.subscriptionId } // Use correct primary key
        }))
      );

      await Promise.allSettled(deletePromises);
      console.log(`✅ تم حذف ${scanResult.Items.length} اشتراك للاتصال: ${connectionId}`);
    }
  } catch (error) {
    console.error(`❌ خطأ في حذف اشتراكات الاتصال ${connectionId}:`, error);
  }
}

/**
 * الحصول على تفاصيل اتصال معين
 */
export async function getConnection(connectionId: string): Promise<any | null> {
  try {
    const result = await docClient.send(new ScanCommand({
      TableName: CONNECTIONS_TABLE,
      FilterExpression: 'connectionId = :connectionId',
      ExpressionAttributeValues: {
        ':connectionId': connectionId
      },
      Limit: 1
    }));

    if (result.Items && result.Items.length > 0) {
      return result.Items[0];
    }
    return null;
  } catch (error) {
    console.error(`❌ خطأ في الحصول على تفاصيل الاتصال ${connectionId}:`, error);
    return null;
  }
}

/**
 * البحث عن اتصالات مشتركة في طلب معين
 */
export async function findConnectionsByOrderId(orderId: string): Promise<any[]> {
  try {
    // البحث في جدول الاشتراكات أولاً
    const subscriptionsResult = await docClient.send(new ScanCommand({
      TableName: SUBSCRIPTIONS_TABLE,
      FilterExpression: 'orderId = :orderId AND subscriptionType = :type',
      ExpressionAttributeValues: {
        ':orderId': orderId,
        ':type': 'order_updates'
      }
    }));

    if (!subscriptionsResult.Items || subscriptionsResult.Items.length === 0) {
      return [];
    }

    // الحصول على connectionIds
    const connectionIds = subscriptionsResult.Items.map(item => item.connectionId).filter(Boolean);
    
    if (connectionIds.length === 0) {
      return [];
    }

    // البحث عن تفاصيل الاتصالات
    const connections: any[] = [];
    for (const connectionId of connectionIds) {
      const connection = await getConnection(connectionId);
      if (connection) {
        connections.push(connection);
      }
    }

    return connections;
  } catch (error) {
    console.error(`❌ خطأ في البحث عن اتصالات الطلب ${orderId}:`, error);
    return [];
  }
}

/**
 * البحث عن اتصالات مشتركة في مطعم معين
 */
export async function findConnectionsByBusinessId(businessId: string): Promise<any[]> {
  try {
    // البحث في جدول الاشتراكات أولاً
    const subscriptionsResult = await docClient.send(new ScanCommand({
      TableName: SUBSCRIPTIONS_TABLE,
      FilterExpression: 'businessId = :businessId AND subscriptionType = :type',
      ExpressionAttributeValues: {
        ':businessId': businessId,
        ':type': 'business_status'
      }
    }));

    if (!subscriptionsResult.Items || subscriptionsResult.Items.length === 0) {
      return [];
    }

    // الحصول على connectionIds
    const connectionIds = subscriptionsResult.Items.map(item => item.connectionId).filter(Boolean);
    
    if (connectionIds.length === 0) {
      return [];
    }

    // البحث عن تفاصيل الاتصالات
    const connections: any[] = [];
    for (const connectionId of connectionIds) {
      const connection = await getConnection(connectionId);
      if (connection) {
        connections.push(connection);
      }
    }

    return connections;
  } catch (error) {
    console.error(`❌ خطأ في البحث عن اتصالات المطعم ${businessId}:`, error);
    return [];
  }
}

/**
 * تحديث آخر نشاط للاتصال
 */
export async function updateConnectionActivity(connectionId: string): Promise<void> {
  try {
    // نظرًا لأن الجدول يستخدم connectionId كمفتاح أساسي، نحتاج لقراءة السجل أولاً ثم تحديثه
    const connection = await getConnection(connectionId);
    if (!connection) {
      console.warn(`⚠️ لم يتم العثور على اتصال: ${connectionId}`);
      return;
    }

    // تحديث آخر نشاط
    connection.lastActiveAt = new Date().toISOString();

    await docClient.send(new PutCommand({
      TableName: CONNECTIONS_TABLE,
      Item: connection
    }));

    console.log(`✅ تم تحديث آخر نشاط للاتصال: ${connectionId}`);
  } catch (error) {
    console.error(`❌ خطأ في تحديث نشاط الاتصال ${connectionId}:`, error);
  }
}

/**
 * الحصول على إحصائيات الاتصالات النشطة
 */
export async function getActiveConnectionsStats(): Promise<{
  total: number;
  byType: Record<string, number>;
  byPlatform: Record<string, number>;
}> {
  try {
    const scanResult = await docClient.send(new ScanCommand({
      TableName: CONNECTIONS_TABLE
    }));

    const connections = scanResult.Items || [];
    const stats = {
      total: connections.length,
      byType: {} as Record<string, number>,
      byPlatform: {} as Record<string, number>
    };

    for (const connection of connections) {
      // إحصائيات حسب نوع الكيان
      const entityType = connection.entityType || 'unknown';
      stats.byType[entityType] = (stats.byType[entityType] || 0) + 1;

      // إحصائيات حسب المنصة
      const platform = connection.platform || 'unknown';
      stats.byPlatform[platform] = (stats.byPlatform[platform] || 0) + 1;
    }

    return stats;
  } catch (error) {
    console.error('❌ خطأ في الحصول على إحصائيات الاتصالات:', error);
    return {
      total: 0,
      byType: {},
      byPlatform: {}
    };
  }
}
