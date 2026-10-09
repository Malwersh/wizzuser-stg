const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, ScanCommand, DeleteCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');
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

const WEBSOCKET_ENDPOINT = process.env.WEBSOCKET_ENDPOINT;
const WEBSOCKET_MANAGEMENT_ENDPOINT =
    process.env.WEBSOCKET_MANAGEMENT_ENDPOINT ||
    (WEBSOCKET_ENDPOINT ? WEBSOCKET_ENDPOINT.replace('wss://', 'https://') : undefined);

const apiGatewayManagementApi = new ApiGatewayManagementApiClient({
    endpoint: WEBSOCKET_MANAGEMENT_ENDPOINT || requireEnv('WEBSOCKET_MANAGEMENT_ENDPOINT')
});

// Table names - using correct environment variable name from template.yaml
const WEBSOCKET_CONNECTIONS_TABLE = requireEnv('CONNECTIONS_TABLE');
const BUSINESS_WORKING_HOURS_TABLE = process.env.WORKING_HOURS_TABLE || 'WhizzMerchants_BusinessWorkingHours';

/**
 * Lambda function to handle DynamoDB Streams from Business table
 * and broadcast business status updates via WebSocket
 */
exports.handler = async (event) => {
    console.log('🔄 Business Status Stream Handler - Event received:', JSON.stringify(event, null, 2));
    
    const promises = [];
    
    for (const record of event.Records) {
        console.log(`📋 Processing record: ${record.eventName}`);
        
        try {
            if (record.eventName === 'MODIFY') {
                const businessId = record.dynamodb.Keys?.businessId?.S;
                
                if (!businessId) {
                    console.log('⚠️ No businessId found in record');
                    continue;
                }
                
                // Get old and new values
                const oldImage = record.dynamodb.OldImage || {};
                const newImage = record.dynamodb.NewImage || {};
                
                const oldAcceptingOrders = oldImage.acceptingOrders?.BOOL;
                const newAcceptingOrders = newImage.acceptingOrders?.BOOL;
                const businessName = newImage.businessName?.S || newImage.name?.S || 'Unknown Business';
                
                console.log(`🏪 Business: ${businessName} (${businessId})`);
                console.log(`   Old acceptingOrders: ${oldAcceptingOrders}`);
                console.log(`   New acceptingOrders: ${newAcceptingOrders}`);
                
                // Check if acceptingOrders field changed
                if (oldAcceptingOrders !== newAcceptingOrders) {
                    console.log(`🚨 Business status changed! Broadcasting update...`);
                    
                    // Get current working hours for this business
                    const workingHours = await getBusinessWorkingHours(businessId);
                    const isCurrentlyOpen = isBusinessCurrentlyOpen(workingHours);
                    
                    const updatePromise = broadcastBusinessStatusUpdate({
                        businessId: businessId,
                        businessName: businessName,
                        acceptingOrders: newAcceptingOrders,
                        canAcceptOrders: newAcceptingOrders, // For compatibility
                        status: newAcceptingOrders ? 'available' : 'unavailable',
                        statusMessage: newAcceptingOrders ? 'متاح للطلبات' : 'غير متاح حالياً',
                        isBusy: !newAcceptingOrders,
                        isCurrentlyOpen: isCurrentlyOpen,
                        workingHours: workingHours,
                        timestamp: new Date().toISOString(),
                        eventType: 'business_status_update'
                    });
                    
                    promises.push(updatePromise);
                } else {
                    console.log(`ℹ️ acceptingOrders unchanged, skipping broadcast`);
                }
                
                // Check for other important changes
                const oldBusinessName = oldImage.businessName?.S || oldImage.name?.S;
                const newBusinessName = newImage.businessName?.S || newImage.name?.S;
                
                if (oldBusinessName !== newBusinessName) {
                    console.log(`📝 Business name changed: ${oldBusinessName} → ${newBusinessName}`);
                    
                    const nameUpdatePromise = broadcastBusinessStatusUpdate({
                        businessId: businessId,
                        businessName: newBusinessName,
                        acceptingOrders: newAcceptingOrders,
                        status: newAcceptingOrders ? 'available' : 'unavailable',
                        timestamp: new Date().toISOString(),
                        eventType: 'business_info_update'
                    });
                    
                    promises.push(nameUpdatePromise);
                }
            } else if (record.eventName === 'INSERT') {
                console.log(`✅ New business added: ${record.dynamodb.NewImage?.businessId?.S}`);
                // Could broadcast new business added event
            } else if (record.eventName === 'REMOVE') {
                console.log(`❌ Business removed: ${record.dynamodb.OldImage?.businessId?.S}`);
                // Could broadcast business removed event
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
            console.log(`✅ Successfully processed ${promises.length} updates`);
        } catch (error) {
            console.error('❌ Error in batch processing:', error);
        }
    } else {
        console.log('ℹ️ No updates to broadcast');
    }
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Stream processing completed',
            recordsProcessed: event.Records.length,
            updatesDispatched: promises.length
        })
    };
};

