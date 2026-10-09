// WebSocket Broadcast System for Availability Updates
import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const WEBSOCKET_TABLE = requireEnv('WEBSOCKET_TABLE');
const WEBSOCKET_ENDPOINT = requireEnv('WEBSOCKET_ENDPOINT');

// Create API Gateway Management API client
const apiGatewayClient = new ApiGatewayManagementApiClient({
  endpoint: WEBSOCKET_ENDPOINT.replace('wss://', 'https://')
});

interface AvailabilityUpdate {
  businessId: string;
  storeName: string;
  status: 'OPEN' | 'CLOSED_HOURS' | 'CLOSED_OVERRIDE' | 'PAUSED_BY_MERCHANT' | 'BUSY_THROTTLED' | 'CLOSING_SOON' | 'DELIVERY_BLACKOUT' | 'CAPACITY_FULL';
  canOrderNow: boolean;
  allowDelivery: boolean;
  allowPickup: boolean;
  leadTimeMins: number;
  nextOpenAt?: string;
  reasonCodes: string[];
  timestamp: string;
}

interface BroadcastRequest {
  type: 'AVAILABILITY_UPDATE' | 'BUSINESS_STATUS_CHANGE' | 'WORKING_HOURS_UPDATE';
  businessId?: string;
  data: AvailabilityUpdate | any;
  targetConnections?: string[]; // Optional specific connections to target
}

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  console.log('WebSocket broadcast request:', JSON.stringify(event, null, 2));

  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*'
  };

  try {
    const { body } = event;
    
    if (!body) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'Request body is required' })
      };
    }

    const request: BroadcastRequest = JSON.parse(body);
    const result = await broadcastUpdate(request);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        messagesSent: result.successful,
        messagesFailed: result.failed,
        connectionsCleanedUp: result.cleanedUp
      })
    };

  } catch (error) {
    console.error('Broadcast error:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        error: 'Broadcast failed',
        details: error instanceof Error ? error.message : 'Unknown error'
      })
    };
  }
};

async function broadcastUpdate(request: BroadcastRequest): Promise<{
  successful: number;
  failed: number;
  cleanedUp: number;
}> {
  try {
    // Get active WebSocket connections
    const connections = await getActiveConnections(request.targetConnections);
    
    if (connections.length === 0) {
      console.log('No active connections to broadcast to');
      return { successful: 0, failed: 0, cleanedUp: 0 };
    }

    // Prepare the message
    const message = {
      type: request.type,
      businessId: request.businessId,
      data: request.data,
      timestamp: new Date().toISOString()
    };

    const messageText = JSON.stringify(message);
    console.log(`Broadcasting to ${connections.length} connections:`, messageText);

    // Send messages to all connections
    const results = await Promise.allSettled(
      connections.map(connection => sendMessageToConnection(connection.connectionId, messageText))
    );

    // Count results and clean up stale connections
    let successful = 0;
    let failed = 0;
    let cleanedUp = 0;
    const staleConnections: string[] = [];

    results.forEach((result, index) => {
      if (result.status === 'fulfilled') {
        successful++;
      } else {
        failed++;
        const connectionId = connections[index].connectionId;
        
        // Check if it's a stale connection error
        if (result.reason?.name === 'GoneException' || 
            result.reason?.message?.includes('410') ||
            result.reason?.message?.includes('Connection')) {
          staleConnections.push(connectionId);
        }
      }
    });

    // Clean up stale connections
    if (staleConnections.length > 0) {
      cleanedUp = await cleanupStaleConnections(staleConnections);
    }

    console.log(`Broadcast complete: ${successful} successful, ${failed} failed, ${cleanedUp} cleaned up`);
    return { successful, failed, cleanedUp };

  } catch (error) {
    console.error('Error in broadcastUpdate:', error);
    throw error;
  }
}

async function getActiveConnections(targetConnections?: string[]): Promise<any[]> {
  try {
    if (targetConnections && targetConnections.length > 0) {
      // Return specific connections if provided
      return targetConnections.map(connectionId => ({ connectionId }));
    }

    // Get all active connections
    const command = new ScanCommand({
      TableName: WEBSOCKET_TABLE,
      FilterExpression: 'attribute_exists(connectionId)'
    });

    const result = await docClient.send(command);
    return result.Items || [];

  } catch (error) {
    console.error('Error getting active connections:', error);
    return [];
  }
}

