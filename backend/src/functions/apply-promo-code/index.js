const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const TABLE_NAME = process.env.WIZZORDERS_TABLE;

/**
 * Lambda handler for applying promo codes to orders
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

        // Parse request body
        let body;
        if (typeof event.body === 'string') {
            body = JSON.parse(event.body);
        } else {
            body = event.body;
        }

        const { orderId, promoCode } = body;
        
        if (!orderId || !promoCode) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order ID and promo code are required',
                    success: false
                })
            };
        }

        console.log('Applying promo code:', promoCode, 'to order:', orderId);

        // For now, return a simple response since promo functionality is temporarily disabled
        // In the future, this would validate promo codes and calculate discounts
        
        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                success: true,
                message: 'Promo code functionality is temporarily disabled',
                discount: 0,
                validPromo: false
            })
        };

    } catch (error) {
        console.error('Error applying promo code:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                error: 'Failed to apply promo code',
                message: error.message,
                success: false
            })
        };
    }
};
