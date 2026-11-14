const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, TransactWriteCommand } = require('@aws-sdk/lib-dynamodb');
const {writeContext}=require('../create-order/guarded-write');
const {createHash}=require('node:crypto');
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
    console.log('Wallet initialization request', {requestId:event.requestContext?.requestId});
    
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
        
        const write=await writeContext(dynamodb,event,userId);
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
        // Existing wallets keep their IDs. New initialization uses a stable ID
        // so two concurrent requests cannot create two wallets for one profile.
        const walletId = 'wallet_' + createHash('sha256').update(userId).digest('hex').slice(0,32);
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

        transactionParams.ConditionExpression='attribute_not_exists(transactionId)';
        await dynamodb.send(new TransactWriteCommand({TransactItems:[write.fence,{Put:createParams},{Put:transactionParams}]}));

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
            statusCode: error.statusCode || (error.name==='TransactionCanceledException'?409:500),
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