/**
 * Broadcast business status update to all connected WebSocket clients
 */
async function broadcastBusinessStatusUpdate(updateData) {
    console.log(`📡 Broadcasting update for business: ${updateData.businessId}`);
    
    try {
        // Get all active WebSocket connections
        const connections = await getActiveConnections();
        console.log(`👥 Found ${connections.length} active connections`);
        
        if (connections.length === 0) {
            console.log('ℹ️ No active connections to broadcast to');
            return;
        }
        
        const message = {
            type: 'business_status_update',
            data: updateData
        };
        
        const messageString = JSON.stringify(message);
        console.log(`📤 Broadcasting message:`, messageString);
        
        // Send to all connections
        const broadcastPromises = connections.map(async (connection) => {
            try {
                console.log(`🔗 Attempting to send to connection: ${connection.connectionId} (user: ${connection.userId}, type: ${connection.entityType})`);
                
                const command = new PostToConnectionCommand({
                    ConnectionId: connection.connectionId,
                    Data: messageString
                });
                await apiGatewayManagementApi.send(command);
                
                console.log(`✅ Sent to connection: ${connection.connectionId}`);
                return { connectionId: connection.connectionId, status: 'sent' };
                
            } catch (error) {
                console.log(`❌ Failed to send to ${connection.connectionId}:`, error.message);
                console.log(`🔍 Error details:`, JSON.stringify(error, null, 2));
                
                // Remove stale connections - most WebSocket errors indicate stale connections
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
        
        console.log(`📊 Broadcast results: ${successful} sent, ${failed} failed`);
        
    } catch (error) {
        console.error('❌ Error in broadcastBusinessStatusUpdate:', error);
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
        console.log(`📋 Found ${result.Items?.length || 0} non-expired connections`);
        
        // Log some sample connections for debugging
        if (result.Items && result.Items.length > 0) {
            console.log(`📝 Sample connection:`, JSON.stringify(result.Items[0], null, 2));
        }
        
        return result.Items || [];
        
    } catch (error) {
        console.error('❌ Error getting active connections:', error);
        console.error('Error details:', error);
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
 * Get full business working hours for status updates
 */
async function getBusinessWorkingHours(businessId) {
    try {
        console.log(`🕒 Getting working hours for business: ${businessId}`);
        
        const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        
        const results = await Promise.all(
            weekdays.map(async (day) => {
                try {
                    const result = await dynamodb.send(new GetCommand({
                        TableName: BUSINESS_WORKING_HOURS_TABLE,
                        Key: { businessId: businessId, weekday: day }
                    }));
                    return { day, data: result.Item };
                } catch (error) {
                    console.error(`❌ Error querying ${day}:`, error);
                    return { day, data: null };
                }
            })
        );
        
        const workingHours = {};
        results.forEach(({ day, data }) => {
            if (data) {
                workingHours[day] = {
                    opening: data.opening,
                    closing: data.closing,
                    isClosed: data.isClosed || (!data.opening && !data.closing),
                    updatedAt: data.updatedAt
                };
            } else {
                workingHours[day] = {
                    opening: null,
                    closing: null,
                    isClosed: true,
                    updatedAt: null
                };
            }
        });
        
        console.log(`📋 Retrieved working hours for ${businessId}:`, JSON.stringify(workingHours, null, 2));
        return workingHours;
        
    } catch (error) {
        console.error('❌ Error getting business working hours:', error);
        return null;
    }
}

/**
 * Check if business is currently open based on working hours
 */
function isBusinessCurrentlyOpen(workingHours) {
    if (!workingHours) return null;
    
    const now = new Date();
    const currentDay = now.toLocaleDateString('en-US', { weekday: 'long' });
    const currentTime = now.toLocaleTimeString('en-GB', { hour12: false, hour: '2-digit', minute: '2-digit' });
    
    const todayHours = workingHours[currentDay];
    
    if (!todayHours || todayHours.isClosed || !todayHours.opening || !todayHours.closing) {
        return false; // Closed today
    }
    
    // Compare current time with opening hours
    const openTime = todayHours.opening;
    const closeTime = todayHours.closing;
    
    if (currentTime >= openTime && currentTime <= closeTime) {
        return true; // Currently open
    }
    
    return false; // Outside business hours
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
