const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { v4: uuidv4 } = require('uuid');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.ORDERS_TABLE;

/**
 * Lambda handler for creating a new order
 */
exports.handler = async (event) => {
    console.log('Event received:', JSON.stringify(event, null, 2));
    console.log('TABLE_NAME:', TABLE_NAME);
    console.log('Environment variables:', {
        ORDERS_TABLE: process.env.ORDERS_TABLE,
        NODE_ENV: process.env.NODE_ENV
    });
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    };
    
    try {
        // Early validation of environment variables
        if (!TABLE_NAME) {
            console.error('TABLE_NAME is not set!');
            return {
                statusCode: 500,
                headers: headers,
                body: JSON.stringify({
                    error: 'Configuration error: TABLE_NAME is not set',
                    success: false
                })
            };
        }
        
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

        // Support both 'items' and 'cartItems' for backward compatibility
        if (body.cartItems && !body.items) {
            body.items = body.cartItems;
        }

        // Validate required fields
        const requiredFields = ['userId', 'storeId', 'storeName', 'deliveryAddress', 'paymentMethod'];
        for (const field of requiredFields) {
            if (!body[field]) {
                return {
                    statusCode: 400,
                    headers: headers,
                    body: JSON.stringify({
                        error: `Missing required field: ${field}`,
                        success: false
                    })
                };
            }
        }

        // Validate items array
        if (!Array.isArray(body.items) || body.items.length === 0) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Items array is required and must not be empty',
                    success: false
                })
            };
        }

        // Generate order ID and order number
        const orderId = uuidv4();
        const orderNumber = `ORD${Date.now()}`;
        const createdAt = new Date().toISOString();

        // Calculate totals
        // If subtotal is not provided, calculate from items
        let subtotal = body.subtotal || 0;
        if (subtotal === 0) {
            subtotal = body.items.reduce((sum, item) => {
                const itemPrice = item.price || item.base_price || 0;
                const quantity = item.quantity || 1;
                return sum + (itemPrice * quantity);
            }, 0);
        }
        
        const deliveryFee = body.deliveryFee || 10.0;
        const tax = body.tax || 0;
        const discount = body.discount || 0;
        const total = subtotal + deliveryFee + tax - discount;

        // Create order object
        const order = {
            orderId: orderId,
            orderNumber: orderNumber,
            userId: body.userId,
            storeId: body.storeId,
            storeName: body.storeName,
            items: body.items,
            subtotal: subtotal,
            deliveryFee: deliveryFee,
            tax: tax,
            discount: discount,
            total: total,
            status: 'pending',
            paymentMethod: body.paymentMethod,
            paymentStatus: 'pending',
            deliveryAddress: body.deliveryAddress,
            deliveryInstructions: body.deliveryInstructions || null,
            customerPhone: body.customerPhone || null,
            customerName: body.customerName || null,
            customerEmail: body.customerEmail || null,
            isGuestOrder: body.isGuestOrder || false,
            createdAt: createdAt,
            confirmedAt: null,
            estimatedDeliveryTime: new Date(Date.now() + 30 * 60 * 1000).toISOString(), // 30 minutes from now
            actualDeliveryTime: null,
            cancelReason: null,
            metadata: body.metadata || null
        };

        console.log('Order to be created:', JSON.stringify(order, null, 2));

        // Save order to DynamoDB
        const putCommand = new PutCommand({
            TableName: TABLE_NAME,
            Item: order
        });

        await dynamoDb.send(putCommand);

        console.log('Order created successfully:', orderId);

        return {
            statusCode: 201,
            headers: headers,
            body: JSON.stringify({
                success: true,
                message: 'Order created successfully',
                orderId: orderId,
                orderNumber: orderNumber,
                order: order
            })
        };

    } catch (error) {
        console.error('Error creating order:', error);
        console.error('Error stack:', error.stack);
        console.error('Error name:', error.name);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                error: 'Failed to create order',
                message: error.message,
                errorName: error.name,
                success: false
            })
        };
    }
};
