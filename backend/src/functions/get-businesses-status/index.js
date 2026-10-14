"use strict";
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });

const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
const WORKING_HOURS_TABLE = process.env.WORKING_HOURS_TABLE || 'WhizzMerchants_BusinessWorkingHours';
const DEFAULT_TIMEZONE = process.env.DEFAULT_TIMEZONE || 'Asia/Baghdad';

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type,Authorization',
      'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    },
    body: JSON.stringify(body)
  };
}

function parseBody(event) {
  try {
    if (!event || !event.body) return {};
    return typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
  } catch (_) { return {}; }
}

function getTodayWeekday(timezone) {
  try {
    const now = new Date();
    console.log(`⏰ getTodayWeekday: UTC time = ${now.toISOString()}, timezone = ${timezone}`);
    // 🔥 Fix: استخدام Intl.DateTimeFormat مباشرة بدلاً من parsing string
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      weekday: 'long'
    });
    const weekday = formatter.format(now);
    console.log(`⏰ getTodayWeekday: weekday in ${timezone} = ${weekday}`);
    return weekday;
  } catch (e) {
    console.log(`⏰ getTodayWeekday: ERROR = ${e.message}, falling back to local`);
    return new Date().toLocaleDateString('en-US', { weekday: 'long' });
  }
}

function getCurrentHM(timezone) {
  try {
    const now = new Date();
    console.log(`⏰ getCurrentHM: UTC time = ${now.toISOString()}, timezone = ${timezone}`);
    // استخدام Intl.DateTimeFormat للحصول على الوقت الصحيح بتوقيت المنطقة
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    });
    const parts = formatter.formatToParts(now);
    let hour = parts.find(p => p.type === 'hour').value;
    const minute = parts.find(p => p.type === 'minute').value;
    
    // 🔥 FIX: تطبيع hour=24 ليصبح hour=00 (منتصف الليل)
    if (hour === '24') {
      hour = '00';
      console.log(`⏰ getCurrentHM: NORMALIZED 24:xx to 00:xx`);
    }
    
    const result = `${hour}:${minute}`;
    console.log(`⏰ getCurrentHM: local time in ${timezone} = ${result}`);
    return result;
  } catch (e) {
    console.log(`⏰ getCurrentHM: ERROR = ${e.message}, falling back to server time`);
    // fallback: استخدام الوقت المحلي للسيرفر
    return new Date().toTimeString().slice(0, 5);
  }
}

async function getTodayWindow(businessId, timezone) {
  try {
    const weekday = getTodayWeekday(timezone);
    console.log(`[${businessId}] Looking for working hours - weekday: ${weekday}, table: ${WORKING_HOURS_TABLE}`);
    const res = await docClient.send(new QueryCommand({
        TableName: WORKING_HOURS_TABLE,
        KeyConditionExpression: 'businessId = :bid', // 🔥 تصحيح: businessId بدلاً من business_id
        ExpressionAttributeValues: { ':bid': businessId }
      }));
    const items = res.Items || [];
    console.log(`[${businessId}] Found ${items.length} working hour records:`, JSON.stringify(items));
    const today = items.find(x => (x.weekday === weekday) || (x.day === weekday));
    if (!today) {
      console.log(`[${businessId}] No working hours record found for ${weekday}`);
      return { isOpen: false, workingHoursToday: null };
    }
    
    // Check if today is marked as closed
    if (today.isClosed === true) {
      console.log(`[${businessId}] ${weekday} is marked as closed (isClosed=true)`);
      const workingHoursToday = {
        open: today.opening || 'closed',
        close: today.closing || 'closed',
        isClosed: true
      };
      return { isOpen: false, workingHoursToday };
    }
    
    // Validate opening/closing times exist
    if (!today.opening || !today.closing || today.opening === 'closed' || today.closing === 'closed') {
      console.log(`[${businessId}] Invalid opening/closing times for ${weekday}`);
      return { isOpen: false, workingHoursToday: null };
    }
    
    // Check if currently within working hours
    const nowHM = getCurrentHM(timezone);
    const openTime = String(today.opening).slice(0,5);
    const closeTime = String(today.closing).slice(0,5);
    
    // Detailed logging for debugging
    console.log(`[${businessId}] Time comparison debug:`);
    console.log(`  nowHM: "${nowHM}" (type: ${typeof nowHM}, length: ${nowHM.length})`);
    console.log(`  openTime: "${openTime}" (type: ${typeof openTime}, length: ${openTime.length})`);
    console.log(`  closeTime: "${closeTime}" (type: ${typeof closeTime}, length: ${closeTime.length})`);
    console.log(`  nowHM >= openTime: ${nowHM >= openTime}`);
    console.log(`  nowHM < closeTime: ${nowHM < closeTime}`);
    
    // 🔥 FIX: Handle times that cross midnight properly
    // For example: opening=00:00, closing=23:55 means open 24 hours (except 5 minutes)
    let isOpen;
    if (closeTime > openTime) {
      // Normal case: opens and closes same day (e.g., 08:00 - 22:00)
      isOpen = nowHM >= openTime && nowHM < closeTime;
    } else {
      // Crosses midnight: opens late, closes early next day (e.g., 22:00 - 02:00)
      isOpen = nowHM >= openTime || nowHM < closeTime;
    }
    
    console.log(`[${businessId}] ⏰ Crosses midnight check: ${closeTime <= openTime}, isOpen: ${isOpen}`);
    console.log(`[${businessId}] 🔧 FIXED VERSION 2.0 - Midnight handling enabled`);
    
    const workingHoursToday = {
      open: today.opening,
      close: today.closing,
      isClosed: false
    };
    console.log(`[${businessId}] 🕐 ${weekday}: ${openTime}-${closeTime}, now: ${nowHM}, isOpen: ${isOpen}`);
    console.log(`[${businessId}] 🔍 FINAL RESULT: { isOpen: ${isOpen}, workingHoursToday: ${JSON.stringify(workingHoursToday)} }`);
    return { isOpen, workingHoursToday };
  } catch (e) {
    console.log('Working hours lookup failed for', businessId, e?.message || e);
    return { isOpen: false, workingHoursToday: null };
  }
}

