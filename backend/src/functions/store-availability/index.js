// Store Availability Engine - JavaScript Wrapper for get-businesses integration
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const STORES_TABLE = process.env.WIZZSTORES_TABLE || 'order-receiver-businesses-dev';
const WORKING_HOURS_TABLE = process.env.WORKING_HOURS_TABLE || 'order-receiver-business-working-hours-dev';
const ORDERS_TABLE = process.env.ORDERS_TABLE || 'WizzOrders';

// Main availability check function for get-businesses integration
async function checkStoreAvailability(storeId, userLatitude, userLongitude) {
  try {
    console.log(`🔍 Checking availability for store: ${storeId}`);
    
    // Get store data
    const storeData = await getStoreData(storeId);
    if (!storeData) {
      throw new Error(`Store ${storeId} not found`);
    }

    // Get working hours
    const workingHours = await getWorkingHours(storeId);
    
    // Calculate basic availability
    const availability = await calculateBasicAvailability(storeData, workingHours, userLatitude, userLongitude);
    
    return availability;
  } catch (error) {
    console.error(`Error checking availability for store ${storeId}:`, error);
    // Return fallback availability
    return createFallbackAvailability(storeId, error.message);
  }
}

async function getStoreData(storeId) {
  try {
    const command = new GetCommand({
      TableName: STORES_TABLE,
      Key: { businessId: storeId }
    });

    const result = await docClient.send(command);
    return result.Item || null;
  } catch (error) {
    console.error('Error fetching store data:', error);
    return null;
  }
}

async function getWorkingHours(storeId) {
  try {
    const command = new QueryCommand({
      TableName: WORKING_HOURS_TABLE,
      KeyConditionExpression: 'business_id = :storeId',
      ExpressionAttributeValues: {
        ':storeId': storeId
      }
    });

    const result = await docClient.send(command);
    return result.Items || [];
  } catch (error) {
    console.error('Error fetching working hours:', error);
    return [];
  }
}

async function calculateBasicAvailability(storeData, workingHours, userLatitude, userLongitude) {
  const timezone = storeData.timezone || 'Asia/Baghdad';
  const now = new Date();
  
  console.log(`🕐 Calculating availability for ${storeData.businessName || storeData.business_name}`);
  
  const reasonCodes = [];
  let status = 'OPEN';
  let canOrderNow = true;
  let canSchedule = true;
  let allowPickup = true;
  let allowDelivery = true;
  let leadTimeMins = storeData.preparationTime || 30;

  // 1. STORE ACTIVE CHECK
  if (!storeData.isActive) {
    status = 'CLOSED_OVERRIDE';
    canOrderNow = false;
    allowDelivery = false;
    allowPickup = false;
    reasonCodes.push('STORE_INACTIVE');
    console.log('❌ Store is inactive');
  }

  // 2. ACCEPTING ORDERS CHECK (Merchant toggle)
  if (canOrderNow && !storeData.acceptingOrders) {
    status = 'PAUSED_BY_MERCHANT';
    canOrderNow = false;
    reasonCodes.push('MERCHANT_PAUSED');
    console.log('⏸️ Store paused by merchant');
  }

  // 3. BUSINESS HOURS CHECK
  if (canOrderNow && workingHours.length > 0) {
    const hoursCheck = await checkBusinessHours(workingHours, timezone);
    if (!hoursCheck.isOpen) {
      status = 'CLOSED_HOURS';
      canOrderNow = false;
      reasonCodes.push('OUTSIDE_HOURS');
      console.log('🕐 Outside business hours');
    }
  }

  // 4. CAPACITY CHECK
  const capacityInfo = await checkBasicCapacity(storeData.businessId, storeData.maxOrdersPerHour || 20);
  
  // 5. DELIVERY AVAILABILITY
  const deliveryInfo = await checkBasicDeliveryAvailability(storeData, userLatitude, userLongitude);
  if (!deliveryInfo.available) {
    allowDelivery = false;
    reasonCodes.push(...deliveryInfo.reasonCodes);
  }

  // 6. PRICING
  const pricing = {
    deliveryFee: parseFloat(storeData.deliveryFee || storeData.delivery_fee || '5'),
    originalDeliveryFee: parseFloat(storeData.deliveryFee || storeData.delivery_fee || '5'),
    dynamicPricing: false,
    minimumOrder: parseFloat(storeData.minimumOrder || storeData.minimum_order || '0')
  };

  // 7. NEXT OPEN TIME
  const nextOpenAt = canOrderNow ? undefined : await calculateNextOpenTime(workingHours, timezone);

  return {
    storeId: storeData.businessId,
    storeName: storeData.businessName || storeData.business_name,
    status,
    reasonCodes,
    canOrderNow,
    canSchedule,
    allowPickup,
    allowDelivery,
    leadTimeMins,
    dynamicLeadTime: leadTimeMins !== (storeData.preparationTime || 30) ? leadTimeMins : undefined,
    nextOpenAt,
    allowScheduleFrom: canSchedule ? new Date(Date.now() + 60000).toISOString() : undefined,
    estimatedDeliveryTime: canOrderNow && allowDelivery ? 
      new Date(Date.now() + (leadTimeMins + (deliveryInfo.estimatedTime || 0)) * 60000).toISOString() : undefined,
    maxScheduleDays: 7,
    pricing,
    capacity: capacityInfo,
    delivery: deliveryInfo,
    scheduling: {
      available: canSchedule,
      availableSlots: [],
      nextAvailableSlot: canSchedule ? new Date(Date.now() + 60000).toISOString() : undefined
    },
    metadata: {
      timezone,
      currentTime: new Date().toISOString(),
      businessHours: formatWorkingHours(workingHours),
      isPaused: !storeData.acceptingOrders,
      isWithinHours: canOrderNow || status === 'OPEN',
      lastUpdated: new Date().toISOString()
    }
  };
}

