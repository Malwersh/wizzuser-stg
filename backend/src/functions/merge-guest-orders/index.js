const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, UpdateCommand, TransactWriteCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

// Use WizzOrders table
const TABLE_NAME = process.env.WIZZORDERS_TABLE || 'WizzOrders';

/**
 * 🔄 Merge Guest Orders Handler
 * 
 * Endpoint: POST /users/{user_id}/merge-guest
 * Authentication: Required (user must be authenticated)
 * 
 * Merges guest orders to authenticated user account
 * Uses conditional updates to prevent conflicts
 */
exports.handler = async (event) => {
    console.log('🔄 Merge Guest Orders Event:', JSON.stringify(event, null, 2));

    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',  
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
    };

    try {
        // Handle CORS preflight
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers,
                body: ''
            };
        }

        if (event.httpMethod !== 'POST') {
            return {
                statusCode: 405,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Method not allowed'
                })
            };
        }

        // Extract userId from path parameters
        const userId = event.pathParameters?.user_id;
        if (!userId) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'User ID is required in path',
                    error: 'MISSING_USER_ID'
                })
            };
        }

        // Parse request body
        const body = JSON.parse(event.body || '{}');
        const guestToken = body.guestToken;

        if (!guestToken) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'guestToken is required in request body',
                    error: 'MISSING_GUEST_TOKEN'
                })
            };
        }

        console.log('👤 User ID:', userId);
        console.log('🎫 Guest Token:', guestToken);

        // Step 1: Find all orders associated with the guestToken
        const queryParameters = {
            TableName: TABLE_NAME,
            IndexName: 'GSI_User',
            KeyConditionExpression: 'userId_gsi = :guestToken',
            ExpressionAttributeValues: {
                ':guestToken': guestToken
            }
        };

        console.log('🔍 Searching for guest orders...');
        const result = await dynamoDb.send(new QueryCommand(queryParameters));
        const guestOrders = result.Items || [];

        console.log(`📦 Found ${guestOrders.length} guest orders to merge`);

        if (guestOrders.length === 0) {
            return {
                statusCode: 200,
                headers,
                body: JSON.stringify({
                    success: true,
                    message: 'No guest orders found to merge',
                    mergedCount: 0,
                    failedCount: 0,
                    details: []
                })
            };
        }

        // Step 2: Process orders in batches to avoid TransactWrite limits (max 25 items)
        const batchSize = 20; // Use 20 to be safe with TransactWrite limits
        const batches = [];
        for (let i = 0; i < guestOrders.length; i += batchSize) {
            batches.push(guestOrders.slice(i, i + batchSize));
        }

        let mergedCount = 0;
        let failedCount = 0;
        const mergeDetails = [];

        // Step 3: Process each batch
        for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
            const batch = batches[batchIndex];
            console.log(`🔄 Processing batch ${batchIndex + 1}/${batches.length} with ${batch.length} orders`);

            // Prepare transaction items for this batch
            const transactItems = batch.map(order => {
                const orderId = order.orderId;
                
                return {
                    Update: {
                        TableName: TABLE_NAME,
                        Key: {
                            PK: `ORDER#${orderId}`,
                            SK: 'META'
                        },
                        UpdateExpression: 'SET userId = :userId, userId_gsi = :userId_gsi, isGuestOrder = :isGuestOrder, updatedAt = :updatedAt, updatedBy = :updatedBy, #rev = #rev + :incr',
                        ExpressionAttributeNames: {
                            '#rev': 'rev'
                        },
                        ExpressionAttributeValues: {
                            ':userId': userId,
                            ':userId_gsi': userId,
                            ':isGuestOrder': false,
                            ':updatedAt': new Date().toISOString(),
                            ':updatedBy': 'merge_guest_orders',
                            ':incr': 1
                        },
                        // Conditional update: only merge if still a guest order
                        ConditionExpression: 'attribute_exists(PK) AND (attribute_not_exists(userId) OR userId = :nullUserId OR isGuestOrder = :trueValue)',
                        ExpressionAttributeValues: {
                            ...{
                                ':userId': userId,
                                ':userId_gsi': userId,
                                ':isGuestOrder': false,
                                ':updatedAt': new Date().toISOString(),
                                ':updatedBy': 'merge_guest_orders',
                                ':incr': 1
                            },
                            ':nullUserId': null,
                            ':trueValue': true
                        }
                    }
                };
            });

            try {
                // Execute transaction for this batch
                await dynamoDb.send(new TransactWriteCommand({
                    TransactItems: transactItems
                }));

                // All items in batch succeeded
                mergedCount += batch.length;
                batch.forEach(order => {
                    mergeDetails.push({
                        orderId: order.orderId,
                        orderNumber: order.orderNumber,
                        status: 'merged',
                        message: 'Successfully merged to user account'
                    });
                });

                console.log(`✅ Batch ${batchIndex + 1} completed successfully (${batch.length} orders)`);

            } catch (transactionError) {
                console.error(`❌ Batch ${batchIndex + 1} failed:`, transactionError);

                // If transaction fails, try individual updates to identify which ones failed
                for (const order of batch) {
                    try {
                        await dynamoDb.send(new UpdateCommand({
                            TableName: TABLE_NAME,
                            Key: {
                                PK: `ORDER#${order.orderId}`,
                                SK: 'META'
                            },
                            UpdateExpression: 'SET userId = :userId, userId_gsi = :userId_gsi, isGuestOrder = :isGuestOrder, updatedAt = :updatedAt, updatedBy = :updatedBy, #rev = #rev + :incr',
                            ExpressionAttributeNames: {
                                '#rev': 'rev'
                            },
                            ExpressionAttributeValues: {
                                ':userId': userId,
                                ':userId_gsi': userId,
                                ':isGuestOrder': false,
                                ':updatedAt': new Date().toISOString(),
                                ':updatedBy': 'merge_guest_orders',
                                ':incr': 1
                            },
                            ConditionExpression: 'attribute_exists(PK) AND (attribute_not_exists(userId) OR userId = :nullUserId OR isGuestOrder = :trueValue)',
                            ExpressionAttributeValues: {
                                ...{
                                    ':userId': userId,
                                    ':userId_gsi': userId,
                                    ':isGuestOrder': false,
                                    ':updatedAt': new Date().toISOString(),
                                    ':updatedBy': 'merge_guest_orders',
                                    ':incr': 1
                                },
                                ':nullUserId': null,
                                ':trueValue': true
                            }
                        }));

                        mergedCount++;
                        mergeDetails.push({
                            orderId: order.orderId,
                            orderNumber: order.orderNumber,
                            status: 'merged',
                            message: 'Successfully merged to user account (individual update)'
                        });

                        console.log(`✅ Individual merge successful for order: ${order.orderId}`);

                    } catch (individualError) {
                        failedCount++;
                        let errorMessage = 'Unknown error';
                        
                        if (individualError.name === 'ConditionalCheckFailedException') {
                            errorMessage = 'Order already belongs to another user or conflict detected';
                        } else {
                            errorMessage = individualError.message;
                        }

                        mergeDetails.push({
                            orderId: order.orderId,
                            orderNumber: order.orderNumber,
                            status: 'failed',
                            message: errorMessage,
                            error: individualError.name
                        });

                        console.log(`❌ Individual merge failed for order: ${order.orderId} - ${errorMessage}`);
                    }
                }
            }
        }

        // Step 4: Create audit log entry
        const auditLog = {
            operation: 'merge_guest_orders',
            userId: userId,
            guestToken: guestToken,
            timestamp: new Date().toISOString(),
            totalOrders: guestOrders.length,
            mergedCount: mergedCount,
            failedCount: failedCount,
            details: mergeDetails
        };

        console.log('📋 Merge audit log:', JSON.stringify(auditLog, null, 2));

        // Step 5: Return results
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                message: `Merge completed: ${mergedCount} orders merged, ${failedCount} failed`,
                mergedCount: mergedCount,
                failedCount: failedCount,
                totalProcessed: guestOrders.length,
                details: mergeDetails,
                auditLog: auditLog
            })
        };

    } catch (error) {
        console.error('❌ Error in merge guest orders:', error);

        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({
                success: false,
                message: 'Failed to merge guest orders',
                error: error.message
            })
        };
    }
};
