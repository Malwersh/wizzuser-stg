const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

const TABLE_NAME = process.env.WIZZORDERS_TABLE;

/**
 * Lambda handler for updating order status with new schema
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
        // Validate required env vars
        requireEnv('WIZZORDERS_TABLE');
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
        console.log('🚀 ================================');
        console.log('🚀 UPDATE ORDER STATUS LAMBDA INVOKED');
        console.log('🚀 Order ID:', orderId);
        console.log('🚀 Event Body:', event.body);
        console.log('🚀 Event Method:', event.httpMethod);
        console.log('🚀 ================================');
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

        // Validate status transitions - UNIFIED STATUS SYSTEM
        // Map legacy statuses to unified ones
        const statusMapping = {
            'in_kitchen': 'preparing',
            'canceled_by_user': 'cancelled', 
            'canceled_by_store': 'cancelled',
            'canceled_by_system': 'cancelled',
            'out_for_delivery': 'on_the_way'
        };
        
        // Convert legacy status to unified status
        const unifiedStatus = statusMapping[status] || status;
        
        // Handle cancelReason standardization for cancelled orders
        let standardizedCancelReason = body.cancelReason;
        if (unifiedStatus === 'cancelled' && body.cancelReason) {
            // Map common Arabic reasons to standard English reasons
            const reasonMapping = {
                'طلب من العميل': 'User cancellation',
                'رفض المطعم': 'Restaurant cancellation', 
                'نفاد الصنف': 'Item unavailable',
                'خارج منطقة التوصيل': 'Out of delivery area',
                'الغاء من النظام': 'System cancellation',
                'عطل فني': 'Technical issue'
            };
            standardizedCancelReason = reasonMapping[body.cancelReason] || body.cancelReason;
        }
        
        const validStatuses = ['pending', 'confirmed', 'preparing', 'ready', 'on_the_way', 'delivered', 'cancelled', 'failed', 'expired'];
        if (!validStatuses.includes(unifiedStatus)) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Invalid status value',
                    validStatuses: validStatuses,
                    receivedStatus: status,
                    unifiedStatus: unifiedStatus,
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
            ':status': unifiedStatus, // Use unified status
            ':newRev': newRev,
            ':updatedAt': now,
            ':updatedBy': body.updatedBy || 'system',
            ':storeStatus': `${currentOrder.storeId}#${unifiedStatus}#${bucket}`, // Use unified status
            ':currentRev': currentRev
        };

        // Add timestamp fields based on unified status
        switch (unifiedStatus) {
            case 'confirmed':
                updateExpression += ', #confirmedAt = :confirmedAt';
                expressionAttributeNames['#confirmedAt'] = 'confirmedAt';
                expressionAttributeValues[':confirmedAt'] = now;
                break;
            case 'preparing':
                // Handle both 'preparing' and legacy 'in_kitchen'
                updateExpression += ', #inKitchenAt = :inKitchenAt';
                expressionAttributeNames['#inKitchenAt'] = 'inKitchenAt';
                expressionAttributeValues[':inKitchenAt'] = now;
                break;
            case 'ready':
                updateExpression += ', #readyAt = :readyAt';
                expressionAttributeNames['#readyAt'] = 'readyAt';
                expressionAttributeValues[':readyAt'] = now;
                
                console.log('🎯 ================================');
                console.log('🎯 STATUS CHANGED TO READY');
                console.log('🎯 FCFS System will handle assignment via OrderStreamProcessor');
                console.log('🎯 Order ID:', orderId);
                console.log('🎯 Current Order:', JSON.stringify(currentOrder, null, 2));
                console.log('🎯 ================================');
                
                // FCFS SYSTEM WILL HANDLE ASSIGNMENT - NO AUTO ASSIGNMENT
                console.log('🎯 ================================');
                console.log('🎯 FCFS SYSTEM ACTIVE');
                console.log('🎯 Order Status changed to READY - awaiting FCFS processing');
                console.log('🎯 ================================');
                break;
            case 'on_the_way':
                // Handle both 'on_the_way' and legacy 'out_for_delivery'
                updateExpression += ', #outForDeliveryAt = :outForDeliveryAt';
                expressionAttributeNames['#outForDeliveryAt'] = 'outForDeliveryAt';
                expressionAttributeValues[':outForDeliveryAt'] = now;
                
                // Update driver status if driverId provided
                if (body.driverId) {
                    updateExpression += ', #driverId = :driverId, #driverStatus = :driverStatus';
                    expressionAttributeNames['#driverId'] = 'driverId';
                    expressionAttributeNames['#driverStatus'] = 'driverStatus';
                    expressionAttributeValues[':driverId'] = body.driverId;
                    expressionAttributeValues[':driverStatus'] = `${body.driverId}#on_the_way#${bucket}`;
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
            case 'cancelled':
                // Handle all cancellation types with unified approach
                updateExpression += ', #canceledAt = :canceledAt, #canceledBy = :canceledBy';
                expressionAttributeNames['#canceledAt'] = 'canceledAt';
                expressionAttributeNames['#canceledBy'] = 'canceledBy';
                expressionAttributeValues[':canceledAt'] = now;
                
                // Determine who cancelled based on original status or reason
                let canceledBy = 'system';
                if (status.includes('user')) canceledBy = 'user';
                else if (status.includes('store') || status.includes('merchant')) canceledBy = 'merchant';
                else if (standardizedCancelReason) {
                    if (standardizedCancelReason.toLowerCase().includes('user')) canceledBy = 'user';
                    else if (standardizedCancelReason.toLowerCase().includes('restaurant') || standardizedCancelReason.toLowerCase().includes('merchant')) canceledBy = 'merchant';
                }
                // Use provided canceledBy if available
                if (body.canceledBy) {
                    canceledBy = body.canceledBy;
                }
                expressionAttributeValues[':canceledBy'] = canceledBy;
                
                if (standardizedCancelReason) {
                    updateExpression += ', #cancelReason = :cancelReason';
                    expressionAttributeNames['#cancelReason'] = 'cancelReason';
                    expressionAttributeValues[':cancelReason'] = standardizedCancelReason;
                }

                // Create cancel object with standardized reason
                const cancelObject = {
                    cancelReason: standardizedCancelReason || 'No reason provided',
                    canceledBy: canceledBy,
                    canceledAt: now
                };
                updateExpression += ', #cancel = :cancel';
                expressionAttributeNames['#cancel'] = 'cancel';
                expressionAttributeValues[':cancel'] = cancelObject;
                break;
            case 'expired':
                // Handle order expiration
                updateExpression += ', #expiredAt = :expiredAt';
                expressionAttributeNames['#expiredAt'] = 'expiredAt';
                expressionAttributeValues[':expiredAt'] = now;
                break;
            case 'failed':
                // Handle order failure
                updateExpression += ', #failedAt = :failedAt';
                expressionAttributeNames['#failedAt'] = 'failedAt';
                expressionAttributeValues[':failedAt'] = now;
                
                if (body.failureReason) {
                    updateExpression += ', #failureReason = :failureReason';
                    expressionAttributeNames['#failureReason'] = 'failureReason';
                    expressionAttributeValues[':failureReason'] = body.failureReason;
                }
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

        const result = await dynamoDb.send(updateCommand);

        console.log('Order status updated successfully:', orderId, 'to:', status);

        // Send WebSocket notification after successful database update
        try {
            const websocketSendUpdateFunction = process.env.WEBSOCKET_SEND_UPDATE_FUNCTION;
            const websocketManagementEndpoint =
                process.env.WEBSOCKET_MANAGEMENT_ENDPOINT ||
                (process.env.WEBSOCKET_ENDPOINT ? process.env.WEBSOCKET_ENDPOINT.replace('wss://', 'https://') : undefined);

            if (!websocketSendUpdateFunction || !websocketManagementEndpoint) {
                console.warn('⚠️ WebSocket notification skipped (missing WEBSOCKET_SEND_UPDATE_FUNCTION or WEBSOCKET_* endpoint env vars)');
            } else {
                const { LambdaClient, InvokeCommand } = require('@aws-sdk/client-lambda');
                const lambdaClient = new LambdaClient({});

                const websocketPayload = {
                    orderId: orderId,
                    updateData: {
                        status: unifiedStatus, // Use unified status for consistency
                        originalStatus: status, // Keep original for logging
                        orderNumber: result.Attributes.orderNumber_gsi || '',
                        estimatedDeliveryTime: result.Attributes.estimatedDeliveryTime,
                        deliveryTime: result.Attributes.deliveryTime,
                        message: getStatusMessage(unifiedStatus)
                    },
                    websocketEndpoint: websocketManagementEndpoint
                };

                console.log('📤 Sending WebSocket notification:', websocketPayload);

                const invokeCommand = new InvokeCommand({
                    FunctionName: websocketSendUpdateFunction,
                    Payload: JSON.stringify(websocketPayload),
                    InvocationType: 'Event' // Asynchronous invocation
                });

                await lambdaClient.send(invokeCommand);
                console.log('✅ WebSocket notification sent successfully');
            }
        } catch (wsError) {
            console.warn('⚠️ Failed to send WebSocket notification:', wsError);
            // Don't fail the main operation if WebSocket fails
        }

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
        
        // Handle optimistic locking conflicts
        if (error.name === 'ConditionalCheckFailedException') {
            return {
                statusCode: 409,
                headers: headers,
                body: JSON.stringify({
                    error: 'Order was modified by another process. Please retry.',
                    success: false
                })
            };
        }
        
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

// Status message helper function - Updated for unified status system
function getStatusMessage(status) {
    const statusMessages = {
        'pending': 'تم استلام طلبك وننتظر موافقة المطعم',
        'confirmed': 'تم تأكيد طلبك من المطعم',
        'preparing': 'يتم تحضير طلبك الآن',
        'ready': 'طلبك جاهز للتوصيل',
        'on_the_way': 'السائق في الطريق إليك',
        'delivered': 'تم توصيل طلبك بنجاح',
        'cancelled': 'تم إلغاء الطلب',
        'expired': 'انتهت صلاحية الطلب',
        'failed': 'فشل في معالجة الطلب',
        // Legacy status support for backwards compatibility
        'in_kitchen': 'يتم تحضير طلبك الآن',
        'out_for_delivery': 'السائق في الطريق إليك',
        // Add more status messages
        'user_cancelled': 'تم إلغاء الطلب من قبل المستخدم',
        'store_cancelled': 'تم إلغاء الطلب من قبل المطعم',
        'timeout_cancelled': 'تم إلغاء الطلب بسبب انتهاء الوقت'
    };

    return statusMessages[status] || `تم تحديث حالة الطلب إلى: ${status}`;
}

/**
 * Auto-assign order to available driver when status changes to 'ready'
 */
