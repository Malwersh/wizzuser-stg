const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { v4: uuidv4 } = require('uuid');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(client);

// Table names from environment
const WALLETS_TABLE = process.env.WALLETS_TABLE || 'WizzUser_wallets-dev';
const TRANSACTIONS_TABLE = process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev';

// Simple UUID generator function
function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        const r = Math.random() * 16 | 0;
        const v = c == 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

exports.handler = async (event) => {
    console.log('Wallet Init Event:', JSON.stringify(event, null, 2));
    
    try {
        // Parse request body
        const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
        const { userId } = body;
        
        if (!userId) {
            return {
                statusCode: 400,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المستخدم مطلوب'
                })
            };
        }
        
        // Check if wallet already exists using GSI
        const checkParams = {
            TableName: WALLETS_TABLE,
            IndexName: 'userId-index',
            KeyConditionExpression: 'userId = :userId',
            ExpressionAttributeValues: {
                ':userId': userId
            }
        };
        
        const existingWallet = await dynamodb.send(new QueryCommand(checkParams));
        
        if (existingWallet.Items && existingWallet.Items.length > 0) {
            const wallet = existingWallet.Items[0];
            return {
                statusCode: 200,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: true,
                    message: 'المحفظة موجودة بالفعل',
                    data: {
                        walletId: wallet.walletId,
                        userId: wallet.userId,
                        balance: wallet.balance || 0,
                        currency: wallet.currency || 'IQD',
                        createdAt: wallet.createdAt,
                        updatedAt: wallet.updatedAt
                    }
                })
            };
        }

        // Create new wallet
        const walletId = uuidv4(); // Generate unique wallet ID
        const walletData = {
            walletId: walletId, // Primary key
            userId: userId,     // For GSI lookup
            balance: 0,
            currency: 'IQD',
            status: 'ACTIVE',
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            version: 1
        };

        const createParams = {
            TableName: WALLETS_TABLE,
            Item: walletData,
            ConditionExpression: 'attribute_not_exists(walletId)'
        };

        await dynamodb.send(new PutCommand(createParams));

        // Create initial transaction record
        const transactionId = uuidv4();
        const initialTransaction = {
            userId: userId,
            transactionId: transactionId,
            type: 'INIT',
            amount: 0,
            currency: 'IQD',
            status: 'SUCCESS',
            description: 'تهيئة المحفظة',
            timestamp: new Date().toISOString(),
            createdAt: new Date().toISOString()
        };

        const transactionParams = {
            TableName: TRANSACTIONS_TABLE,
            Item: initialTransaction
        };

        await dynamodb.send(new PutCommand(transactionParams));

        return {
            statusCode: 201,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
            },
            body: JSON.stringify({
                success: true,
                message: 'تم إنشاء المحفظة بنجاح',
                data: {
                    walletId: walletData.walletId,
                    userId: walletData.userId,
                    balance: walletData.balance,
                    currency: walletData.currency,
                    status: walletData.status,
                    createdAt: walletData.createdAt,
                    updatedAt: walletData.updatedAt
                }
            })
        };
        
    } catch (error) {
        console.error('Wallet Init Error:', error);
        return {
            statusCode: 500,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
            },
            body: JSON.stringify({
                success: false,
                message: 'حدث خطأ في إنشاء المحفظة',
                error: error.message
            })
        };
    }
};
