const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const TABLE_NAME = process.env.WIZZORDERS_TABLE;

/**
 * Lambda handler for searching orders by order number using GSI_OrderNumber
 */
exports.handler = async (event) => {
    console.log('Event received:', JSON.stringify(event, null, 2));
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    };
    
    try {
        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: headers,
                body: ''
            };
        }

        // Get order number from path parameters or query string
        const orderNumber = event.pathParameters?.orderNumber || 
                           event.queryStringParameters?.orderNumber ||
                           event.queryStringParameters?.order_number;
        
        if (!orderNumber) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order number is required',
                    success: false
                })
            };
        }

        console.log('Searching for order number:', orderNumber);

        // Query GSI_OrderNumber for the order
        const queryCommand = new QueryCommand({
            TableName: TABLE_NAME,
            IndexName: 'GSI_OrderNumber',
            KeyConditionExpression: 'orderNumber = :orderNumber',
            ExpressionAttributeValues: {
                ':orderNumber': orderNumber
            },
            Limit: 1 // Order numbers should be unique
        });

        const result = await dynamoDb.send(queryCommand);

        if (!result.Items || result.Items.length === 0) {
            return {
                statusCode: 404,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order not found',
                    orderNumber: orderNumber,
                    success: false
                })
            };
        }

        const order = result.Items[0];
        
        console.log('Order found successfully:', order.orderId);

        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                success: true,
                order: order,
                orderNumber: orderNumber
            })
        };

    } catch (error) {
        console.error('Error searching order by number:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                error: 'Failed to search order',
                message: error.message,
                success: false
            })
        };
    }
};
