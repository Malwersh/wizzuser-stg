const {promotionConsent,notificationView}=require('../shared/customer-promotion-consent-449');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');
const { accountGuard } = require('../create-order/account-guard');
const { CognitoIdentityProviderClient, GetUserCommand } = require('@aws-sdk/client-cognito-identity-provider');
const cognito = new CognitoIdentityProviderClient({});

const client = new DynamoDBClient({ 
    region: 'us-east-1'
});
const dynamodb = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('Get profile request', {requestId:event.requestContext?.requestId});
    
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

        let profile;
        const guarded = await accountGuard({event, userId,
            pool:process.env.USER_POOL_ID, clientId:process.env.USER_POOL_CLIENT_ID,
            profilesTable:process.env.USERS_TABLE,
            getUser:token=>cognito.send(new GetUserCommand({AccessToken:token})),
            getProfile:async id=>{
                profile=(await dynamodb.send(new GetCommand({
                    TableName:process.env.USERS_TABLE, Key:{userId:id}, ConsistentRead:true
                }))).Item;
                return profile;
            }});
        if (!guarded.condition) throw Object.assign(new Error('AUTH_REQUIRED'), {statusCode:401});
        if (profile.cognitoSub && profile.cognitoSub !== guarded.sub) {
            throw Object.assign(new Error('ACCOUNT_MISMATCH'), {statusCode:403});
        }
        const result = {Item:profile};

        // Return user profile data
        const userProfile = {
            id: result.Item.userId,
            name: result.Item.name || result.Item.full_name,
            email: result.Item.email,
            phone: result.Item.phone,
            birthdate: result.Item.birth_date || result.Item.birthdate,
            gender: result.Item.gender || 'male',
            marketing_consent: promotionConsent(result.Item),
            newsletter_subscription: result.Item.newsletter_subscription || false,
            created_at: result.Item.created_at,
            updated_at: result.Item.updated_at,
            notification_settings: notificationView(result.Item),
            language_preference: result.Item.language_preference,
            country_preference: result.Item.country_preference
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
            statusCode: error.statusCode || 500,
            headers,
            body: JSON.stringify({
                error: error.statusCode ? error.message : 'PROFILE_READ_FAILED',
                message: error.statusCode ? error.message : 'PROFILE_READ_FAILED'
            })
        };
    }
};
