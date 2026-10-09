const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ 
    region: 'us-east-1'
});
const dynamodb = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
    console.log('Update User Profile Event:', JSON.stringify(event, null, 2));
    
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

        // Validate required fields (at least one field should be provided)
        const allowedFields = ['name', 'gender', 'birth_date', 'birthdate', 'marketing_consent', 'newsletter_subscription'];
        const providedFields = Object.keys(requestBody).filter(key => allowedFields.includes(key));
        
        if (providedFields.length === 0) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    error: 'At least one field must be provided for update',
                    allowed_fields: allowedFields
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
        const expressionAttributeNames = {};
        const expressionAttributeValues = {};
        
        // Handle name update
        if (requestBody.name) {
            updateExpressionParts.push('#name = :name');
            expressionAttributeNames['#name'] = 'name';
            expressionAttributeValues[':name'] = requestBody.name;
        }

        // Handle gender update
        if (requestBody.gender) {
            updateExpressionParts.push('gender = :gender');
            expressionAttributeValues[':gender'] = requestBody.gender;
        }

        // Handle birth_date update (supporting both birth_date and birthdate)
        const birthdate = requestBody.birth_date || requestBody.birthdate;
        if (birthdate) {
            updateExpressionParts.push('birth_date = :birth_date');
            expressionAttributeValues[':birth_date'] = birthdate;
        }

        // Handle marketing consent update
        if (typeof requestBody.marketing_consent === 'boolean') {
            updateExpressionParts.push('marketing_consent = :marketing_consent');
            expressionAttributeValues[':marketing_consent'] = requestBody.marketing_consent;
        }

        // Handle newsletter subscription update
        if (typeof requestBody.newsletter_subscription === 'boolean') {
            updateExpressionParts.push('newsletter_subscription = :newsletter_subscription');
            expressionAttributeValues[':newsletter_subscription'] = requestBody.newsletter_subscription;
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

        // Add ExpressionAttributeNames only if we have any
        if (Object.keys(expressionAttributeNames).length > 0) {
            updateParams.ExpressionAttributeNames = expressionAttributeNames;
        }

        console.log('DynamoDB Update Params:', JSON.stringify(updateParams, null, 2));
        
        // Update the user profile
        const result = await dynamodb.send(new UpdateCommand(updateParams));
        
        // Format the response data
        const updatedProfile = {
            id: result.Attributes.userId,
            name: result.Attributes.name || result.Attributes.full_name,
            email: result.Attributes.email,
            phone: result.Attributes.phone,
            birthdate: result.Attributes.birth_date || result.Attributes.birthdate,
            gender: result.Attributes.gender || 'male',
            marketing_consent: result.Attributes.marketing_consent || false,
            newsletter_subscription: result.Attributes.newsletter_subscription || false,
            created_at: result.Attributes.created_at,
            updated_at: result.Attributes.updated_at
        };

        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                message: 'User profile updated successfully',
                data: updatedProfile
            })
        };

    } catch (error) {
        console.error('Error updating user profile:', error);
        
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