async function checkBusinessHours(workingHours, timezone) {
  try {
    const now = new Date();
    const localTime = new Date(now.toLocaleString("en-US", { timeZone: timezone }));
    const weekday = localTime.toLocaleDateString('en-US', { weekday: 'long', timeZone: timezone });
    const currentTime = localTime.toTimeString().slice(0, 5); // HH:MM format
    
    const todayHours = workingHours.find(wh => wh.weekday === weekday);
    
    if (!todayHours || !todayHours.opening || !todayHours.closing) {
      return { isOpen: false, reason: 'CLOSED_TODAY' };
    }
    
    const isOpen = currentTime >= todayHours.opening && currentTime < todayHours.closing;
    return { 
      isOpen, 
      reason: isOpen ? null : 'OUTSIDE_HOURS',
      todayHours 
    };
  } catch (error) {
    console.error('Error checking business hours:', error);
    return { isOpen: false, reason: 'HOURS_CHECK_ERROR' };
  }
}

async function checkBasicCapacity(storeId, maxOrdersPerHour) {
  try {
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    
    const ordersCommand = new ScanCommand({
      TableName: ORDERS_TABLE,
      FilterExpression: 'storeId = :storeId AND createdAt >= :oneHourAgo AND #status IN (:pending, :confirmed, :preparing)',
      ExpressionAttributeNames: {
        '#status': 'status'
      },
      ExpressionAttributeValues: {
        ':storeId': storeId,
        ':oneHourAgo': oneHourAgo,
        ':pending': 'pending',
        ':confirmed': 'confirmed',
        ':preparing': 'preparing'
      }
    });
    
    const result = await docClient.send(ordersCommand);
    const currentOrders = result.Items?.length || 0;
    const utilizationPercent = Math.round((currentOrders / maxOrdersPerHour) * 100);
    
    return {
      currentOrders,
      maxOrdersPerHour,
      utilizationPercent,
      isNearCapacity: utilizationPercent >= 80,
      waitTimeAdded: utilizationPercent >= 80 ? Math.min(30, Math.floor((utilizationPercent - 80) * 1.5)) : 0
    };
  } catch (error) {
    console.error('Error checking capacity:', error);
    return {
      currentOrders: 0,
      maxOrdersPerHour,
      utilizationPercent: 0,
      isNearCapacity: false,
      waitTimeAdded: 0
    };
  }
}

