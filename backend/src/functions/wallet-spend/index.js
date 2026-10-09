const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { v4: uuidv4 } = require('uuid');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('Wallet Spend Event:', JSON.stringify(event, null, 2));
    
    try {
        const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
        const { userId, amount, orderId, description } = body;
        
        if (!userId || !amount || amount <= 0) {
            return {
                statusCode: 400,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المستخدم والمبلغ مطلوبان'
                })
            };
        }
        
        // Get current wallet balance
        const walletResult = await dynamodb.send(new GetCommand({
            TableName: process.env.WALLETS_TABLE || 'WizzUser_wallets-dev',
            Key: { userId: userId }
        }));
        
        if (!walletResult.Item) {
            return {
                statusCode: 404,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: false,
                    message: 'المحفظة غير موجودة'
                })
            };
        }
        
        const currentBalance = walletResult.Item.balance;
        
        // Check if balance is sufficient
        if (currentBalance < amount) {
            return {
                statusCode: 400,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: false,
                    message: 'الرصيد غير كافٍ',
                    currentBalance: currentBalance,
                    requiredAmount: amount
                })
            };
        }
        
        // Generate transaction ID
        const transactionId = uuidv4();
        
        try {
            // Start transaction - deduct from wallet
            await dynamodb.send(new UpdateCommand({
                TableName: process.env.WALLETS_TABLE || 'WizzUser_wallets-dev',
                Key: { userId: userId },
                UpdateExpression: 'SET balance = balance - :amount, updatedAt = :updatedAt',
                ConditionExpression: 'balance >= :amount', // Ensure balance is still sufficient
                ExpressionAttributeValues: {
                    ':amount': amount,
                    ':updatedAt': new Date().toISOString()
                }
            }));
            
            // Record the spend transaction
            const spendTransaction = {
                userId: userId,
                transactionId: transactionId,
                type: 'SPEND',
                amount: amount,
                currency: walletResult.Item.currency || 'IQD',
                status: 'SUCCESS',
                orderId: orderId || null,
                description: description || `دفع مقابل طلب ${orderId || ''}`,
                timestamp: new Date().toISOString(),
                createdAt: new Date().toISOString()
            };
            
            await dynamodb.send(new PutCommand({
                TableName: process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev',
                Item: spendTransaction
            }));
            
            // Get updated balance
            const updatedWalletResult = await dynamodb.send(new GetCommand({
                TableName: process.env.WALLETS_TABLE || 'WizzUser_wallets-dev',
                Key: { userId: userId }
            }));
            
            return {
                statusCode: 200,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: true,
                    message: 'تم خصم المبلغ بنجاح',
                    transactionId: transactionId,
                    deductedAmount: amount,
                    previousBalance: currentBalance,
                    newBalance: updatedWalletResult.Item.balance,
                    currency: walletResult.Item.currency
                })
            };
            
        } catch (conditionalError) {
            // Handle case where balance became insufficient between check and deduction
            if (conditionalError.code === 'ConditionalCheckFailedException') {
                return {
                    statusCode: 400,
                    headers: {
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                    },
                    body: JSON.stringify({
                        success: false,
                        message: 'الرصيد غير كافٍ - تم تحديث الرصيد من جهة أخرى'
                    })
                };
            }
            throw conditionalError;
        }
        
    } catch (error) {
        console.error('Wallet Spend Error:', error);
        return {
            statusCode: 500,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
            },
            body: JSON.stringify({
                success: false,
                message: 'حدث خطأ في عملية الخصم',
                error: error.message
            })
        };
    }
};
