/**
 * Enhanced Customer WebSocket Disconnect Handler
 * Updated to use Universal WebSocket Manager for consistent connection management
 */

const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient } = require("@aws-sdk/lib-dynamodb");
const { UniversalWebSocketManager } = require('../../universal_websocket_manager');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

// Initialize Universal WebSocket Manager
const universalManager = new UniversalWebSocketManager();

/**
 * WebSocket Disconnect Handler for Customer App
 * Updates connection status to disconnected instead of deleting
 */
const handler = async (event) => {
    try {
        const connectionId = event.requestContext.connectionId;
        console.log(`🔌 Customer WebSocket disconnection request: ${connectionId}`);

        // Use universal manager for customer disconnection
        const result = await universalManager.handleDisconnect(connectionId);
        
        console.log(`✅ Customer disconnection handled by universal manager: ${connectionId}`);
        return result;
        
    } catch (error) {
        console.error('❌ Error in customer WebSocket disconnect:', error);
        return { 
            statusCode: 500, 
            body: JSON.stringify({
                error: 'Failed to disconnect',
                message: error.message
            })
        };
    }
};

module.exports = { handler };
