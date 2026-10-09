// PayTabs Callback Handler for WizzUser Wallet
// This function handles PayTabs payment callbacks and updates wallet balances

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const PAYTABS_CONFIG = require('./paytabs-config');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(client);

// Table names from environment
const WALLETS_TABLE = process.env.WALLETS_TABLE || 'WizzUser_wallets-dev';
const TRANSACTIONS_TABLE = process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev';

exports.handler = async (event) => {
    console.log('PayTabs Callback Event:', JSON.stringify(event, null, 2));
    
    try {
        // Parse the callback data from PayTabs
        let callbackData;
        
        if (event.body) {
            try {
                callbackData = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
            } catch (parseError) {
                console.error('Failed to parse callback body:', parseError);
                return createResponse(400, { success: false, message: 'Invalid callback data' });
            }
        } else if (event.queryStringParameters) {
            // PayTabs might send data as query parameters
            callbackData = event.queryStringParameters;
        } else {
            console.error('No callback data received');
            return createResponse(400, { success: false, message: 'No callback data' });
        }
        
        console.log('[PayTabs Callback] Received data:', JSON.stringify(callbackData, null, 2));
        
        // Extract essential callback information
        const {
            tran_ref,
            cart_id,
            respStatus,
            respCode,
            respMessage,
            acquirerMessage,
            acquirerRRN,
            cartAmount,
            cartCurrency,
            tranRef
        } = callbackData;
        
        // Use tran_ref or tranRef (PayTabs sends different field names sometimes)
        const transactionRef = tran_ref || tranRef;
        
        if (!transactionRef || !cart_id) {
            console.error('[PayTabs Callback] Missing required fields:', { tran_ref: transactionRef, cart_id });
            return createResponse(400, { 
                success: false, 
                message: 'Missing transaction reference or cart ID' 
            });
        }
        
        // Extract userId from cart_id (format: TOPUP-{userId_prefix}-{timestamp})
        const cartIdParts = cart_id.split('-');
        if (cartIdParts.length < 2 || cartIdParts[0] !== 'TOPUP') {
            console.error('[PayTabs Callback] Invalid cart_id format:', cart_id);
            return createResponse(400, { 
                success: false, 
                message: 'Invalid cart ID format' 
            });
        }
        
        // Find the transaction in database by cart_id/reference
        const transactionQuery = await dynamodb.send(new GetCommand({
            TableName: TRANSACTIONS_TABLE,
            IndexName: 'ReferenceIndex', // Assuming there's a GSI on reference field
            Key: { reference: cart_id }
        }));
        
        // If GSI doesn't exist, we'll need to scan (less efficient but works)
        let transaction = transactionQuery.Item;
        if (!transaction) {
            console.log('[PayTabs Callback] Transaction not found by reference, searching by tran_ref...');
            // Alternative: scan for transaction with matching PayTabs reference
            const scanParams = {
                TableName: TRANSACTIONS_TABLE,
                FilterExpression: 'payTabsRef = :ref OR payTabsTranRef = :ref OR reference = :cartId',
                ExpressionAttributeValues: {
                    ':ref': transactionRef,
                    ':cartId': cart_id
                }
            };
            
            const scanResult = await dynamodb.scan(scanParams).promise();
            if (scanResult.Items && scanResult.Items.length > 0) {
                transaction = scanResult.Items[0];
            }
        }
        
        if (!transaction) {
            console.error('[PayTabs Callback] Transaction not found for cart_id:', cart_id);
            return createResponse(404, { 
                success: false, 
                message: 'Transaction not found' 
            });
        }
        
        console.log('[PayTabs Callback] Found transaction:', transaction);
        
        // Determine payment status based on PayTabs response
        let paymentStatus = 'FAILED';
        let statusReason = respMessage || 'Payment failed';
        
        // PayTabs success codes (check PayTabs documentation for exact codes)
        const successCodes = ['100', '001', '000']; // Common success codes
        const isSuccessful = successCodes.includes(respCode) || respStatus === 'A';
        
        if (isSuccessful) {
            paymentStatus = 'COMPLETED';
            statusReason = 'Payment completed successfully';
            
            console.log('[PayTabs Callback] Payment successful, updating wallet...');
            
            // Update wallet balance
            const userId = transaction.userId;
            const amount = parseFloat(transaction.amount);
            
            try {
                await dynamodb.send(new UpdateCommand({
                    TableName: WALLETS_TABLE,
                    Key: { userId: userId },
                    UpdateExpression: 'SET balance = if_not_exists(balance, :zero) + :amount, lastTopUp = :now, updatedAt = :now',
                    ExpressionAttributeValues: {
                        ':amount': amount,
                        ':zero': 0,
                        ':now': new Date().toISOString()
                    }
                }));
                
                console.log(`[PayTabs Callback] Wallet updated: userId=${userId}, amount=+${amount}`);
            } catch (walletError) {
                console.error('[PayTabs Callback] Failed to update wallet:', walletError);
                // Don't fail the callback, but log the error
                statusReason += ' (Warning: Wallet update failed)';
            }
        } else {
            console.log('[PayTabs Callback] Payment failed:', { respCode, respStatus, respMessage });
        }
        
        // Update transaction status
        await dynamodb.send(new UpdateCommand({
            TableName: TRANSACTIONS_TABLE,
            Key: {
                userId: transaction.userId,
                transactionId: transaction.transactionId
            },
            UpdateExpression: 'SET #status = :status, statusReason = :reason, payTabsResponse = :response, completedAt = :now, acquirerRRN = :rrn',
            ExpressionAttributeNames: {
                '#status': 'status'
            },
            ExpressionAttributeValues: {
                ':status': paymentStatus,
                ':reason': statusReason,
                ':response': callbackData,
                ':now': new Date().toISOString(),
                ':rrn': acquirerRRN || null
            }
        }));
        
        console.log(`[PayTabs Callback] Transaction updated: ${transaction.transactionId} -> ${paymentStatus}`);
        
        // Return success response to PayTabs
        return createResponse(200, {
            success: true,
            message: 'Callback processed successfully',
            transactionId: transaction.transactionId,
            status: paymentStatus
        });
        
    } catch (error) {
        console.error('[PayTabs Callback] Error:', error);
        
        // Return error response
        return createResponse(500, {
            success: false,
            message: 'Internal server error',
            error: error.message
        });
    }
};

// Helper function to create HTTP response
function createResponse(statusCode, body) {
    return {
        statusCode: statusCode,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,Authorization',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
        },
        body: JSON.stringify(body)
    };
}
