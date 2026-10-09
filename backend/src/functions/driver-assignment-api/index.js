/**
 * Driver Assignment API Lambda Function
 * 
 * Handles driver interactions with the assignment system:
 * - Get available offers
 * - Accept/reject offers
 * - Update driver status
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');
const { getDriverOffers, respondToOffer } = require('/opt/nodejs/driver-assignment/offer-entity');
const { updateDriverStatus, getDriverStatus } = require('/opt/nodejs/driver-assignment/driver-status-manager');

const dynamoDbClient = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(dynamoDbClient);

/**
 * Lambda handler for driver assignment API
 */
exports.handler = async (event) => {
    console.log('📨 Event received:', JSON.stringify(event, null, 2));
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    };

    try {
        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: headers,
                body: ''
            };
        }

        const { httpMethod, path, pathParameters, queryStringParameters } = event;
        const body = event.body ? JSON.parse(event.body) : {};

        // Extract driver ID from path or body
        const driverId = pathParameters?.driverId || body.driverId;
        
        if (!driverId) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Driver ID is required'
                })
            };
        }

        // Route requests based on path and method
        if (path.includes('/offers') && httpMethod === 'GET') {
            // GET /driver/{driverId}/offers - Get available offers
            return await handleGetOffers(driverId, queryStringParameters, headers);
            
        } else if (path.includes('/offers/respond') && httpMethod === 'POST') {
            // POST /driver/{driverId}/offers/respond - Respond to offer
            return await handleRespondToOffer(driverId, body, headers);
            
        } else if (path.includes('/status') && httpMethod === 'PUT') {
            // PUT /driver/{driverId}/status - Update driver status
            return await handleUpdateStatus(driverId, body, headers);
            
        } else if (path.includes('/status') && httpMethod === 'GET') {
            // GET /driver/{driverId}/status - Get driver status
            return await handleGetStatus(driverId, headers);
            
        } else {
            return {
                statusCode: 404,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Endpoint not found'
                })
            };
        }

    } catch (error) {
        console.error('❌ API Error:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                success: false,
                message: 'Internal server error',
                error: process.env.NODE_ENV === 'development' ? error.message : undefined
            })
        };
    }
};

/**
 * Handle getting available offers for a driver
 */
async function handleGetOffers(driverId, queryParams, headers) {
    try {
        console.log(`📋 Getting offers for driver: ${driverId}`);
        
        const limit = parseInt(queryParams?.limit || '10');
        const status = queryParams?.status || 'pending';
        
        const result = await getDriverOffers(driverId, { limit, status });
        
        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                success: true,
                offers: result.offers,
                pagination: result.pagination,
                message: `Found ${result.offers.length} available offers`
            })
        };

    } catch (error) {
        console.error('❌ Error getting offers:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                success: false,
                message: 'Failed to get offers',
                error: error.message
            })
        };
    }
}

/**
 * Handle driver response to an offer
 */
async function handleRespondToOffer(driverId, body, headers) {
    try {
        const { offerId, response, location } = body;
        
        if (!offerId || !response) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Offer ID and response are required'
                })
            };
        }

        if (!['accept', 'reject'].includes(response)) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Response must be "accept" or "reject"'
                })
            };
        }

        console.log(`💬 Driver ${driverId} responding to offer ${offerId}: ${response}`);
        
        const result = await respondToOffer(offerId, driverId, response, { location });
        
        if (result.success) {
            return {
                statusCode: 200,
                headers: headers,
                body: JSON.stringify({
                    success: true,
                    message: result.message,
                    response: result.response,
                    assignmentConfirmed: result.assignmentConfirmed
                })
            };
        } else {
            return {
                statusCode: 409,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: result.message,
                    reason: result.reason
                })
            };
        }

    } catch (error) {
        console.error('❌ Error responding to offer:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                success: false,
                message: 'Failed to process response',
                error: error.message
            })
        };
    }
}

/**
 * Handle updating driver status
 */
async function handleUpdateStatus(driverId, body, headers) {
    try {
        const { status, location, vehicleInfo } = body;
        
        if (!status) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Status is required'
                })
            };
        }

        console.log(`🚗 Updating driver ${driverId} status to: ${status}`);
        
        const result = await updateDriverStatus(driverId, status, { location, vehicleInfo });
        
        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                success: true,
                message: 'Driver status updated successfully',
                status: result.status,
                lastUpdate: result.lastUpdate
            })
        };

    } catch (error) {
        console.error('❌ Error updating driver status:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                success: false,
                message: 'Failed to update status',
                error: error.message
            })
        };
    }
}

/**
 * Handle getting driver status
 */
async function handleGetStatus(driverId, headers) {
    try {
        console.log(`📊 Getting status for driver: ${driverId}`);
        
        const result = await getDriverStatus(driverId);
        
        if (result) {
            return {
                statusCode: 200,
                headers: headers,
                body: JSON.stringify({
                    success: true,
                    driver: result,
                    message: 'Driver status retrieved successfully'
                })
            };
        } else {
            return {
                statusCode: 404,
                headers: headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Driver not found'
                })
            };
        }

    } catch (error) {
        console.error('❌ Error getting driver status:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                success: false,
                message: 'Failed to get driver status',
                error: error.message
            })
        };
    }
}
