const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, UpdateCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.ORDERS_TABLE;

/**
 * Lambda handler for updating order status
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

        // Parse request body
        let body;
        if (typeof event.body === 'string') {
            body = JSON.parse(event.body);
        } else {
            body = event.body;
        }

        const { status } = body;
        
        if (!status) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Status is required',
                    success: false
                })
            };
        }

        // Validate status transitions
        const validStatuses = ['pending', 'confirmed', 'in_kitchen', 'ready', 'out_for_delivery', 'delivered', 'canceled_by_user', 'canceled_by_store', 'canceled_by_system'];
        if (!validStatuses.includes(status)) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Invalid status value',
                    validStatuses: validStatuses,
                    success: false
                })
            };
        }

        console.log('Updating order status:', orderId, 'to:', status);

        // Helper function to generate bucket (b0-b9) from orderId hash
        const generateBucket = (id) => {
            let hash = 0;
            for (let i = 0; i < id.length; i++) {
                hash = ((hash << 5) - hash) + id.charCodeAt(i);
                hash = hash & hash; // Convert to 32bit integer
            }
            return `b${Math.abs(hash) % 10}`;
        };

        const bucket = generateBucket(orderId);

        // First, get the current order to check rev and get storeId
        const getCommand = new GetCommand({
            TableName: TABLE_NAME,
            Key: {
                PK: `ORDER#${orderId}`,
                SK: 'META'
            }
        });

        const getResult = await dynamoDb.send(getCommand);

        if (!getResult.Item) {
            return {
                statusCode: 404,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order not found',
                    success: false
                })
            };
        }

        const currentOrder = getResult.Item;
        const currentRev = currentOrder.rev || 1;
        const newRev = currentRev + 1;

        const now = new Date().toISOString();

        // Prepare update expressions based on status
        let updateExpression = 'SET #status = :status, #rev = :newRev, #updatedAt = :updatedAt, #updatedBy = :updatedBy, #storeStatus = :storeStatus';
        let expressionAttributeNames = {
            '#status': 'status',
            '#rev': 'rev',
            '#updatedAt': 'updatedAt',
            '#updatedBy': 'updatedBy',
            '#storeStatus': 'storeStatus'
        };
        let expressionAttributeValues = {
            ':status': status,
            ':newRev': newRev,
            ':updatedAt': now,
            ':updatedBy': body.updatedBy || 'system',
            ':storeStatus': `${currentOrder.storeId}#${status}#${bucket}`,
            ':currentRev': currentRev
        };

        // Add timestamp fields based on status
        switch (status) {
            case 'confirmed':
                updateExpression += ', #confirmedAt = :confirmedAt';
                expressionAttributeNames['#confirmedAt'] = 'confirmedAt';
                expressionAttributeValues[':confirmedAt'] = now;
                break;
            case 'in_kitchen':
                updateExpression += ', #inKitchenAt = :inKitchenAt';
                expressionAttributeNames['#inKitchenAt'] = 'inKitchenAt';
                expressionAttributeValues[':inKitchenAt'] = now;
                break;
            case 'ready':
                updateExpression += ', #readyAt = :readyAt';
                expressionAttributeNames['#readyAt'] = 'readyAt';
                expressionAttributeValues[':readyAt'] = now;
                break;
            case 'out_for_delivery':
                updateExpression += ', #outForDeliveryAt = :outForDeliveryAt';
                expressionAttributeNames['#outForDeliveryAt'] = 'outForDeliveryAt';
                expressionAttributeValues[':outForDeliveryAt'] = now;
                
                // Update driver status if driverId provided
                if (body.driverId) {
                    updateExpression += ', #driverId = :driverId, #driverStatus = :driverStatus';
                    expressionAttributeNames['#driverId'] = 'driverId';
                    expressionAttributeNames['#driverStatus'] = 'driverStatus';
                    expressionAttributeValues[':driverId'] = body.driverId;
                    expressionAttributeValues[':driverStatus'] = `${body.driverId}#out_for_delivery#${bucket}`;
                }
                break;
            case 'delivered':
                updateExpression += ', #deliveredAt = :deliveredAt';
                expressionAttributeNames['#deliveredAt'] = 'deliveredAt';
                expressionAttributeValues[':deliveredAt'] = now;
                
                // Handle COD collection if applicable
                if (body.codCollected && currentOrder.paymentMethod === 'cod') {
                    updateExpression += ', #codCollectedAt = :codCollectedAt, #paymentStatus = :paymentStatus';
                    expressionAttributeNames['#codCollectedAt'] = 'codCollectedAt';
                    expressionAttributeNames['#paymentStatus'] = 'paymentStatus';
                    expressionAttributeValues[':codCollectedAt'] = now;
                    expressionAttributeValues[':paymentStatus'] = 'captured';
                    
                    if (body.collectorId) {
                        updateExpression += ', #collectorId = :collectorId';
                        expressionAttributeNames['#collectorId'] = 'collectorId';
                        expressionAttributeValues[':collectorId'] = body.collectorId;
                    }
                }
                break;
            case 'canceled_by_user':
            case 'canceled_by_store':
            case 'canceled_by_system':
                updateExpression += ', #canceledAt = :canceledAt, #canceledBy = :canceledBy';
                expressionAttributeNames['#canceledAt'] = 'canceledAt';
                expressionAttributeNames['#canceledBy'] = 'canceledBy';
                expressionAttributeValues[':canceledAt'] = now;
                expressionAttributeValues[':canceledBy'] = status.split('_')[2]; // Extract user/store/system
                
                if (body.cancelReason) {
                    updateExpression += ', #cancelReason = :cancelReason';
                    expressionAttributeNames['#cancelReason'] = 'cancelReason';
                    expressionAttributeValues[':cancelReason'] = body.cancelReason;
                }

                // Create cancel object
                const cancelObject = {
                    cancelReason: body.cancelReason || 'No reason provided',
                    canceledBy: status.split('_')[2],
                    canceledAt: now
                };
                updateExpression += ', #cancel = :cancel';
                expressionAttributeNames['#cancel'] = 'cancel';
                expressionAttributeValues[':cancel'] = cancelObject;
                break;
        }

        // Update order with optimistic locking
        const updateCommand = new UpdateCommand({
            TableName: TABLE_NAME,
            Key: {
                PK: `ORDER#${orderId}`,
                SK: 'META'
            },
            UpdateExpression: updateExpression,
            ExpressionAttributeNames: expressionAttributeNames,
            ExpressionAttributeValues: expressionAttributeValues,
            ConditionExpression: '#rev = :currentRev', // Optimistic locking
            ReturnValues: 'ALL_NEW'
        });

        // Prepare update expression and values
        let updateExpression = 'SET #status = :status, updatedAt = :updatedAt';
        const expressionAttributeNames = {
            '#status': 'status'
        };
        const expressionAttributeValues = {
            ':status': status,
            ':updatedAt': now
        };

        // Add status-specific timestamps
        if (status === 'confirmed') {
            updateExpression += ', confirmedAt = :confirmedAt';
            expressionAttributeValues[':confirmedAt'] = now;
        } else if (status === 'delivered') {
            updateExpression += ', actualDeliveryTime = :actualDeliveryTime';
            expressionAttributeValues[':actualDeliveryTime'] = now;
        } else if (status === 'cancelled' && body.cancelReason) {
            updateExpression += ', cancelReason = :cancelReason';
            expressionAttributeValues[':cancelReason'] = body.cancelReason;
        }

        // Update order in DynamoDB
        const updateCommand = new UpdateCommand({
            TableName: TABLE_NAME,
            Key: {
                orderId: orderId
            },
            UpdateExpression: updateExpression,
            ExpressionAttributeNames: expressionAttributeNames,
            ExpressionAttributeValues: expressionAttributeValues,
            ReturnValues: 'ALL_NEW'
        });

        const result = await dynamoDb.send(updateCommand);

        console.log('Order status updated successfully:', orderId);

        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                success: true,
                message: 'Order status updated successfully',
                order: result.Attributes
            })
        };

    } catch (error) {
        console.error('Error updating order status:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                error: 'Failed to update order status',
                message: error.message,
                success: false
            })
        };
    }
};
