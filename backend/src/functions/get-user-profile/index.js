const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ 
    region: 'us-east-1'
});
const dynamodb = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('Get User Profile Event:', JSON.stringify(event, null, 2));
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    };

    // Handle CORS preflight
    if (event.httpMethod === 'OPTIONS') {
        return {
            statusCode: 200,
            headers,
            body: ''
        };
    }

    try {
        const userId = event.pathParameters?.user_id;
        
        if (!userId) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    error: 'Missing user_id parameter'
                })
            };
        }

        // Query DynamoDB for user profile
        const params = {
            TableName: process.env.USERS_TABLE || 'WizzUser_users_dev',
            Key: {
                userId: userId
            }
        };

        console.log('DynamoDB Query Params:', params);
        const result = await dynamodb.send(new GetCommand(params));
        
        if (!result.Item) {
            return {
                statusCode: 404,
                headers,
                body: JSON.stringify({
                    error: 'User not found'
                })
            };
        }

        // Return user profile data
        const userProfile = {
            id: result.Item.userId,
            name: result.Item.name || result.Item.full_name,
            email: result.Item.email,
            phone: result.Item.phone,
            birthdate: result.Item.birth_date || result.Item.birthdate,
            gender: result.Item.gender || 'male',
            marketing_consent: result.Item.marketing_consent || false,
            newsletter_subscription: result.Item.newsletter_subscription || false,
            created_at: result.Item.created_at,
            updated_at: result.Item.updated_at
        };

        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                data: userProfile
            })
        };

    } catch (error) {
        console.error('Error fetching user profile:', error);
        
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({
                error: 'Internal server error',
                message: error.message
            })
        };
    }
};