async function autoAssignOrderToDriver(orderId, orderData) {
    console.log('🎯 ================================');
    console.log('🎯 AUTO-ASSIGNMENT STARTED');
    console.log('🎯 Order ID:', orderId);
    console.log('🎯 Order Data Keys:', Object.keys(orderData || {}));
    console.log('🎯 ================================');
    
    try {
        const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
        const { DynamoDBDocumentClient, ScanCommand, PutCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
        const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');
        
        const dynamoClient = new DynamoDBClient({});
        const docClient = DynamoDBDocumentClient.from(dynamoClient);
        
        // 1. Find available driver connections
        console.log('📋 Scanning for available drivers...');
        const connectionsResult = await docClient.send(new ScanCommand({
            TableName: requireEnv('DRIVERS_CONNECTIONS_TABLE'),
            FilterExpression: '#status IN (:status1, :status2, :status3)',
            ExpressionAttributeNames: {
                '#status': 'status'
            },
            ExpressionAttributeValues: {
                ':status1': 'connected',
                ':status2': 'available', 
                ':status3': 'online'
            },
            Limit: 5 // Get up to 5 drivers
        }));

        if (!connectionsResult.Items || connectionsResult.Items.length === 0) {
            console.log('❌ No available drivers found');
            console.log('📊 Scanning all connections to debug...');
            
            // Debug: Scan all connections to see what's available
            const allConnectionsResult = await docClient.send(new ScanCommand({
                TableName: requireEnv('DRIVERS_CONNECTIONS_TABLE')
            }));
            
            console.log(`📋 Total connections: ${allConnectionsResult.Items?.length || 0}`);
            allConnectionsResult.Items?.forEach((conn, index) => {
                console.log(`   ${index + 1}. Driver: ${conn.driverId}, Status: ${conn.status}, Connection: ${conn.connectionId}`);
            });
            
            return;
        }

        console.log(`✅ Found ${connectionsResult.Items.length} available drivers:`);
        connectionsResult.Items.forEach((conn, index) => {
            console.log(`   ${index + 1}. Driver: ${conn.driverId}, Status: ${conn.status}, Connection: ${conn.connectionId}`);
        });

        // 📡 NEW: Send order offer to ALL available drivers (First Come, First Served)
        console.log('📡 Broadcasting order offer to all available drivers...');
        
        const orderOffer = {
            type: 'order_offer',
            data: {
                orderId,
                orderNumber: orderData.orderNumber || `ORD${Date.now()}`,
                customerName: orderData.customerName || 'Customer',
                customerPhone: orderData.customerPhone || '',
                totalAmount: (orderData.pricing?.total || orderData.totalAmount || 0) / 100,
                deliveryFee: (orderData.pricing?.deliveryFee || orderData.deliveryFee || 0) / 100,
                storeId: orderData.storeId || '',
                storeName: orderData.storeName || 'Restaurant',
                status: 'ready',
                deliveryAddress: {
                    fullAddress: orderData.deliveryAddress?.fullAddress || 'Address not specified',
                    city: orderData.deliveryAddress?.city || '',
                    area: orderData.deliveryAddress?.area || ''
                },
                items: orderData.items || [],
                paymentMethod: orderData.paymentMethod || 'cash',
                createdAt: orderData.createdAt || now,
                readyAt: orderData.readyAt || now,
                offerExpiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString(), // 5 minutes to accept
                offerTimeoutSec: 300 // 5 minutes
            }
        };

        let broadcastSuccessCount = 0;
        const offerSessions = [];

        // Send offer to all available drivers
        for (const connection of connectionsResult.Items) {
            try {
                console.log(`📤 Sending order offer to driver: ${connection.driverId || 'Unknown'} (${connection.connectionId})`);
                
                await apiGateway.send(new PostToConnectionCommand({
                    ConnectionId: connection.connectionId,
                    Data: JSON.stringify(orderOffer)
                }));

                broadcastSuccessCount++;
                offerSessions.push({
                    connectionId: connection.connectionId,
                    driverId: connection.driverId || connection.connectionId,
                    offeredAt: now
                });
                
                console.log(`✅ Order offer sent to driver: ${connection.driverId}`);
                
            } catch (wsError) {
                console.error(`❌ Failed to send offer to driver ${connection.driverId}:`, wsError.message);
                
                if (wsError.statusCode === 410) {
                    console.log(`🗑️ Stale connection detected: ${connection.connectionId}`);
                    // Update connection status to disconnected
                    try {
                        await docClient.send(new UpdateCommand({
                            TableName: requireEnv('DRIVERS_CONNECTIONS_TABLE'),
                            Key: { connectionId: connection.connectionId },
                            UpdateExpression: 'SET #status = :status',
                            ExpressionAttributeNames: { '#status': 'status' },
                            ExpressionAttributeValues: { ':status': 'disconnected' }
                        }));
                    } catch (updateError) {
                        console.error('Failed to update stale connection:', updateError);
                    }
                }
            }
        }

        console.log(`📊 Order offers broadcast result:`);
        console.log(`   ✅ Successful: ${broadcastSuccessCount}/${connectionsResult.Items.length}`);
        console.log(`   📋 Active offer sessions: ${offerSessions.length}`);

        // Create order offer tracking record (for managing acceptances)
        const offerTrackingId = `offer_${orderId}_${Date.now()}`;
        await docClient.send(new PutCommand({
            TableName: requireEnv('DRIVERS_ASSIGNMENTS_TABLE'),
            Item: {
                assignmentId: offerTrackingId,
                orderId,
                status: 'broadcast', // New status for tracking broadcasts
                offerSessions: offerSessions,
                broadcastAt: now,
                expiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
                successfulBroadcasts: broadcastSuccessCount,
                totalDrivers: connectionsResult.Items.length
            }
        }));

        console.log(`📝 Created offer tracking record: ${offerTrackingId}`);

        if (broadcastSuccessCount === 0) {
            console.log('❌ No drivers received the order offer');
            return false;
        }

        // NOTE: Actual assignment will happen when a driver accepts the offer
        // This will be handled in a separate message handler for driver responses
        console.log(`🎯 Order offer broadcast completed! Waiting for driver acceptance...`);
        
        return true; // Successfully broadcast to at least one driver

    } catch (error) {
        console.error('❌ ================================');
        console.error('❌ CRITICAL AUTO-ASSIGNMENT ERROR');
        console.error(`❌ Order ID: ${orderId}`);
        console.error(`❌ Error Message: ${error.message}`);
        console.error(`❌ Error Stack: ${error.stack}`);
        console.error(`❌ Error Name: ${error.name}`);
        console.error('❌ ================================');
        
        return false;
    }
}
