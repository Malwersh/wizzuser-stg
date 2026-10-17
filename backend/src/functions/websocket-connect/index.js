/**
 * Universal WebSocket Connection Handler
 * Handles connections from all app types: Customer, Business, and Driver
 * Uses intelligent connection type detection and Universal WebSocket Manager
 */

const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient } = require("@aws-sdk/lib-dynamodb");
const { UniversalWebSocketManager } = require('../../universal_websocket_manager');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

// Initialize Universal WebSocket Manager
const universalManager = new UniversalWebSocketManager();

function isInvalidId(value) {
    if (value === undefined || value === null) return true;
    const s = String(value).trim().toLowerCase();
    return s === '' || s === 'unknown' || s === 'null' || s === 'undefined' || s === 'none';
}

/**
 * Universal WebSocket Connect Handler
 * Handles connection establishment for Customer, Business, and Driver apps
 * Uses intelligent type detection and complete information storage
 */
const handler = async (event) => {
    try {
        const connectionId = event.requestContext.connectionId;
        const queryParams = event.queryStringParameters || {};
        const headers = event.headers || {};

        // Allow token via Authorization header as fallback (some clients may not send query params)
        if (!queryParams.token) {
            const authHeader = headers.Authorization || headers.authorization;
            if (authHeader && typeof authHeader === 'string') {
                const trimmed = authHeader.trim();
                if (trimmed.toLowerCase().startsWith('bearer ')) {
                    queryParams.token = trimmed.slice('bearer '.length).trim();
                }
            }
        }

        console.log(`🔌 Universal WebSocket connection request: ${connectionId}`);
        console.log('Connection type requested', {userType:queryParams.userType,entityType:queryParams.entityType});

        // Enhanced connection detection - determine entity type intelligently
        let detectedEntityType = 'customer'; // default
        let detectedUserType = 'customer'; // default
        
        // 1. Check for explicit guest connection
        if (queryParams.userType === 'guest' || queryParams.entityType === 'guest') {
            detectedEntityType = 'guest';
            detectedUserType = 'guest';
        }
        // 2. Check explicit entityType and userType parameters
        else if (queryParams.entityType) {
            detectedEntityType = queryParams.entityType;
        } else if (queryParams.userType) {
            if (queryParams.userType === 'business' || queryParams.userType === 'merchant') {
                detectedEntityType = 'business';
            } else if (queryParams.userType === 'driver') {
                detectedEntityType = 'driver';
            } else {
                detectedEntityType = 'customer';
            }
        }
        // 3. If no explicit type, detect from other parameters
        else if (queryParams.businessId || queryParams.merchantId) {
            detectedEntityType = 'business';
            detectedUserType = 'business';
        } else if (queryParams.driverId && !isInvalidId(queryParams.driverId)) {
            detectedEntityType = 'driver';
            detectedUserType = 'driver';
        }
        // 4. If no token and no userId, treat as guest
        else if (!queryParams.token && !queryParams.userId) {
            detectedEntityType = 'guest';
            detectedUserType = 'guest';
        }
        
        // Set userType to match entityType if not explicitly provided
        if (queryParams.userType) {
            detectedUserType = queryParams.userType;
        } else {
            detectedUserType = detectedEntityType;
        }

        console.log(`🔍 Connection type detection:`, {
            original: { entityType: queryParams.entityType, userType: queryParams.userType },
            detected: { entityType: detectedEntityType, userType: detectedUserType },
            indicators: { 
                businessId: !!queryParams.businessId, 
                merchantId: !!queryParams.merchantId,
                driverId: !!queryParams.driverId,
                userId: !!queryParams.userId
            }
        });

        // Enhance query parameters with intelligent detection
        const enhancedEvent = {
            ...event,
            queryStringParameters: {
                ...queryParams,
                // Use detected entity and user types
                entityType: detectedEntityType,
                userType: detectedUserType,
                // For business connections, don't pass userId to prevent guest user creation
                userId: detectedEntityType === 'business' ? null : (queryParams.userId || null),
                orderId: queryParams.orderId || null,
                businessId: queryParams.businessId || null,
                merchantId: queryParams.merchantId || null,
                driverId: (!isInvalidId(queryParams.driverId) ? queryParams.driverId : null),
                deviceId: queryParams.deviceId || null,
                platform: queryParams.platform || null,
                appVersion: queryParams.appVersion || null,
                token: queryParams.token || null
            }
        };

        // Use universal manager for all connection types
        const result = await universalManager.handleConnect(connectionId, enhancedEvent);
        
        console.log(`✅ ${detectedEntityType} connection handled by universal manager: ${connectionId}`);
        
        // Add specific connection type logging
        if (result.statusCode === 200) {
            console.log(`🎯 ${detectedEntityType.toUpperCase()} connection successful:`, {
                connectionId: connectionId,
                userId: queryParams.userId,
                entityType: detectedEntityType,
                userType: detectedUserType,
                businessId: queryParams.businessId,
                merchantId: queryParams.merchantId,
                driverId: queryParams.driverId,
                orderId: queryParams.orderId,
                platform: queryParams.platform
            });
        }
        
        return result;
        
    } catch (error) {
        console.error('❌ Error in WebSocket connect:', error);
        return { 
            statusCode: 500, 
            body: JSON.stringify({
                error: 'Failed to connect',
                message: error.message
            })
        };
    }
};

module.exports = { handler };
