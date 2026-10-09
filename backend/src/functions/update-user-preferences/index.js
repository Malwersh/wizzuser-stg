const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const dynamodb = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('Update User Preferences Event:', JSON.stringify(event, null, 2));
    
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

        // Check if user exists first
        const getUserParams = {
            TableName: process.env.USERS_TABLE || 'WizzUser_users_dev',
            Key: {
                userId: userId
            }
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
        if (requestBody.notification_settings) {
            updateExpressionParts.push('notification_settings = :notification_settings');
            expressionAttributeValues[':notification_settings'] = requestBody.notification_settings;
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

        console.log('DynamoDB Update Params:', JSON.stringify(updateParams, null, 2));
        
        // Update the user preferences
        const result = await dynamodb.send(new UpdateCommand(updateParams));
        
        // Format the response data
        const updatedUser = {
            id: result.Attributes.userId,
            language_preference: result.Attributes.language_preference,
            country_preference: result.Attributes.country_preference,
            notification_settings: result.Attributes.notification_settings,
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
            statusCode: 500,
            headers,
            body: JSON.stringify({
                error: 'Internal server error',
                message: error.message
            })
        };
    }
};
