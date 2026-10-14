const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const { normalizePlatformPromo } = require('../shared/discount-engine');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const PLATFORM_DISCOUNTS_TABLE = process.env.PLATFORM_DISCOUNTS_TABLE || 'WizzCentral_Platform_Discounts';

/**
 * List currently active platform promo codes.
 * Route: GET /promo-codes/active
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

        const result = await dynamoDb.send(new ScanCommand({
            TableName: PLATFORM_DISCOUNTS_TABLE
        }));

        const now = new Date();
        const promos = (result.Items || [])
            .map(normalizePlatformPromo)
            .filter(p => {
                if (!p.code) return false;
                if ((p.status || 'active') !== 'active' || p.isActive === false) return false;
                if (p.validFrom && now < new Date(p.validFrom)) return false;
                if (p.validTo && now > new Date(p.validTo)) return false;
                if (p.usageLimit && (p.usageCount || 0) >= p.usageLimit) return false;
                return true;
            })
            .map(p => ({
                code: p.code,
                title: p.title || '',
                description: p.description || '',
                type: p.type,
                value: p.value,
                minOrderAmount: p.minimumOrderAmount,
                endDate: p.validTo || null
            }));

        return respond(200, {
            success: true,
            promos,
            count: promos.length
        });

    } catch (error) {
        console.error('Error getting active promo codes:', error);

        return respond(500, {
            success: false,
            message: 'Failed to retrieve promo codes',
            error: error.message
        });
    }
};
