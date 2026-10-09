const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, ScanCommand, UpdateCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('PayTabs Webhook Event:', JSON.stringify(event, null, 2));
    
    try {
        // Parse webhook data - handle different sources
        let body;
        if (event.body) {
            body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
        } else if (event.httpMethod === 'POST' && event.requestContext) {
            // Check for query parameters in a POST request (some payment gateways send data this way)
            body = event.queryStringParameters || {};
        } else {
            // Direct payload for testing
            body = event;
        }
        
        console.log('PayTabs Webhook Body:', body);
        
        // If body is still empty, check if this is a GET request with query parameters
        if (!body || Object.keys(body).length === 0) {
            if (event.queryStringParameters) {
                body = event.queryStringParameters;
                console.log('Using query parameters as body:', body);
            }
        }
        
        const {
            tran_ref,
            cart_id,
            tran_type,
            cart_amount,
            cart_currency,
            respStatus,
            respCode,
            respMessage,
            acquirerMessage,
            acquirerRRN
        } = body;
        
        if (!tran_ref || !cart_id) {
            console.error('Missing required PayTabs webhook data');
            return {
                statusCode: 400,
                body: JSON.stringify({ 
                    success: false, 
                    message: 'Missing required webhook data' 
                })
            };
        }
        
        // Extract userId from cart_id (format: TOPUP_userId_timestamp)
        const cartIdParts = cart_id.split('_');
        if (cartIdParts.length < 2) {
            console.error('Invalid cart_id format:', cart_id);
            return {
                statusCode: 400,
                body: JSON.stringify({ 
                    success: false, 
                    message: 'Invalid cart_id format' 
                })
            };
        }
        
        const userId = cartIdParts[1];
        
        // Find the transaction by reference using scan (temporary solution)
        const transactionQuery = await dynamodb.send(new ScanCommand({
            TableName: process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev',
            FilterExpression: '#ref = :ref OR payTabsRef = :tranRef',
            ExpressionAttributeNames: {
                '#ref': 'reference'
            },
            ExpressionAttributeValues: {
                ':ref': cart_id,
                ':tranRef': tran_ref
            }
        }));
        
        if (!transactionQuery.Items || transactionQuery.Items.length === 0) {
            console.error('Transaction not found for reference:', cart_id);
            return {
                statusCode: 404,
                body: JSON.stringify({ 
                    success: false, 
                    message: 'Transaction not found' 
                })
            };
        }
        
        const transaction = transactionQuery.Items[0];
        const transactionId = transaction.transactionId;
        
        // Determine if payment was successful
        // PayTabs success codes: A = Authorized, 100 = Success
        const isSuccess = respStatus === 'A' || respCode === '100' || respMessage?.toLowerCase().includes('success');
        const newStatus = isSuccess ? 'SUCCESS' : 'FAILED';
        
        console.log(`Payment status for transaction ${transactionId}: ${newStatus} (respStatus: ${respStatus}, respCode: ${respCode})`);
        
        // If payment was successful, also update wallet balance
        if (isSuccess && transaction.type === 'TOPUP') {
            try {
                // Get current wallet
                const walletResult = await dynamodb.send(new GetCommand({
                    TableName: process.env.WALLETS_TABLE || 'WizzUser_wallets-dev',
                    Key: { userId: userId }
                }));
                
                if (walletResult.Item) {
                    const currentBalance = walletResult.Item.balance || 0;
                    const newBalance = currentBalance + transaction.amount;
                    
                    // Update wallet balance
                    await dynamodb.send(new UpdateCommand({
                        TableName: process.env.WALLETS_TABLE || 'WizzUser_wallets-dev',
                        Key: { userId: userId },
                        UpdateExpression: 'SET balance = :balance, updatedAt = :updatedAt',
                        ExpressionAttributeValues: {
                            ':balance': newBalance,
                            ':updatedAt': new Date().toISOString()
                        }
                    }));
                    
                    console.log(`Wallet balance updated for user ${userId}: ${currentBalance} -> ${newBalance}`);
                }
            } catch (walletError) {
                console.error('Failed to update wallet balance:', walletError);
                // Don't fail the whole webhook if wallet update fails
            }
        }
        
        // Update transaction status
        await dynamodb.send(new UpdateCommand({
            TableName: process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev',
            Key: {
                userId: userId,
                transactionId: transactionId
            },
            UpdateExpression: 'SET #status = :status, payTabsRef = :tranRef, respCode = :respCode, respMessage = :respMessage, acquirerRRN = :rrn, completedAt = :completedAt',
            ExpressionAttributeNames: {
                '#status': 'status'
            },
            ExpressionAttributeValues: {
                ':status': newStatus,
                ':tranRef': tran_ref,
                ':respCode': respCode,
                ':respMessage': respMessage,
                ':rrn': acquirerRRN || '',
                ':completedAt': new Date().toISOString()
            }
        }));
        
        // If payment was successful, update wallet balance
        if (isSuccess && transaction.type === 'TOPUP') {
            try {
                await dynamodb.send(new UpdateCommand({
                    TableName: process.env.WALLETS_TABLE || 'WizzUser_wallets-dev',
                    Key: {
                        userId: userId
                    },
                    UpdateExpression: 'SET balance = balance + :amount, updatedAt = :updatedAt',
                    ExpressionAttributeValues: {
                        ':amount': parseFloat(cart_amount),
                        ':updatedAt': new Date().toISOString()
                    }
                }));
                
                console.log(`Wallet balance updated for user ${userId}, added ${cart_amount} ${cart_currency}`);
                
                // Create a SUCCESS transaction record for audit
                const successTransactionId = `${transactionId}_SUCCESS`;
                const successTransaction = {
                    userId: userId,
                    transactionId: successTransactionId,
                    type: 'TOPUP_SUCCESS',
                    amount: parseFloat(cart_amount),
                    currency: cart_currency,
                    status: 'SUCCESS',
                    reference: cart_id,
                    payTabsRef: tran_ref,
                    description: `شحن ناجح للمحفظة - ${cart_amount} ${cart_currency}`,
                    timestamp: new Date().toISOString(),
                    createdAt: new Date().toISOString()
                };
                
                await dynamodb.put({
                    TableName: process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev',
                    Item: successTransaction
                }).promise();
                
            } catch (walletError) {
                console.error('Error updating wallet balance:', walletError);
                // Even if wallet update fails, we acknowledge the webhook
                // We'll handle this in a separate process
            }
        }
        
        // Always return 200 to PayTabs to acknowledge receipt
        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                success: true,
                message: 'Webhook processed successfully',
                transactionId: transactionId,
                status: newStatus
            })
        };
        
    } catch (error) {
        console.error('PayTabs Webhook Error:', error);
        
        // Still return 200 to avoid PayTabs retrying
        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                success: false,
                message: 'Webhook processing error',
                error: error.message
            })
        };
    }
};
