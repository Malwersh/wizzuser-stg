const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { normalizePlatformPromo, validatePlatformPromo, calculateDiscountAmount } = require('../shared/discount-engine');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const PLATFORM_DISCOUNTS_TABLE = process.env.PLATFORM_DISCOUNTS_TABLE || 'WizzCentral_Platform_Discounts';

/**
 * Validate a typed platform promo code against a prospective order.
 * Route: POST /promo-codes/validate
 * Body: { code, orderTotal, deliveryFee, storeId? } (dinar amounts)
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

        let body;
        if (typeof event.body === 'string') {
            body = JSON.parse(event.body);
        } else {
            body = event.body;
        }

        const { code, orderTotal, deliveryFee } = body || {};

        if (!code || orderTotal === undefined) {
            return respond(400, {
                success: false,
                valid: false,
                message: 'Missing required fields: code, orderTotal'
            });
        }

        const result = await dynamoDb.send(new QueryCommand({
            TableName: PLATFORM_DISCOUNTS_TABLE,
            IndexName: 'code-index',
            KeyConditionExpression: '#code = :code',
            ExpressionAttributeNames: { '#code': 'code' },
            ExpressionAttributeValues: { ':code': String(code).trim() }
        }));

        if (!result.Items || result.Items.length === 0) {
            return respond(404, {
                success: false,
                valid: false,
                message: 'Promo code not found'
            });
        }

        const promo = normalizePlatformPromo(result.Items[0]);
        const orderTotalFils = Math.round(orderTotal * 1000);
        const deliveryFeeFils = Math.round((deliveryFee || 0) * 1000);

        const validation = validatePlatformPromo(promo, orderTotalFils);
        if (!validation.valid) {
            return respond(400, {
                success: false,
                valid: false,
                message: validation.message
            });
        }

        const discountAmountFils = Math.round(
            calculateDiscountAmount(promo, orderTotalFils, [], deliveryFeeFils)
        );
        const discountAmount = discountAmountFils / 1000;

        return respond(200, {
            success: true,
            valid: true,
            discountAmount,
            discountAmountFils,
            finalTotal: (orderTotalFils - discountAmountFils) / 1000,
            promo: {
                code: promo.code,
                title: promo.title || '',
                type: promo.type,
                value: promo.value
            }
        });

    } catch (error) {
        console.error('Error validating promo code:', error);

        return respond(500, {
            success: false,
            valid: false,
            message: 'Failed to validate promo code',
            error: error.message
        });
    }
};