async function checkBasicDeliveryAvailability(storeData, userLatitude, userLongitude) {
  try {
    const deliveryRadius = storeData.deliveryRadius || 10; // Default 10km
    let available = true;
    let estimatedTime = 30;
    const reasonCodes = [];
    
    // Basic distance check if user location provided
    if (userLatitude && userLongitude && storeData.latitude && storeData.longitude) {
      const distance = calculateDistance(
        userLatitude, userLongitude,
        storeData.latitude, storeData.longitude
      );
      
      if (distance > deliveryRadius) {
        available = false;
        reasonCodes.push('OUTSIDE_DELIVERY_RADIUS');
      } else {
        // Estimate delivery time based on distance
        estimatedTime = Math.max(15, Math.min(60, Math.round(distance * 3)));
      }
    }
    
    return {
      available,
      radius: deliveryRadius,
      blackoutZones: [],
      estimatedTime,
      driverAvailable: true, // Assume drivers available for basic check
      reasonCodes
    };
  } catch (error) {
    console.error('Error checking delivery availability:', error);
    return {
      available: true,
      radius: 10,
      blackoutZones: [],
      estimatedTime: 30,
      driverAvailable: true,
      reasonCodes: ['DELIVERY_CHECK_ERROR']
    };
  }
}

function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in kilometers
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c; // Distance in kilometers
}

async function calculateNextOpenTime(workingHours, timezone) {
  try {
    const now = new Date();
    const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    
    // Check next 7 days
    for (let dayOffset = 0; dayOffset < 7; dayOffset++) {
      const checkDate = new Date(now);
      checkDate.setDate(checkDate.getDate() + dayOffset);
      
      const weekdayIndex = checkDate.getDay();
      const weekdayName = weekdays[weekdayIndex];
      
      const dayHours = workingHours.find(wh => wh.weekday === weekdayName);
      if (!dayHours || !dayHours.opening) continue;
      
      // For today, check if opening time is in the future
      if (dayOffset === 0) {
        const todayInTimezone = new Date(now.toLocaleString("en-US", { timeZone: timezone }));
        const currentTime = todayInTimezone.toTimeString().slice(0, 5);
        
        if (currentTime < dayHours.opening) {
          const [openHour, openMinute] = dayHours.opening.split(':').map(Number);
          const openTime = new Date(checkDate);
          openTime.setHours(openHour, openMinute, 0, 0);
          return openTime.toISOString();
        }
      } else {
        // Future day
        const [openHour, openMinute] = dayHours.opening.split(':').map(Number);
        const openTime = new Date(checkDate);
        openTime.setHours(openHour, openMinute, 0, 0);
        return openTime.toISOString();
      }
    }
    
    return undefined;
  } catch (error) {
    console.error('Error calculating next open time:', error);
    return undefined;
  }
}

function formatWorkingHours(workingHours) {
  const formatted = {};
  const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  
  weekdays.forEach(day => {
    const dayHours = workingHours.find(wh => wh.weekday === day);
    formatted[day] = {
      opening: dayHours?.opening || null,
      closing: dayHours?.closing || null
    };
  });
  
  return formatted;
}

function createFallbackAvailability(storeId, errorMessage) {
  return {
    storeId,
    storeName: 'Unknown Store',
    status: 'CLOSED_OVERRIDE',
    reasonCodes: ['AVAILABILITY_CHECK_ERROR'],
    canOrderNow: false,
    canSchedule: false,
    allowPickup: false,
    allowDelivery: false,
    leadTimeMins: 30,
    nextOpenAt: undefined,
    maxScheduleDays: 0,
    pricing: {
      deliveryFee: 5,
      originalDeliveryFee: 5,
      dynamicPricing: false,
      minimumOrder: 0
    },
    capacity: {
      currentOrders: 0,
      maxOrdersPerHour: 20,
      utilizationPercent: 0,
      isNearCapacity: false,
      waitTimeAdded: 0
    },
    delivery: {
      available: false,
      radius: 0,
      blackoutZones: [],
      estimatedTime: 0,
      driverAvailable: false,
      reasonCodes: ['AVAILABILITY_CHECK_ERROR']
    },
    scheduling: {
      available: false,
      availableSlots: [],
      nextAvailableSlot: undefined
    },
    metadata: {
      timezone: 'Asia/Baghdad',
      currentTime: new Date().toISOString(),
      businessHours: {},
      isPaused: true,
      isWithinHours: false,
      lastUpdated: new Date().toISOString(),
      error: errorMessage
    }
  };
}

module.exports = {
  checkStoreAvailability
};
