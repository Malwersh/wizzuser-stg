const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, ScanCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

// Configure AWS clients
const dynamoClient = new DynamoDBClient({ region: 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(dynamoClient);
const apiGatewayManagementApi = new ApiGatewayManagementApiClient({
    endpoint: process.env.WEBSOCKET_ENDPOINT
});

// Table names
const WEBSOCKET_CONNECTIONS_TABLE = requireEnv('CONNECTIONS_TABLE');

/**
 * Lambda function to handle DynamoDB Streams from Business Working Hours table
 * and broadcast working hours updates via WebSocket
 */
exports.handler = async (event) => {
    console.log('🕒 Working Hours Stream Handler - Event received:', JSON.stringify(event, null, 2));
    
    const promises = [];
    
    for (const record of event.Records) {
        console.log(`📋 Processing record: ${record.eventName}`);
        
        try {
            if (record.eventName === 'MODIFY' || record.eventName === 'INSERT') {
                const businessId = record.dynamodb.Keys?.businessId?.S;
                const weekday = record.dynamodb.Keys?.weekday?.S;
                
                if (!businessId || !weekday) {
                    console.log('⚠️ No businessId or weekday found in record');
                    continue;
                }
                
                // Get old and new values
                const oldImage = record.dynamodb.OldImage || {};
                const newImage = record.dynamodb.NewImage || {};
                
                const oldOpening = oldImage.opening?.S;
                const newOpening = newImage.opening?.S;
                const oldClosing = oldImage.closing?.S;
                const newClosing = newImage.closing?.S;
                const oldIsClosed = oldImage.isClosed?.BOOL;
                const newIsClosed = newImage.isClosed?.BOOL;
                
                console.log(`🏪 Business: ${businessId}, Day: ${weekday}`);
                console.log(`   Old hours: ${oldOpening || 'null'} - ${oldClosing || 'null'} (closed: ${oldIsClosed})`);
                console.log(`   New hours: ${newOpening || 'null'} - ${newClosing || 'null'} (closed: ${newIsClosed})`);
                
                // Check if working hours changed (including closed status)
                const hoursChanged = (oldOpening !== newOpening) || (oldClosing !== newClosing) || (oldIsClosed !== newIsClosed);
                
                if (hoursChanged) {
                    console.log(`🚨 Working hours changed for ${weekday}! Broadcasting update...`);
                    
                    // 🔥 أولوية عالية لـ isClosed - يأخذ الأولوية على أي ساعات محددة
                    const isDayClosed = newIsClosed === true || (!newOpening && !newClosing) || newOpening === 'none' || newClosing === 'none';
                    const wasDayOpen = oldIsClosed === false && oldOpening && oldClosing && oldOpening !== 'none' && oldClosing !== 'none';
                    
                    let eventType = 'working_hours_update';
                    let statusMessage = '';
                    
                    if (isDayClosed && wasDayOpen) {
                        eventType = 'day_closed';
                        statusMessage = `مغلق يوم ${getArabicDayName(weekday)}`;
                    } else if (!isDayClosed && !wasDayOpen) {
                        eventType = 'day_opened';
                        statusMessage = `مفتوح يوم ${getArabicDayName(weekday)} من ${newOpening} إلى ${newClosing}`;
                    } else {
                        statusMessage = `تم تحديث ساعات العمل ليوم ${getArabicDayName(weekday)}`;
                    }
                    
                    const updatePromise = broadcastWorkingHoursUpdate({
                        businessId: businessId,
                        weekday: weekday,
                        weekdayArabic: getArabicDayName(weekday),
                        opening: newOpening,
                        closing: newClosing,
                        isClosed: newIsClosed || false,
                        isDayClosed: isDayClosed,
                        statusMessage: statusMessage,
                        timestamp: new Date().toISOString(),
                        eventType: eventType,
                        // Include all current working hours for this business
                        updatedDay: {
                            weekday: weekday,
                            opening: newOpening,
                            closing: newClosing,
                            isClosed: newIsClosed || false,
                            isDayClosed: isDayClosed
                        }
                    });
                    
                    promises.push(updatePromise);
                } else {
                    console.log(`ℹ️ Working hours unchanged for ${weekday}, skipping broadcast`);
                }
                
            } else if (record.eventName === 'REMOVE') {
                const businessId = record.dynamodb.OldImage?.businessId?.S;
                const weekday = record.dynamodb.OldImage?.weekday?.S;
                console.log(`❌ Working hours removed for ${businessId} on ${weekday}`);
                
                // Could broadcast day removal event
                const removePromise = broadcastWorkingHoursUpdate({
                    businessId: businessId,
                    weekday: weekday,
                    weekdayArabic: getArabicDayName(weekday),
                    opening: null,
                    closing: null,
                    isClosed: true,
                    isDayClosed: true,
                    statusMessage: `تم حذف ساعات العمل ليوم ${getArabicDayName(weekday)}`,
                    timestamp: new Date().toISOString(),
                    eventType: 'day_removed'
                });
                
                promises.push(removePromise);
            }
            
        } catch (error) {
            console.error(`❌ Error processing record:`, error);
            // Continue processing other records even if one fails
        }
    }
    
    // Wait for all broadcasts to complete
    if (promises.length > 0) {
        try {
            await Promise.all(promises);
            console.log(`✅ Successfully processed ${promises.length} working hours updates`);
        } catch (error) {
            console.error('❌ Error in batch processing:', error);
        }
    } else {
        console.log('ℹ️ No working hours updates to broadcast');
    }
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Working hours stream processing completed',
            recordsProcessed: event.Records.length,
            updatesDispatched: promises.length
        })
    };
};

