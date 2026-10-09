"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
const lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
const client = new client_dynamodb_1.DynamoDBClient({});
const docClient = lib_dynamodb_1.DynamoDBDocumentClient.from(client);
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
const WORKING_HOURS_TABLE = process.env.WORKING_HOURS_TABLE || 'WhizzMerchants_BusinessWorkingHours';
const DEFAULT_TIMEZONE = process.env.DEFAULT_TIMEZONE || 'Asia/Baghdad';
function getTodayWeekday(timezone) {
    try {
        const now = new Date();
        const local = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
        return local.toLocaleDateString('en-US', { weekday: 'long', timeZone: timezone });
    }
    catch (_a) {
        return new Date().toLocaleDateString('en-US', { weekday: 'long' });
    }
}
function getCurrentHM(timezone) {
    try {
        const now = new Date();
        const local = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
        return local.toTimeString().slice(0, 5); // HH:MM
    }
    catch (_a) {
        return new Date().toTimeString().slice(0, 5);
    }
}
async function getTodayWorkingWindow(businessId, timezone) {
    try {
        const weekday = getTodayWeekday(timezone);
        const query = new lib_dynamodb_1.QueryCommand({
            TableName: WORKING_HOURS_TABLE,
            KeyConditionExpression: 'business_id = :bid',
            ExpressionAttributeValues: { ':bid': businessId }
        });
        const result = await docClient.send(query);
        const items = (result.Items || []);
        const today = items.find((x) => (x.weekday === weekday) || (x.day === weekday));
        if (!today || !today.opening || !today.closing) {
            return { isOpen: false, opening: null, closing: null, weekday };
        }
        const nowHM = getCurrentHM(timezone);
        const isOpen = nowHM >= String(today.opening).slice(0, 5) && nowHM < String(today.closing).slice(0, 5);
        return { isOpen, opening: today.opening, closing: today.closing, weekday };
    }
    catch (e) {
        console.log('⚠️ Working hours lookup failed', e);
        return { isOpen: false, opening: null, closing: null, weekday: getTodayWeekday(timezone) };
    }
}
function deriveStatus(acceptingOrders, withinHours) {
    if (!withinHours)
        return { currentStatus: 'closed', isClosed: true, isAvailableNow: false, statusMessage: 'مغلق' };
    if (!acceptingOrders)
        return { currentStatus: 'offline', isClosed: false, isAvailableNow: false, statusMessage: 'مشغول' };
    return { currentStatus: 'online', isClosed: false, isAvailableNow: true };
}
const handler = async (event) => {
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS',
    };
    try {
        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers,
                body: '',
            };
        }
        const businessId = event.pathParameters?.businessId;
        if (!businessId) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    error: 'Business ID is required',
                    message: 'معرف المطعم مطلوب'
                }),
            };
        }
        console.log(`Fetching business with ID: ${businessId}`);
        const command = new lib_dynamodb_1.GetCommand({
            TableName: BUSINESSES_TABLE,
            Key: {
                businessId: businessId,
            },
        });
        const result = await docClient.send(command);
        if (!result.Item) {
            return {
                statusCode: 404,
                headers,
                body: JSON.stringify({
                    error: 'Business not found',
                    message: 'المطعم غير موجود'
                }),
            };
        }
        // Transform the DynamoDB item to match frontend expectations
        const business = {
            business_id: result.Item.businessId || result.Item.business_id,
            business_name: result.Item.business_name,
            address: result.Item.address,
            business_photo_url: result.Item.business_photo_url,
            business_type: result.Item.business_type,
            phone: result.Item.phone_number,
            email: result.Item.email,
            rating: result.Item.rating || 4.2,
            delivery_time: result.Item.delivery_time || '30-45 دقيقة',
            delivery_fee: result.Item.delivery_fee || '5000',
            minimum_order: result.Item.minimum_order || 0,
            is_active: result.Item.is_active !== false,
            created_at: result.Item.created_at,
            updated_at: result.Item.updated_at,
            owner_name: result.Item.owner_name,
            status: result.Item.status,
            // إضافة الإحداثيات الضرورية لحساب المسافة
            latitude: result.Item.latitude,
            longitude: result.Item.longitude,
        };

        // Derive live availability
        const timezone = result.Item.timezone || DEFAULT_TIMEZONE;
        const acceptingOrders = result.Item.acceptingOrders === true;
        const todayWindow = await getTodayWorkingWindow(business.business_id, timezone);
        const withinHours = todayWindow.isOpen === true;
        const { currentStatus, isClosed, isAvailableNow, statusMessage } = deriveStatus(acceptingOrders, withinHours);

        const enriched = Object.assign({}, business, {
            acceptingOrders,
            isClosed,
            isAvailableNow,
            currentStatus,
            statusMessage,
            workingHoursToday: todayWindow.opening && todayWindow.closing ? {
                weekday: todayWindow.weekday,
                opening: todayWindow.opening,
                closing: todayWindow.closing
            } : undefined
        });
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                business: enriched
            }),
        };
    }
    catch (error) {
        console.error('Error fetching business:', error);
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({
                error: 'Internal server error',
                message: 'خطأ في الخادم الداخلي'
            }),
        };
    }
};
exports.handler = handler;
