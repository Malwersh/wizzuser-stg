"use strict";
// functions/get-business-working-hours/index.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
const lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
const client = new client_dynamodb_1.DynamoDBClient({});
const docClient = lib_dynamodb_1.DynamoDBDocumentClient.from(client);
const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
};
const handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    try {
        // Handle OPTIONS request for CORS
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers,
                body: '',
            };
        }
        // Get business ID from path parameters
        const businessId = event.pathParameters?.businessId;
        if (!businessId) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    success: false,
                    message: 'Business ID is required',
                }),
            };
        }
        console.log(`Fetching working hours for business: ${businessId}`);
        // Query working hours from DynamoDB
        const command = new lib_dynamodb_1.QueryCommand({
            TableName: 'WhizzMerchants_BusinessWorkingHours',
            KeyConditionExpression: 'businessId = :businessId',
            ExpressionAttributeValues: {
                ':businessId': businessId,
            },
        });
        const result = await docClient.send(command);
        console.log('DynamoDB query result:', JSON.stringify(result, null, 2));
        if (!result.Items || result.Items.length === 0) {
            console.log('No working hours found for business:', businessId);
            return {
                statusCode: 200,
                headers,
                body: JSON.stringify({
                    success: true,
                    workingHours: [],
                    message: 'No working hours found for this business',
                }),
            };
        }
        // Transform the DynamoDB items and organize by weekday
        const workingHoursArray = result.Items.map(item => ({
            business_id: item.businessId,
            weekday: item.weekday,
            opening: item.opening,
            closing: item.closing,
            isClosed: item.isClosed || false, // 🔥 إضافة حقل isClosed
            updated_at: item.updatedAt,
        }));

        // Also create an object format for easier access
        const workingHoursObject = {};
        workingHoursArray.forEach(item => {
            workingHoursObject[item.weekday.toLowerCase()] = {
                opening: item.opening,
                closing: item.closing,
                isClosed: item.isClosed,
                isOpen: !item.isClosed && item.opening && item.closing && 
                       item.opening !== 'closed' && item.closing !== 'closed',
            };
        });

        console.log(`Found ${workingHoursArray.length} working hour entries`);
        
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                businessId: businessId,
                workingHours: workingHoursArray, // Array format for compatibility
                working_hours: workingHoursObject, // Object format for new features  
                count: workingHoursArray.length,
            }),
        };
    }
    catch (error) {
        console.error('Error fetching working hours:', error);
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({
                success: false,
                message: 'Internal server error',
                error: process.env.NODE_ENV === 'development' ? error.message : undefined,
            }),
        };
    }
};
exports.handler = handler;
