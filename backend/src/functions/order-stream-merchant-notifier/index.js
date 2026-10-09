const AWS = require('aws-sdk');
const https = require('https');
const url = require('url');

const dynamodb = new AWS.DynamoDB.DocumentClient();

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

// Merchant WebSocket endpoint
const MERCHANT_WEBSOCKET_ENDPOINT = requireEnv('MERCHANT_WEBSOCKET_MANAGEMENT_ENDPOINT');
const MERCHANT_ENDPOINTS_TABLE = requireEnv('MERCHANT_ENDPOINTS_TABLE');

/**
 * Lambda function triggered by DynamoDB Stream on WizzOrders-Table-Dev
 * Sends WebSocket notifications to merchant app when orders are updated
 */
exports.handler = async (event) => {
    console.log('📥 WizzOrders Stream Event:', JSON.stringify(event, null, 2));
    
    const promises = event.Records.map(async (record) => {
        try {
            await processStreamRecord(record);
        } catch (error) {
            console.error('❌ Error processing stream record:', error);
            // Don't throw - process other records
        }
    });
    
    await Promise.all(promises);
    
    return {
        statusCode: 200,
        body: JSON.stringify({ message: 'Stream processed successfully' })
    };
};

async function processStreamRecord(record) {
    const eventName = record.eventName;
    console.log(`📝 Processing ${eventName} event`);
    
    // Only process MODIFY events (status changes)
    if (eventName !== 'MODIFY') {
        console.log('⏭️  Skipping non-MODIFY event');
        return;
    }
    
    const oldImage = AWS.DynamoDB.Converter.unmarshall(record.dynamodb.OldImage);
    const newImage = AWS.DynamoDB.Converter.unmarshall(record.dynamodb.NewImage);
    
    // Check if status changed
    if (oldImage.status === newImage.status) {
        console.log('⏭️  Status unchanged, skipping');
        return;
    }
    
    console.log(`🔄 Order status changed: ${oldImage.status} → ${newImage.status}`);
    console.log(`📦 Order ID: ${newImage.orderId}`);
    console.log(`🏪 Store ID: ${newImage.storeId}`);
    
    // Send WebSocket notification to merchant
    await sendMerchantNotification(newImage);
}

async function sendMerchantNotification(order) {
    try {
        console.log(`🔍 Looking for merchant connections for store: ${order.storeId}`);
        
        // Query merchant WebSocket connections
        const connections = await dynamodb.query({
            TableName: MERCHANT_ENDPOINTS_TABLE,
            KeyConditionExpression: 'merchantId = :merchantId AND endpointType = :endpointType',
            FilterExpression: 'isActive = :isActive',
            ExpressionAttributeValues: {
                ':merchantId': order.storeId,
                ':endpointType': 'websocket',
                ':isActive': true
            }
        }).promise();
        
        if (!connections.Items || connections.Items.length === 0) {
            console.log(`⚠️  No active WebSocket connections found for merchant: ${order.storeId}`);
            return;
        }
        
        console.log(`✅ Found ${connections.Items.length} active connection(s)`);
        
        // Prepare notification message
        const notification = {
            type: 'ORDER_STATUS_UPDATE',
            orderId: order.orderId,
            status: order.status,
            cancelReason: order.cancelReason || order.canceledBy,
            data: {
                orderId: order.orderId,
                status: order.status,
                storeId: order.storeId,
                customerId: order.customerId,
                customerName: order.customerName,
                totalAmount: order.totalAmount,
                canceledAt: order.canceledAt,
                canceledBy: order.canceledBy,
                cancelReason: order.cancelReason,
                updatedAt: order.updatedAt
            },
            timestamp: new Date().toISOString()
        };
        
        // Send to all active connections
        const sendPromises = connections.Items.map(connection => 
            sendToConnection(connection.connectionId, notification)
        );
        
        const results = await Promise.allSettled(sendPromises);
        
        const successful = results.filter(r => r.status === 'fulfilled').length;
        const failed = results.filter(r => r.status === 'rejected').length;
        
        console.log(`📊 Notification results: ${successful} succeeded, ${failed} failed`);
        
    } catch (error) {
        console.error('❌ Error sending merchant notification:', error);
        throw error;
    }
}

async function sendToConnection(connectionId, message) {
    const endpoint = url.parse(MERCHANT_WEBSOCKET_ENDPOINT);
    const postData = JSON.stringify(message);
    
    const options = {
        hostname: endpoint.hostname,
        port: 443,
        path: `${endpoint.path}/@connections/${connectionId}`,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData)
        }
    };
    
    return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
            let data = '';
            
            res.on('data', chunk => {
                data += chunk;
            });
            
            res.on('end', () => {
                if (res.statusCode === 200 || res.statusCode === 204) {
                    console.log(`✅ Sent to connection: ${connectionId}`);
                    resolve();
                } else if (res.statusCode === 410) {
                    console.log(`🗑️  Stale connection removed: ${connectionId}`);
                    // TODO: Remove stale connection from table
                    resolve();
                } else {
                    console.error(`❌ Failed to send to ${connectionId}: ${res.statusCode}`);
                    reject(new Error(`HTTP ${res.statusCode}: ${data}`));
                }
            });
        });
        
        req.on('error', (error) => {
            console.error(`❌ Request error for ${connectionId}:`, error);
            reject(error);
        });
        
        req.write(postData);
        req.end();
    });
}
