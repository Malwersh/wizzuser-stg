const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');
const { normalizeDiscount, validateDiscount, calculateDiscountAmount } = require('../shared/discount-engine');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const DISCOUNTS_TABLE = process.env.DISCOUNTS_TABLE || 'WhizzMerchants_Discounts';

/**
 * Validate a merchant discount against a prospective order.
 * Route: POST /promo-codes/apply
 * Body: { businessId, discountId, orderTotal, items, deliveryFee } (dinar amounts)
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

        const { businessId, discountId, orderTotal, items, deliveryFee } = body || {};

        if (!businessId || !discountId || orderTotal === undefined || !Array.isArray(items)) {
            return respond(400, {
                success: false,
                valid: false,
                message: 'Missing required fields: businessId, discountId, orderTotal, items'
            });
        }

        const result = await dynamoDb.send(new GetCommand({
            TableName: DISCOUNTS_TABLE,
            Key: { discountId }
        }));

        if (!result.Item) {
            return respond(404, {
                success: false,
                valid: false,
                message: 'Discount not found'
            });
        }

        const discount = normalizeDiscount(result.Item);

        if (discount.businessId !== businessId) {
            return respond(400, {
                success: false,
                valid: false,
                message: 'Discount does not belong to this store'
            });
        }

        const orderTotalFils = Math.round(orderTotal * 1000);
        const deliveryFeeFils = Math.round((deliveryFee || 0) * 1000);
        const itemsFils = items.map(item => ({
            id: item.id || item.itemId,
            itemId: item.itemId || item.id,
            categoryId: item.categoryId,
            price: Math.round((parseFloat(item.price) || 0) * 1000),
            quantity: item.quantity || 1
        }));

        const validation = validateDiscount(discount, orderTotalFils);
        if (!validation.valid) {
            return respond(400, {
                success: false,
                valid: false,
                message: validation.message
            });
        }

        const discountAmountFils = Math.round(
            calculateDiscountAmount(discount, orderTotalFils, itemsFils, deliveryFeeFils)
        );
        const discountAmount = discountAmountFils / 1000;

        return respond(200, {
            success: true,
            valid: true,
            discountAmount,
            discountAmountFils,
            finalTotal: (orderTotalFils - discountAmountFils) / 1000,
            discount
        });

    } catch (error) {
        console.error('Error validating discount:', error);

        return respond(500, {
            success: false,
            valid: false,
            message: 'Failed to validate discount',
            error: error.message
        });
    }
};
