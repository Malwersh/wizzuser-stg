const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(client);

// Table name from environment
const WALLETS_TABLE = process.env.WALLETS_TABLE || 'foodapp-wallets-dev';

exports.handler = async (event) => {
    console.log('Get Wallet Balance Event:', JSON.stringify(event, null, 2));
    
    try {
        const userId = event.queryStringParameters?.userId;
        
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
        
        // Get wallet balance using GSI
        const walletResult = await dynamodb.send(new QueryCommand({
            TableName: WALLETS_TABLE,
            IndexName: 'userId-index',
            KeyConditionExpression: 'userId = :userId',
            ExpressionAttributeValues: {
                ':userId': userId
            }
        }));
        
        if (!walletResult.Items || walletResult.Items.length === 0) {
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
        
        const wallet = walletResult.Items[0]; // Get first wallet found
        
        return {
            statusCode: 200,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
            },
            body: JSON.stringify({
                success: true,
                balance: wallet.balance,
                currency: wallet.currency,
                isActive: wallet.status === 'ACTIVE',
                updatedAt: wallet.updatedAt
            })
        };
        
    } catch (error) {
        console.error('Get Balance Error:', error);
        return {
            statusCode: 500,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
            },
            body: JSON.stringify({
                success: false,
                message: 'حدث خطأ في الحصول على الرصيد',
                error: error.message
            })
        };
    }
};