/**
 * Broadcast working hours update to all connected WebSocket clients
 */
async function broadcastWorkingHoursUpdate(updateData) {
    console.log(`📡 Broadcasting working hours update for business: ${updateData.businessId}`);
    
    try {
        // Get all active WebSocket connections
        const connections = await getActiveConnections();
        console.log(`👥 Found ${connections.length} active connections`);
        
        if (connections.length === 0) {
            console.log('ℹ️ No active connections to broadcast to');
            return;
        }
        
        const message = {
            type: 'working_hours_update',
            data: updateData
        };
        
        const messageString = JSON.stringify(message);
        console.log(`📤 Broadcasting working hours message:`, messageString);
        
        // Send to all connections
        const broadcastPromises = connections.map(async (connection) => {
            try {
                console.log(`🔗 Attempting to send to connection: ${connection.connectionId} (user: ${connection.userId}, type: ${connection.entityType})`);
                
                const command = new PostToConnectionCommand({
                    ConnectionId: connection.connectionId,
                    Data: messageString
                });
                await apiGatewayManagementApi.send(command);
                
                console.log(`✅ Sent working hours update to connection: ${connection.connectionId}`);
                return { connectionId: connection.connectionId, status: 'sent' };
                
            } catch (error) {
                console.log(`❌ Failed to send to ${connection.connectionId}:`, error.message);
                console.log(`🔍 Error details:`, JSON.stringify(error, null, 2));
                
                // Remove stale connections
                if (error.statusCode === 410 || error.statusCode === 403 || 
                    error.name === 'GoneException' || error.name === 'UnknownError' ||
                    error.message.includes('Invalid connectionId')) {
                    console.log(`🗑️ Removing stale connection: ${connection.connectionId}`);
                    await removeStaleConnection(connection.connectionId);
                }
                
                return { connectionId: connection.connectionId, status: 'failed', error: error.message };
            }
        });
        
        const results = await Promise.all(broadcastPromises);
        const successful = results.filter(r => r.status === 'sent').length;
        const failed = results.filter(r => r.status === 'failed').length;
        
        console.log(`📊 Working hours broadcast results: ${successful} sent, ${failed} failed`);
        
    } catch (error) {
        console.error('❌ Error in broadcastWorkingHoursUpdate:', error);
        throw error;
    }
}

/**
 * Get all active WebSocket connections
 */
async function getActiveConnections() {
    try {
        const currentTime = Math.floor(Date.now() / 1000); // Current time in seconds
        console.log(`🕐 Current time: ${currentTime}, checking for active connections...`);
        
        const command = new ScanCommand({
            TableName: WEBSOCKET_CONNECTIONS_TABLE,
            FilterExpression: 'attribute_exists(connectionId) AND (#ttl > :currentTime OR attribute_not_exists(#ttl))',
            ExpressionAttributeNames: {
                '#ttl': 'ttl'
            },
            ExpressionAttributeValues: {
                ':currentTime': currentTime
            },
            ProjectionExpression: 'connectionId, userId, deviceId, connectedAt, entityType, platform'
        });
        
        const result = await dynamodb.send(command);
        console.log(`📋 Found ${result.Items?.length || 0} non-expired connections for working hours updates`);
        
        return result.Items || [];
        
    } catch (error) {
        console.error('❌ Error getting active connections:', error);
        return [];
    }
}

/**
 * Remove stale connection from database
 */
async function removeStaleConnection(connectionId) {
    try {
        const command = new DeleteCommand({
            TableName: WEBSOCKET_CONNECTIONS_TABLE,
            Key: { connectionId: connectionId }
        });
        await dynamodb.send(command);
        
        console.log(`🗑️ Removed stale connection: ${connectionId}`);
        
    } catch (error) {
        console.error(`❌ Error removing stale connection ${connectionId}:`, error);
    }
}

/**
 * Convert English day names to Arabic
 */
function getArabicDayName(englishDay) {
    const dayMap = {
        'Monday': 'الاثنين',
        'Tuesday': 'الثلاثاء', 
        'Wednesday': 'الأربعاء',
        'Thursday': 'الخميس',
        'Friday': 'الجمعة',
        'Saturday': 'السبت',
        'Sunday': 'الأحد'
    };
    
    return dayMap[englishDay] || englishDay;
}
