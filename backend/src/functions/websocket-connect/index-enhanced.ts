import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

// Use WEBSOCKET_CONNECTIONS_TABLE first (unified ecosystem), fallback to WEBSOCKET_TABLE
const CONNECTIONS_TABLE = process.env.WEBSOCKET_CONNECTIONS_TABLE || process.env.WEBSOCKET_TABLE;

if (!CONNECTIONS_TABLE) {
  throw new Error('Missing required environment variable: WEBSOCKET_CONNECTIONS_TABLE or WEBSOCKET_TABLE');
}

// WebSocket event interface
interface WebSocketEvent {
  requestContext: {
    connectionId: string;
    routeKey: string;
    messageId?: string;
    apiId: string;
  };
  queryStringParameters?: {
    [key: string]: string;
  } | null;
  isBase64Encoded: boolean;
}

interface ConnectionData {
  PK: string;
  SK: string;
  connectionId: string;
  userId: string | null;
  orderId?: string | null;
  businessId?: string | null;
  entityType: string;
  userType?: string | null;
  connectedAt: string;
  ttl: number;
  GSI1PK?: string;
  GSI1SK?: string;
}

export const handler = async (event: WebSocketEvent): Promise<APIGatewayProxyResult> => {
  console.log('🔌 Enhanced WebSocket Connect Event:', JSON.stringify(event, null, 2));
  
  try {
    const connectionId = event.requestContext.connectionId;
    const queryParams = event.queryStringParameters || {};
    const { userId, orderId, businessId, entityType, userType } = queryParams;
    
    console.log(`🔌 WebSocket connection: ${connectionId}`);
    console.log(`📋 Connection params:`, { userId, orderId, businessId, entityType, userType });

    // Store connection information
    const now = new Date().toISOString();
    const connectionData: ConnectionData = {
      PK: `CONNECTION#${connectionId}`,
      SK: `CONNECTION#${connectionId}`,
      connectionId: connectionId,
      userId: userId || null,
      orderId: orderId || null,
      businessId: businessId || null,
      connectedAt: now,
      entityType: entityType || 'user',
      userType: userType || null,
      // TTL for automatic cleanup (24 hours)
      ttl: Math.floor(Date.now() / 1000) + 86400
    };

    // If user is tracking a specific order, also create order subscription
    if (orderId) {
      connectionData.GSI1PK = `ORDER#${orderId}`;
      connectionData.GSI1SK = `CONNECTION#${connectionId}`;
      console.log(`📦 Added order subscription for: ${orderId}`);
    }

    // If this is a merchant connection, add business subscription
    if (businessId && (entityType === 'merchant' || userType === 'merchant')) {
      // Add GSI2 for business-based queries (we'll need to add this index to DynamoDB)
      connectionData.GSI1PK = connectionData.GSI1PK || `BUSINESS#${businessId}`;
      connectionData.GSI1SK = connectionData.GSI1SK || `CONNECTION#${connectionId}`;
      console.log(`🏪 Added merchant subscription for business: ${businessId}`);
    }

    const putCommand = new PutCommand({
      TableName: CONNECTIONS_TABLE,
      Item: connectionData
    });

    await docClient.send(putCommand);

    console.log(`✅ WebSocket connection stored: ${connectionId}`);
    console.log(`🔗 Connection type: ${entityType || 'user'}${businessId ? ' (Business: ' + businessId + ')' : ''}`);

    return {
      statusCode: 200,
      body: 'Connected'
    };

  } catch (error) {
    console.error('❌ Error handling WebSocket connection:', error);
    
    return {
      statusCode: 500,
      body: 'Failed to connect'
    };
  }
};
