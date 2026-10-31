/**
 * Universal WebSocket Heartbeat Handler
 * Processes heartbeat messages from all app types: Customer, Business, and Driver
 * Updates connection status and tracks last activity (schema-aware)
 */

const { UniversalWebSocketManager } = require('../../universal_websocket_manager');

// Initialize Universal WebSocket Manager
const universalManager = new UniversalWebSocketManager();

/**
 * Handle heartbeat message from client
 * Updates lastHeartbeat, connectionStatus, and lastActivity
 */
const handler = async (event) => {
    try {
        const connectionId = event.requestContext.connectionId;
        const now = Date.now();

        console.log(`💓 Heartbeat received from connection: ${connectionId}`);

        // Update connection record with heartbeat timestamp (schema-aware)
        const result = await universalManager.updateHeartbeat(connectionId);

        console.log(`✅ Heartbeat processed successfully for ${connectionId}`);
        console.log(`   Manager result: ${JSON.stringify(result)}`);

        // Send heartbeat acknowledgment back to client
        return {
            statusCode: 200,
            body: JSON.stringify({
                type: 'heartbeat_ack',
                timestamp: now,
                connectionId: connectionId,
                status: 'active'
            })
        };

    } catch (error) {
        console.error('❌ Error processing heartbeat:', error);
        
        // Don't fail the connection on heartbeat errors
        // Just log and return success to keep connection alive
        return {
            statusCode: 200,
            body: JSON.stringify({
                type: 'heartbeat_error',
                message: 'Heartbeat processing failed but connection maintained'
            })
        };
    }
};

module.exports = {handler:require('../../realtime-identity-scope-346').guardDefault(require('../../merchant-realtime-scope-345').guardDefault(handler))};
