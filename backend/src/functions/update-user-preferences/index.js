const {promotionConsent,notificationView,fenceNotificationSnapshot}=require('../shared/customer-promotion-consent-449');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const {accountGuard}=require('../create-order/account-guard');
const {CognitoIdentityProviderClient,GetUserCommand}=require('@aws-sdk/client-cognito-identity-provider');
const cognito=new CognitoIdentityProviderClient({});

const client = new DynamoDBClient({});
const dynamodb = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('Update preferences request', {requestId:event.requestContext?.requestId});
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'PUT, OPTIONS',
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

        const guarded = await accountGuard({event,userId,pool:process.env.USER_POOL_ID,clientId:process.env.USER_POOL_CLIENT_ID,profilesTable:process.env.USERS_TABLE,
            getUser:token=>cognito.send(new GetUserCommand({AccessToken:token})),
            getProfile:async id=>(await dynamodb.send(new GetCommand({TableName:process.env.USERS_TABLE,Key:{userId:id},ConsistentRead:true}))).Item});
        if(!guarded.condition)throw Object.assign(Error('AUTH_REQUIRED'),{statusCode:401});
        // Parse request body
        let requestBody;
        try {
            requestBody = JSON.parse(event.body);
        } catch (e) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    error: 'Invalid JSON in request body'
                })
            };
        }

        if(!requestBody || typeof requestBody!=='object' || Array.isArray(requestBody))throw Object.assign(Error('INVALID_PREFERENCES'),{statusCode:400});

        // Check if user exists first
        const getUserParams = {
            TableName: process.env.USERS_TABLE || 'WizzUser_users_dev',
            Key: {
                userId: userId
            },
            ConsistentRead: true
        };

        console.log('Checking if user exists:', getUserParams);
        const userResult = await dynamodb.send(new GetCommand(getUserParams));
        
        if (!userResult.Item) {
            return {
                statusCode: 404,
                headers,
                body: JSON.stringify({
                    error: 'User not found'
                })
            };
        }

        // Prepare update expression
        const updateExpressionParts = [];
        const expressionAttributeValues = {};
        
        // Handle language preference update
        if (requestBody.language_preference || requestBody.languageCode) {
            const languageValue = requestBody.language_preference || requestBody.languageCode;
            updateExpressionParts.push('language_preference = :language_preference');
            expressionAttributeValues[':language_preference'] = languageValue;
        }

        // Handle country preference update
        if (requestBody.country_preference || requestBody.countryCode) {
            const countryValue = requestBody.country_preference || requestBody.countryCode;
            updateExpressionParts.push('country_preference = :country_preference');
            expressionAttributeValues[':country_preference'] = countryValue;
        }

        // Handle notification settings update
        if (Object.prototype.hasOwnProperty.call(requestBody, 'notification_settings')) {
            updateExpressionParts.push('notification_settings = :notification_settings');
            expressionAttributeValues[':notification_settings'] = require('./notification-settings').mergeNotificationSettings(userResult.Item.notification_settings, requestBody.notification_settings);
        }

        if(typeof requestBody.notification_settings?.promotion_notifications==='boolean'){
            updateExpressionParts.push('marketing_consent = :marketingConsent');
            expressionAttributeValues[':marketingConsent']=requestBody.notification_settings.promotion_notifications;
        }

        // Validate that at least one preference is provided
        if (updateExpressionParts.length === 0) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    error: 'At least one preference must be provided for update',
                    allowed_fields: ['language_preference', 'country_preference', 'notification_settings']
                })
            };
        }

        // Always update the updated_at timestamp
        updateExpressionParts.push('updated_at = :updated_at');
        expressionAttributeValues[':updated_at'] = new Date().toISOString();

        // Build the update expression
        const updateExpression = 'SET ' + updateExpressionParts.join(', ');

        const updateParams = {
            TableName: process.env.USERS_TABLE || 'WizzUser_users_dev',
            Key: {
                userId: userId
            },
            UpdateExpression: updateExpression,
            ExpressionAttributeValues: expressionAttributeValues,
            ReturnValues: 'ALL_NEW'
        };

        console.log('Updating customer preferences', {requestId:event.requestContext?.requestId});
        
        // Update the user preferences
        const fence=guarded.condition.ConditionCheck;
        updateParams.ConditionExpression=fence.ConditionExpression;
        updateParams.ExpressionAttributeNames=fence.ExpressionAttributeNames;
        Object.assign(updateParams.ExpressionAttributeValues,fence.ExpressionAttributeValues);
        if(Object.prototype.hasOwnProperty.call(requestBody,'notification_settings'))fenceNotificationSnapshot(updateParams,userResult.Item);
        const result = await dynamodb.send(new UpdateCommand(updateParams));
        
        // Format the response data
        const updatedUser = {
            id: result.Attributes.userId,
            language_preference: result.Attributes.language_preference,
            country_preference: result.Attributes.country_preference,
            notification_settings: notificationView(result.Attributes),
            marketing_consent: promotionConsent(result.Attributes),
            updated_at: result.Attributes.updated_at
        };

        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                message: 'User preferences updated successfully',
                data: updatedUser
            })
        };

    } catch (error) {
        console.error('Error updating user preferences:', error);
        
        return {
            statusCode: error.statusCode || (error.name==='ConditionalCheckFailedException'?409:500),
            headers,
            body: JSON.stringify({
                error: 'Internal server error',
                message: error.message
            })
        };
    }
};
