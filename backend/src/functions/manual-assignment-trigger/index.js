/**
 * Manual Assignment Trigger Lambda Function
 * 
 * Allows administrators to manually trigger driver assignment for orders
 * Useful for testing, retry scenarios, or special cases
 */

const { processOrderStatusChange } = require('/opt/nodejs/driver-assignment/order-status-trigger');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

const dynamoDbClient = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(dynamoDbClient);

const ORDERS_TABLE = process.env.ORDERS_TABLE || 'order-receiver-orders-dev';

/**
 * Lambda handler for manual assignment triggering
 */
exports.handler = async (event) => {
    console.log('📨 Manual assignment trigger event:', JSON.stringify(event, null, 2));
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
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

        // Only allow POST method
        if (event.httpMethod !== 'POST') {
            return {
                statusCode: 405,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Method not allowed'
                })
            };
        }

        const body = event.body ? JSON.parse(event.body) : {};
        const { orderId, forceAssignment } = body;

        if (!orderId) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Order ID is required'
                })
            };
        }

        console.log(`🎯 Manual assignment trigger for order: ${orderId}`);

        // Get current order details
        const orderDetails = await getOrderFromDatabase(orderId);
        
        if (!orderDetails) {
            return {
                statusCode: 404,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Order not found'
                })
            };
        }

        // Check if order is in a valid state for assignment
        const validStatuses = ['preparing', 'ready', 'confirmed'];
        if (!validStatuses.includes(orderDetails.status) && !forceAssignment) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: `Order status "${orderDetails.status}" is not valid for assignment. Valid statuses: ${validStatuses.join(', ')}`,
                    currentStatus: orderDetails.status,
                    suggestion: 'Use forceAssignment: true to override this check'
                })
            };
        }

        // Trigger the assignment process
        const assignmentResult = await processOrderStatusChange({
            orderId: orderId,
            newStatus: orderDetails.status,
            previousStatus: orderDetails.status, // Using same status for manual trigger
            orderData: orderDetails
        });

        if (assignmentResult.success) {
            return {
                statusCode: 200,
                headers: headers,
                body: JSON.stringify({
                    success: true,
                    message: 'Driver assignment triggered successfully',
                    orderId: orderId,
                    offerId: assignmentResult.offerId,
                    eligibleDriversCount: assignmentResult.eligibleDriversCount,
                    assignmentDetails: assignmentResult
                })
            };
        } else {
            return {
                statusCode: 200, // Still successful request, but no assignment possible
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Driver assignment could not be completed',
                    orderId: orderId,
                    reason: assignmentResult.reason,
                    details: assignmentResult
                })
            };
        }

    } catch (error) {
        console.error('❌ Manual assignment trigger error:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                success: false,
                message: 'Failed to trigger assignment',
                error: process.env.NODE_ENV === 'development' ? error.message : 'Internal server error'
            })
        };
    }
};

/**
 * Get order details from database
 */
async function getOrderFromDatabase(orderId) {
    try {
        // Try the new key structure first
        const getCommand = new GetCommand({
            TableName: ORDERS_TABLE,
            Key: {
                PK: `ORDER#${orderId}`,
                SK: 'META'
            }
        });

        let result = await dynamodb.send(getCommand);
        
        if (!result.Item) {
            // Try alternative key structure
            const altGetCommand = new GetCommand({
                TableName: ORDERS_TABLE,
                Key: {
                    orderId: orderId
                }
            });
            
            result = await dynamodb.send(altGetCommand);
        }

        if (!result.Item) {
            return null;
        }

        const order = result.Item;
        
        // Transform to standardized format
        return {
            orderId: order.orderId || orderId,
            orderNumber: order.orderNumber_gsi || order.orderNumber || `ORD-${Date.now()}`,
            businessId: order.storeId || order.businessId,
            businessName: order.storeName || order.businessName,
            customerName: order.customerName,
            customerPhone: order.customerPhone,
            deliveryAddress: order.deliveryAddress,
            totalAmount: order.finalTotal || order.totalAmount,
            paymentMethod: order.paymentMethod,
            deliveryInstructions: order.deliveryInstructions,
            estimatedPreparationTime: order.estimatedPreparationTime,
            city: order.deliveryAddress?.city || order.city || 'Baghdad',
            status: order.status,
            createdAt: order.createdAt,
            updatedAt: order.updatedAt
        };

    } catch (error) {
        console.error('❌ Error fetching order from database:', error);
        throw error;
    }
}

/**
 * Test function for local development
 */
async function testManualAssignment(orderId) {
    const testEvent = {
        httpMethod: 'POST',
        body: JSON.stringify({
            orderId: orderId,
            forceAssignment: false
        })
    };

    return await exports.handler(testEvent);
}

// Export test function for development
module.exports = {
    handler: exports.handler,
    testManualAssignment
};
