const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('Get Wallet Transactions Event:', JSON.stringify(event, null, 2));
    
    try {
        const userId = event.queryStringParameters?.userId;
        const limit = parseInt(event.queryStringParameters?.limit) || 20;
        const lastEvaluatedKey = event.queryStringParameters?.lastKey ? 
            JSON.parse(decodeURIComponent(event.queryStringParameters.lastKey)) : null;
        
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
        
        // Query transactions for user
        const queryParams = {
            TableName: process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev',
            KeyConditionExpression: 'userId = :userId',
            ExpressionAttributeValues: {
                ':userId': userId
            },
            ScanIndexForward: false, // Sort by transactionId in descending order (newest first)
            Limit: limit
        };
        
        if (lastEvaluatedKey) {
            queryParams.ExclusiveStartKey = lastEvaluatedKey;
        }
        
        const result = await dynamodb.send(new QueryCommand(queryParams));
        
        // Format transactions for frontend
        const transactions = result.Items.map(item => ({
            transactionId: item.transactionId,
            type: item.type,
            amount: item.amount,
            currency: item.currency,
            status: item.status,
            description: item.description,
            orderId: item.orderId,
            reference: item.reference,
            timestamp: item.timestamp,
            completedAt: item.completedAt,
            // Add type-specific formatting
            displayType: getDisplayType(item.type),
            displayAmount: formatDisplayAmount(item.type, item.amount),
            displayStatus: getDisplayStatus(item.status)
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
                transactions: transactions,
                count: transactions.length,
                lastEvaluatedKey: result.LastEvaluatedKey ? 
                    encodeURIComponent(JSON.stringify(result.LastEvaluatedKey)) : null,
                hasMore: !!result.LastEvaluatedKey
            })
        };
        
    } catch (error) {
        console.error('Get Transactions Error:', error);
        return {
            statusCode: 500,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
            },
            body: JSON.stringify({
                success: false,
                message: 'حدث خطأ في الحصول على المعاملات',
                error: error.message
            })
        };
    }
};

function getDisplayType(type) {
    const typeMap = {
        'INIT': 'تهيئة المحفظة',
        'TOPUP': 'شحن المحفظة',
        'TOPUP_SUCCESS': 'شحن ناجح',
        'SPEND': 'دفع',
        'REFUND': 'استرداد',
        'FAILED': 'عملية فاشلة'
    };
    return typeMap[type] || type;
}

function formatDisplayAmount(type, amount) {
    if (type === 'SPEND') {
        return `-${amount}`;
    } else if (type === 'TOPUP' || type === 'TOPUP_SUCCESS' || type === 'REFUND') {
        return `+${amount}`;
    }
    return amount;
}

function getDisplayStatus(status) {
    const statusMap = {
        'PENDING': 'في الانتظار',
        'SUCCESS': 'مكتملة',
        'FAILED': 'فاشلة'
    };
    return statusMap[status] || status;
}