async function sendMessageToConnection(connectionId: string, message: string): Promise<void> {
  try {
    const command = new PostToConnectionCommand({
      ConnectionId: connectionId,
      Data: Buffer.from(message)
    });

    await apiGatewayClient.send(command);
    console.log(`Message sent to connection ${connectionId}`);

  } catch (error) {
    console.error(`Failed to send message to connection ${connectionId}:`, error);
    throw error;
  }
}

async function cleanupStaleConnections(connectionIds: string[]): Promise<number> {
  let cleanedUp = 0;

  try {
    const deletePromises = connectionIds.map(async (connectionId) => {
      try {
        const command = new DeleteCommand({
          TableName: WEBSOCKET_TABLE,
          Key: { connectionId }
        });

        await docClient.send(command);
        cleanedUp++;
        console.log(`Cleaned up stale connection: ${connectionId}`);
      } catch (error) {
        console.error(`Failed to cleanup connection ${connectionId}:`, error);
      }
    });

    await Promise.all(deletePromises);

  } catch (error) {
    console.error('Error during cleanup:', error);
  }

  return cleanedUp;
}

// Helper function to broadcast availability updates (can be called by other functions)
export const broadcastAvailabilityUpdate = async (update: AvailabilityUpdate): Promise<void> => {
  const request: BroadcastRequest = {
    type: 'AVAILABILITY_UPDATE',
    businessId: update.businessId,
    data: update
  };

  await broadcastUpdate(request);
};

// Helper function to broadcast business status changes
export const broadcastBusinessStatusChange = async (businessId: string, statusData: any): Promise<void> => {
  const request: BroadcastRequest = {
    type: 'BUSINESS_STATUS_CHANGE',
    businessId,
    data: statusData
  };

  await broadcastUpdate(request);
};

// Helper function to broadcast working hours updates
export const broadcastWorkingHoursUpdate = async (businessId: string, workingHoursData: any): Promise<void> => {
  const request: BroadcastRequest = {
    type: 'WORKING_HOURS_UPDATE',
    businessId,
    data: workingHoursData
  };

  await broadcastUpdate(request);
};

// Main trigger function that integrates with store availability engine
export const triggerAvailabilityUpdate = async (params: {
  storeId: string;
  storeName: string;
  previousStatus: string;
  newStatus: string;
  trigger: 'MERCHANT_ACTION' | 'WORKING_HOURS' | 'CAPACITY_CHANGE' | 'SYSTEM_UPDATE';
  forceUpdate?: boolean;
}): Promise<{ connectionsNotified: number }> => {
  console.log('🚀 Triggering availability update:', params);

  try {
    // Import and call the store availability engine
    const storeAvailabilityEngine = await import('../store-availability');
    
    // Get current availability status
    const mockEvent = {
      pathParameters: { businessId: params.storeId },
      queryStringParameters: { forceRefresh: 'true' }
    };
    const availabilityResult = await storeAvailabilityEngine.handler(mockEvent as any);

    let availabilityData;
    if (availabilityResult.statusCode === 200) {
      availabilityData = JSON.parse(availabilityResult.body);
    } else {
      // Fallback if availability engine fails
      console.warn('Availability engine failed, using fallback data');
      availabilityData = {
        businessId: params.storeId,
        storeName: params.storeName,
        status: 'UNKNOWN',
        canOrderNow: false,
        allowDelivery: false,
        allowPickup: false,
        leadTimeMins: 0,
        reasonCodes: ['SYSTEM_ERROR'],
        timestamp: new Date().toISOString()
      };
    }

    // Create the availability update
    const update: AvailabilityUpdate = {
      businessId: params.storeId,
      storeName: params.storeName,
      status: availabilityData.status || 'UNKNOWN',
      canOrderNow: availabilityData.canOrderNow || false,
      allowDelivery: availabilityData.allowDelivery || false,
      allowPickup: availabilityData.allowPickup || false,
      leadTimeMins: availabilityData.leadTimeMins || 0,
      nextOpenAt: availabilityData.nextOpenAt,
      reasonCodes: availabilityData.reasonCodes || [],
      timestamp: new Date().toISOString()
    };

    // Broadcast the update
    await broadcastAvailabilityUpdate(update);

    // Get active connections count for response
    const connections = await getActiveConnections();
    const connectionsNotified = connections.length;

    console.log(`✅ Availability update broadcasted to ${connectionsNotified} connections`);

    return { connectionsNotified };

  } catch (error) {
    console.error('❌ Error triggering availability update:', error);
    throw error;
  }
};
