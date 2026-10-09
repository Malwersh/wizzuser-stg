// Simple test version of the CreateOrder function
exports.handler = async (event) => {
    console.log('Simple handler called');
    console.log('Event:', JSON.stringify(event, null, 2));
    
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
        
        return {
            statusCode: 200,
            headers: headers,
            body: JSON.stringify({
                message: 'Simple handler working',
                success: true,
                receivedData: event.body ? JSON.parse(event.body) : null
            })
        };
        
    } catch (error) {
        console.error('Error in simple handler:', error);
        
        return {
            statusCode: 500,
            headers: headers,
            body: JSON.stringify({
                error: 'Simple handler failed',
                message: error.message,
                success: false
            })
        };
    }
};
