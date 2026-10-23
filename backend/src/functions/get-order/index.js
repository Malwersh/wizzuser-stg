const {customerOrderView} = require('../shared/customer-order-view');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

const TABLE_NAME = process.env.WIZZORDERS_TABLE;
const DRIVERS_TABLE = process.env.DRIVERS_TABLE || 'WhizzDrivers_dev';

/**
 * Get driver information from WhizzDrivers_dev table
 */
async function getDriverInfo(driverId) {
    if (!driverId) return null;
    
    try {
        console.log('🚗 Fetching driver info for:', driverId);
        
        // Try with driverId as primary key (most common)
        const getCommand = new GetCommand({
            TableName: DRIVERS_TABLE,
            Key: { driverId: driverId }
        });
        
        const result = await dynamoDb.send(getCommand);
        
        if (result.Item) {
            console.log('✅ Driver info found:', {
                name: result.Item.name,
                vehicleType: result.Item.vehicleType,
                licenseNumber: result.Item.licenseNumber
            });
            
            return {
                driverName: result.Item.name,
                driver_name: result.Item.name,
                vehicleType: result.Item.vehicleType,
                vehicle_type: result.Item.vehicleType,
                vehiclePlate: result.Item.licenseNumber,
                vehicle_plate: result.Item.licenseNumber,
                license_number: result.Item.licenseNumber,
                licenseNumber: result.Item.licenseNumber
            };
        }
        
        console.log('⚠️ Driver not found in WhizzDrivers_dev');
        return null;
    } catch (error) {
        console.error('❌ Error fetching driver info:', error);
        return null;
    }
}

/**
 * Lambda handler for retrieving an order by ID
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

        // Get order ID from path parameters
        const orderId = event.pathParameters?.orderId || event.pathParameters?.id;
        
        if (!orderId) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order ID is required',
                    success: false
                })
            };
        }

        console.log('Retrieving order:', orderId);

        // Get order from DynamoDB using new PK/SK structure
        const getCommand = new GetCommand({
            TableName: TABLE_NAME,
            ConsistentRead: true,
            Key: {
                PK: `ORDER#${orderId}`,
                SK: 'META'
            }
        });

        const result = await dynamoDb.send(getCommand);

        if (!result.Item) {
            return {
                statusCode: 404,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order not found',
                    success: false
                })
            };
        }

        console.log('Order retrieved successfully:', orderId);

        // Enrich order with driver information if driverId exists
        const order = result.Item;
        if (order.driverId) {
            console.log('🚗 Order has driverId, fetching driver details...');
            const driverInfo = await getDriverInfo(order.driverId);
            
            if (driverInfo) {
                // Add driver info to order with multiple field name formats
                Object.assign(order, driverInfo);
                console.log('✅ Driver info added to order response');
            } else {
                console.log('⚠️ Driver info not found for driverId:', order.driverId);
            }
        }

        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                success: true,
                order: customerOrderView(order)
            })
        };

    } catch (error) {
        console.error('Error retrieving order:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                error: 'Failed to retrieve order',
                message: error.message,
                success: false
            })
        };
    }
};
