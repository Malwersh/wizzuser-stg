const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { normalizeDiscount } = require('../shared/discount-engine');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const DISCOUNTS_TABLE = process.env.DISCOUNTS_TABLE || 'WhizzMerchants_Discounts';

/**
 * List currently usable discounts for a store.
 * Route: GET /business/{businessId}/discounts
 */
exports.handler = async (event) => {
    console.log('Event received:', JSON.stringify(event, null, 2));

    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    };

    const respond = (statusCode, body) => ({
        statusCode,
        headers,
        body: JSON.stringify(body)
    });

    try {
        if (event.httpMethod === 'OPTIONS') {
            return respond(200, '');
        }

        const businessId = event.pathParameters && event.pathParameters.businessId;
        if (!businessId) {
            return respond(400, {
                success: false,
                message: 'Missing required path parameter: businessId'
            });
        }

        const result = await dynamoDb.send(new QueryCommand({
            TableName: DISCOUNTS_TABLE,
            IndexName: 'BusinessIdIndex',
            KeyConditionExpression: 'businessId = :businessId',
            ExpressionAttributeValues: {
                ':businessId': businessId
            }
        }));

        const now = new Date();
        const discounts = (result.Items || [])
            .map(normalizeDiscount)
            .filter(d => {
                if (d.status !== 'active') return false;
                if (d.validFrom && now < new Date(d.validFrom)) return false;
                if (d.validTo && now > new Date(d.validTo)) return false;
                if (d.usageLimit && (d.usageCount || 0) >= d.usageLimit) return false;
                return true;
            });

        return respond(200, {
            success: true,
            discounts,
            count: discounts.length
        });

    } catch (error) {
        console.error('Error getting store discounts:', error);

        return respond(500, {
            success: false,
            message: 'Failed to retrieve store discounts',
            error: error.message
        });
    }
};
