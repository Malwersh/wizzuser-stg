const {storefrontFacts}=require('../shared/storefront-facts-170');
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
function getLocalClock(timezone, now = new Date()) {
    let parts;
    try {
        parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, weekday: 'long', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
    } catch (_) {
        parts = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Baghdad', weekday: 'long', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
    }
    const value = type => parts.find(p => p.type === type).value;
    return { weekday: value('weekday'), hm: value('hour') + ':' + value('minute') };
}
function getTodayWeekday(timezone) { return getLocalClock(timezone).weekday; }
function getCurrentHM(timezone) { return getLocalClock(timezone).hm; }
async function getTodayWorkingWindow(businessId, timezone) {
    const clock = getLocalClock(timezone);
    try {
        const query = new lib_dynamodb_1.QueryCommand({
            TableName: WORKING_HOURS_TABLE,
            KeyConditionExpression: 'businessId = :bid',
            ExpressionAttributeValues: { ':bid': businessId },
            ConsistentRead: true
        });
        const result = await docClient.send(query);
        const rows = result.Items || [];
        const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const previousDay = days[(days.indexOf(clock.weekday) + 6) % 7];
        const rowFor = day => rows.find(row => String(row.weekday || row.day).toLowerCase() === day.toLowerCase());
        const valid = row => row && row.isClosed !== true && /^([01]\d|2[0-3]):[0-5]\d$/.test(row.opening) && /^([01]\d|2[0-3]):[0-5]\d$/.test(row.closing) && row.opening !== row.closing;
        const today = rowFor(clock.weekday), previous = rowFor(previousDay);
        let active;
        if (valid(today) && (today.opening < today.closing ? clock.hm >= today.opening && clock.hm < today.closing : clock.hm >= today.opening)) active = today;
        if (!active && valid(previous) && previous.opening > previous.closing && clock.hm < previous.closing) active = previous;
        const displayed = active || today;
        return { isOpen: !!active, opening: displayed?.opening || null, closing: displayed?.closing || null, weekday: active && active === previous ? previousDay : clock.weekday };
    } catch (e) {
        console.log('Working hours lookup failed', { name: e.name });
        return { isOpen: false, opening: null, closing: null, weekday: clock.weekday };
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
            business_name: result.Item.businessName || result.Item.business_name,
            address: result.Item.address,
            business_photo_url: result.Item.businessPhotoUrl || result.Item.business_photo_url,
            business_type: result.Item.businessType || result.Item.business_type,
            businessTypeId: result.Item.businessTypeId || null,
            publishedCuisineIds: result.Item.publishedCuisineIds || [],
            phone: result.Item.phoneNumber || result.Item.phone_number,
            email: result.Item.email,
            ...storefrontFacts(result.Item),


            minimum_order: result.Item.minimum_order || 0,
            is_active: result.Item.is_active !== false,
            created_at: result.Item.createdAt || result.Item.created_at,
            updated_at: result.Item.updatedAt || result.Item.updated_at,
            owner_name: result.Item.ownerName || result.Item.owner_name,
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