function deriveStatus(acceptingOrders, withinHours, isClosed) {
  // isClosed: مغلق يدوياً من Business (من جدول working hours)
  // withinHours: ضمن ساعات العمل (حسب الوقت الحالي)
  // acceptingOrders: يقبل طلبات (من جدول businesses)
  
  // 🎯 isAvailableNow = كل الشروط صحيحة
  const isAvailableNow = !isClosed && withinHours && acceptingOrders;
  
  // تحديد الحالة الظاهرة
  let currentStatus = 'closed';
  if (isClosed) {
    currentStatus = 'closed'; // مغلق يدوياً
  } else if (!withinHours) {
    currentStatus = 'closed'; // خارج ساعات العمل
  } else if (!acceptingOrders) {
    currentStatus = 'offline'; // مشغول
  } else {
    currentStatus = 'online'; // متاح
  }
  
  return { 
    currentStatus, 
    isClosed,           // حالة الإغلاق اليدوي فقط
    isWithinWorkingHours: withinHours, // ضمن ساعات العمل
    isAvailableNow      // متاح الآن (كل الشروط)
  };
}

exports.handler = async (event) => {
  console.log('🚀 LAMBDA VERSION: 3.0 - MIDNIGHT FIX DEPLOYED');
  if (event.httpMethod === 'OPTIONS') return jsonResponse(200, {});

  const body = parseBody(event);
  const businessIds = Array.isArray(body.businessIds) ? body.businessIds.filter(Boolean) : [];
  if (businessIds.length === 0) {
    return jsonResponse(400, { error: 'businessIds array is required' });
  }

  const results = await Promise.all(businessIds.map(async (businessId) => {
    try {
      const res = await docClient.send(new GetCommand({
          TableName: BUSINESSES_TABLE,
          Key: { businessId }
        }));
      const item = res.Item;
      if (!item) return [businessId, { found: false }];

      const timezone = item.timezone || DEFAULT_TIMEZONE;
      const acceptingOrders = item.acceptingOrders === true;
      const today = await getTodayWindow(businessId, timezone);
      const currentWeekday = getTodayWeekday(timezone); // 🔥 اسم اليوم الحالي بـ timezone المطعم
      
      // 🔍 Debug: تحقق من قيم today
      console.log(`[${businessId}] getTodayWindow result:`, JSON.stringify(today));
      console.log(`[${businessId}] today.isOpen = ${today.isOpen}, !!today.isOpen = ${!!today.isOpen}`);
      console.log(`[${businessId}] acceptingOrders = ${acceptingOrders}`);
      console.log(`[${businessId}] currentWeekday = ${currentWeekday}`); // 🔥 debug
      
      // 🔥 استخراج isClosed من working hours (الإغلاق اليدوي)
      const isClosedManually = today.workingHoursToday?.isClosed === true;
      const withinHours = !!today.isOpen;
      
      const { currentStatus, isClosed, isWithinWorkingHours, isAvailableNow } = deriveStatus(
        acceptingOrders, 
        withinHours, 
        isClosedManually
      );

      return [businessId, {
        businessId,
        acceptingOrders,
        isClosed,                    // الإغلاق اليدوي فقط
        isWithinWorkingHours,        // ضمن ساعات العمل (حسب الوقت)
        isAvailableNow,              // متاح الآن (كل الشروط)
        currentStatus,
        currentWeekday,              // 🔥 اسم اليوم الحالي (Tuesday, Monday, etc)
        workingHoursToday: today.workingHoursToday,
        lastUpdated: new Date().toISOString(),
        found: true
      }];
    } catch (e) {
      return [businessId, { found: false, error: e?.message || 'error' }];
    }
  }));

  const map = Object.fromEntries(results);
  return jsonResponse(200, { statuses: map, timestamp: new Date().toISOString() });
};
