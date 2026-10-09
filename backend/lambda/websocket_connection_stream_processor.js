/**
 * WebSocket Connection Stream Processor
 * 
 * يعالج DynamoDB Stream من WizzUser_websocket_connections_<env>
 * ويُحدّث WizzDriverLiveState.connectionId تلقائياً
 * 
 * Events:
 * - INSERT: اتصال جديد → تحديث connectionId
 * - MODIFY: تحديث حالة الاتصال → تحديث connectionId إذا تغير
 * - REMOVE: قطع اتصال → إزالة connectionId
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const { unmarshall } = require('@aws-sdk/util-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamoDB = DynamoDBDocumentClient.from(client);

const envName = process.env.ENVIRONMENT || process.env.Environment || process.env.WEBSOCKET_STAGE || 'dev';
const DRIVER_LIVE_STATE_TABLE = process.env.DRIVER_LIVE_STATE_TABLE || `WizzDriverLiveState_${envName}`;

function isInvalidId(value) {
  if (value === undefined || value === null) return true;
  const s = String(value).trim().toLowerCase();
  return s === '' || s === 'unknown' || s === 'null' || s === 'undefined' || s === 'none';
}

exports.handler = async (event) => {
  console.log(`📊 Received ${event.Records.length} stream records`);

  for (const record of event.Records) {
    try {
      const eventName = record.eventName; // INSERT, MODIFY, REMOVE
      console.log(`📋 Processing ${eventName} event`);

      // استخراج البيانات القديمة والجديدة
      const oldImage = record.dynamodb.OldImage ? unmarshall(record.dynamodb.OldImage) : null;
      const newImage = record.dynamodb.NewImage ? unmarshall(record.dynamodb.NewImage) : null;

      // نعالج فقط اتصالات السائقين
      const entityType = newImage?.entityType || oldImage?.entityType;
      if (entityType !== 'driver') {
        console.log(`ℹ️ Skipping non-driver connection (${entityType})`);
        continue;
      }

      const driverId = newImage?.driverId || oldImage?.driverId;
      if (!driverId || isInvalidId(driverId)) {
        console.warn(`⚠️ No driverId found in record`);
        continue;
      }

      console.log(`🚗 Processing driver ${driverId} connection event: ${eventName}`);

      // ============================================
      // حالة 1: INSERT أو MODIFY - تحديث connectionId
      // ============================================
      if (eventName === 'INSERT' || eventName === 'MODIFY') {
        const connectionId = newImage?.connectionId;
        const isActive = newImage?.isActive;
        const status = newImage?.status;

        // فقط إذا كان الاتصال نشط
        const isConnectedStatus = status === 'connected' || status === 'active';
        if (isActive === true && isConnectedStatus && connectionId) {
          console.log(`✅ Updating WizzDriverLiveState with new connectionId: ${connectionId}`);
          
          await dynamoDB.send(new UpdateCommand({
            TableName: DRIVER_LIVE_STATE_TABLE,
            Key: { driverId },
            UpdateExpression: `
              SET connectionId = :connId,
                  connectionStatus = :connStatus,
                  lastConnected = :now,
                  lastUpdated = :now
            `,
            ExpressionAttributeValues: {
              ':connId': connectionId,
              ':connStatus': 'connected',
              ':now': new Date().toISOString()
            }
          }));

          console.log(`✅ Updated connectionId for driver ${driverId}`);
        }
        // إذا كان الاتصال أصبح غير نشط
        else if (isActive === false || status === 'disconnected') {
          console.log(`ℹ️ Connection became inactive, clearing connectionId`);

          const oldConnId = connectionId || oldImage?.connectionId;
          
          await dynamoDB.send(new UpdateCommand({
            TableName: DRIVER_LIVE_STATE_TABLE,
            Key: { driverId },
            UpdateExpression: `
              SET connectionStatus = :disconnected,
                  lastDisconnected = :now
              REMOVE connectionId
            `,
            ConditionExpression: 'connectionId = :oldConnId',
            ExpressionAttributeValues: {
              ':disconnected': 'disconnected',
              ':now': new Date().toISOString(),
              ':oldConnId': oldConnId
            }
          }));

          console.log(`✅ Cleared connectionId for driver ${driverId}`);
        }
      }

      // ============================================
      // حالة 2: REMOVE - إزالة connectionId
      // ============================================
      else if (eventName === 'REMOVE') {
        const oldConnectionId = oldImage?.connectionId;
        
        console.log(`🗑️ Connection removed, clearing connectionId: ${oldConnectionId}`);
        
        await dynamoDB.send(new UpdateCommand({
          TableName: DRIVER_LIVE_STATE_TABLE,
          Key: { driverId },
          UpdateExpression: `
            SET connectionStatus = :disconnected,
                lastDisconnected = :now
            REMOVE connectionId
          `,
          ConditionExpression: 'connectionId = :oldConnId',
          ExpressionAttributeValues: {
            ':disconnected': 'disconnected',
            ':now': new Date().toISOString(),
            ':oldConnId': oldConnectionId
          }
        }));

        console.log(`✅ Cleared connectionId for driver ${driverId} after removal`);
      }

    } catch (error) {
      if (error.name === 'ConditionalCheckFailedException') {
        console.log(`ℹ️ ConnectionId already changed - skipping update`);
      } else {
        console.error(`❌ Error processing record:`, error);
        // لا نرمي الخطأ لتجنب إيقاف معالجة باقي السجلات
      }
    }
  }

  console.log(`✅ Stream processing complete`);
  return { statusCode: 200, body: 'Success' };
};
