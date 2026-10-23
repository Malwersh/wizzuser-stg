/**
 * Lambda function to delete an address
 * دالة لحذف عنوان
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, DeleteCommand, QueryCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');

const {writeContext}=require('../create-order/guarded-write');
const client = new DynamoDBClient({ 
    region: 'us-east-1'
});
const dynamodb = DynamoDBDocumentClient.from(client);
function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

const TABLE_NAME = requireEnv('ADDRESSES_TABLE');

/**
 * CORS headers for responses
 */
const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'Content-Type': 'application/json; charset=utf-8'
};

/**
 * Set a new default address if needed
 */
async function setNewDefaultAddress(userId, deletedAddressId,write) {
    try {
        // Find other addresses for this user
        const queryParams = {
            TableName: TABLE_NAME,
            IndexName: 'userId-index',
            KeyConditionExpression: 'userId = :userId',
            ExpressionAttributeValues: {
                ':userId': userId
            },
            FilterExpression: 'addressId <> :deletedAddressId',
            ExpressionAttributeValues: {
                ':userId': userId,
                ':deletedAddressId': deletedAddressId
            },
            Limit: 1
        };

        const result = await dynamodb.send(new QueryCommand(queryParams));
        
        if (result.Items.length > 0) {
            // Set the first remaining address as default
            const newDefaultAddress = result.Items[0];
            const updateParams = {
                TableName: TABLE_NAME,
                Key: { addressId: newDefaultAddress.addressId },
                UpdateExpression: 'SET isDefault = :isDefault, updatedAt = :updatedAt',
                ExpressionAttributeValues: {
                    ':isDefault': 'true',
                    ':updatedAt': new Date().toISOString()
                }
            };
            
            await write('Update',{...updateParams,ConditionExpression:'attribute_exists(addressId) AND userId = :owner',ExpressionAttributeValues:{...updateParams.ExpressionAttributeValues,':owner':userId}});
            console.log(`✅ Set address ${newDefaultAddress.addressId} as new default`);
            return newDefaultAddress.addressId;
        }
        
        return null;
    } catch (error) {
        console.error('❌ Error setting new default address:', error);
        throw error;
    }
}

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
    console.log('Account mutation request', {requestId:event.requestContext?.requestId});

    try {
        // Handle CORS preflight
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: CORS_HEADERS,
                body: JSON.stringify({ message: 'CORS preflight successful' })
            };
        }

        // Extract parameters
        const userId = event.pathParameters?.user_id;
        const addressId = event.pathParameters?.address_id;
        
        console.log('👤 User ID:', userId);
        console.log('🏠 Address ID to delete:', addressId);

        if (!userId || !addressId) {
            return {
                statusCode: 400,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المستخدم ومعرف العنوان مطلوبان'
                })
            };
        }

        // First, verify that the address exists and belongs to the user
        const write=await writeContext(dynamodb,event,userId);
        const getParams = {
            TableName: TABLE_NAME,
            Key: { addressId: addressId }
        };

        const existingResult = await dynamodb.send(new GetCommand(getParams));
        
        if (!existingResult.Item) {
            return {
                statusCode: 404,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'العنوان غير موجود'
                })
            };
        }

        const addressToDelete = existingResult.Item;

        if (addressToDelete.userId !== userId) {
            return {
                statusCode: 403,
                headers: CORS_HEADERS,
                body: JSON.stringify({
                    success: false,
                    message: 'غير مخول لحذف هذا العنوان'
                })
            };
        }

        // Check if this is the default address
        const wasDefault = addressToDelete.isDefault === 'true' || addressToDelete.isDefault === true;

        // Delete the address
        const deleteParams = {
            TableName: TABLE_NAME,
            Key: { addressId: addressId }
        };

        await write('Delete',{...deleteParams,ConditionExpression:'attribute_exists(addressId) AND userId = :owner',ExpressionAttributeValues:{':owner':userId}});
        console.log(`✅ Address ${addressId} deleted successfully`);

        // If the deleted address was default, set another address as default
        let newDefaultAddressId = null;
        if (wasDefault) {
            newDefaultAddressId = await setNewDefaultAddress(userId, addressId,write);
        }

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: true,
                message: 'تم حذف العنوان بنجاح',
                data: {
                    deleted_address_id: addressId,
                    was_default: wasDefault,
                    new_default_address_id: newDefaultAddressId
                }
            })
        };

    } catch (error) {
        console.error('💥 Error deleting address:', error);
        
        return {
            statusCode: error.statusCode || (error.name==='TransactionCanceledException'?409:500),
            headers: CORS_HEADERS,
            body: JSON.stringify({
                success: false,
                message: 'خطأ في حذف العنوان',
                error: error.message
            })
        };
    }
};
