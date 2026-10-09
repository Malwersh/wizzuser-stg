// Store Availability Engine - Advanced Restaurant Availability System
import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, QueryCommand, ScanCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const STORES_TABLE = process.env.WIZZSTORES_TABLE || 'order-receiver-businesses-dev';
const WORKING_HOURS_TABLE = process.env.WORKING_HOURS_TABLE || 'order-receiver-business-working-hours-dev';
const ORDERS_TABLE = process.env.ORDERS_TABLE || 'WizzOrders';
const DELIVERY_ZONES_TABLE = process.env.DELIVERY_ZONES_TABLE || 'order-receiver-delivery-zones-dev';

// Export the main function for use by other services
export const checkStoreAvailability = async (
  storeId: string, 
  userLatitude?: number | null, 
  userLongitude?: number | null
): Promise<AvailabilityResponse> => {
  try {
    const storeData = await getStoreData(storeId);
    if (!storeData) {
      throw new Error(`Store ${storeId} not found`);
    }

    const workingHours = await getWorkingHours(storeId);
    const userLocation = userLatitude && userLongitude ? `${userLatitude},${userLongitude}` : undefined;
    
    return await calculateAvailability(storeData, workingHours, userLocation);
  } catch (error) {
    console.error(`Error checking availability for store ${storeId}:`, error);
    throw error;
  }
};

interface AvailabilityResponse {
  storeId: string;
  storeName: string;
  status: 'OPEN' | 'CLOSED_HOURS' | 'CLOSED_OVERRIDE' | 'PAUSED_BY_MERCHANT' | 'BUSY_THROTTLED' | 'CLOSING_SOON' | 'DELIVERY_BLACKOUT' | 'CAPACITY_FULL';
  reasonCodes: string[];
  canOrderNow: boolean;
  canSchedule: boolean;
  allowPickup: boolean;
  allowDelivery: boolean;
  leadTimeMins: number;
  dynamicLeadTime?: number;
  nextOpenAt?: string;
  allowScheduleFrom?: string;
  estimatedDeliveryTime?: string;
  maxScheduleDays: number;
  pricing: {
    deliveryFee: number;
    originalDeliveryFee: number;
    dynamicPricing: boolean;
    surchargeReason?: string;
    minimumOrder: number;
  };
  capacity: {
    currentOrders: number;
    maxOrdersPerHour: number;
    utilizationPercent: number;
    isNearCapacity: boolean;
    waitTimeAdded: number;
  };
  delivery: {
    available: boolean;
    radius: number;
    blackoutZones: string[];
    estimatedTime?: number;
    driverAvailable: boolean;
  };
  scheduling: {
    available: boolean;
    availableSlots: ScheduleSlot[];
    nextAvailableSlot?: string;
  };
  metadata: {
    timezone: string;
    currentTime: string;
    businessHours: any;
    isPaused: boolean;
    isWithinHours: boolean;
    lastUpdated: string;
    weatherImpact?: boolean;
    holidayInfo?: string;
  };
}

interface ScheduleSlot {
  dateTime: string;
  available: boolean;
  leadTime: number;
  capacity: number;
  orderCount: number;
  deliveryAvailable: boolean;
  pickupAvailable: boolean;
}

interface StoreData {
  businessId: string;
  businessName: string;
  isActive: boolean;
  acceptingOrders: boolean;
  isPaused?: boolean;
  pausedUntil?: string;
  pauseReason?: string;
  timezone?: string;
  preparationTime?: number;
  deliveryRadius?: number;
  lastStatusUpdate?: string;
  maxOrdersPerHour?: number;
  minimumOrder?: number;
  deliveryFee?: number;
  latitude?: number;
  longitude?: number;
  autoScheduling?: boolean;
  dynamicPricing?: boolean;
}

interface WorkingHours {
  business_id: string;
  weekday: string;
  opening: string | null;
  closing: string | null;
}

interface DeliveryZone {
  zoneId: string;
  businessId: string;
  type: 'ACTIVE' | 'BLACKOUT' | 'PREMIUM';
  coordinates: Array<{lat: number, lng: number}>;
  deliveryFee?: number;
  isActive: boolean;
  effectiveFrom?: string;
  effectiveUntil?: string;
}

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
};

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  console.log('Store Availability Check:', JSON.stringify(event, null, 2));

  try {
    if (event.httpMethod === 'OPTIONS') {
      return { statusCode: 200, headers, body: '' };
    }

    const storeId = event.pathParameters?.storeId;
    const userLocation = event.queryStringParameters?.location; // "lat,lng"
    
    if (!storeId) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({
          success: false,
          message: 'Store ID is required'
        })
      };
    }

    // Get store data
    const storeData = await getStoreData(storeId);
    if (!storeData) {
      return {
        statusCode: 404,
        headers,
        body: JSON.stringify({
          success: false,
          message: 'Store not found'
        })
      };
    }

    // Get working hours
    const workingHours = await getWorkingHours(storeId);
    
    // Calculate availability
    const availability = await calculateAvailability(storeData, workingHours, userLocation);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        availability
      })
    };

  } catch (error) {
    console.error('Error checking store availability:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'Internal server error',
        error: process.env.NODE_ENV === 'development' ? (error as Error).message : undefined
      })
    };
  }
};

async function getStoreData(storeId: string): Promise<StoreData | null> {
  try {
    const command = new GetCommand({
      TableName: STORES_TABLE,
      Key: { businessId: storeId }
    });

    const result = await docClient.send(command);
    return result.Item as StoreData || null;
  } catch (error) {
    console.error('Error fetching store data:', error);
    return null;
  }
}

async function getWorkingHours(storeId: string): Promise<WorkingHours[]> {
  try {
    const command = new QueryCommand({
      TableName: WORKING_HOURS_TABLE,
      KeyConditionExpression: 'business_id = :storeId',
      ExpressionAttributeValues: {
        ':storeId': storeId
      }
    });

    const result = await docClient.send(command);
    return result.Items as WorkingHours[] || [];
  } catch (error) {
    console.error('Error fetching working hours:', error);
    return [];
  }
}

async function calculateAvailability(
  storeData: StoreData, 
  workingHours: WorkingHours[], 
  userLocation?: string
): Promise<AvailabilityResponse> {
  const timezone = storeData.timezone || 'Asia/Baghdad';
  const now = new Date();
  const localTime = new Intl.DateTimeFormat('en-CA', { 
    timeZone: timezone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    hour12: false
  }).format(now);
  
  console.log(`🕐 Calculating availability for ${storeData.businessName} at ${localTime} (${timezone})`);
  
  const reasonCodes: string[] = [];
  let status: AvailabilityResponse['status'] = 'OPEN';
  let canOrderNow = true;
  let canSchedule = true;
  let allowPickup = true;
  let allowDelivery = true;
  let leadTimeMins = storeData.preparationTime || 30;
  
  // 1. PRIORITY CHECK: Store inactive
  if (!storeData.isActive) {
    status = 'CLOSED_OVERRIDE';
    canOrderNow = false;
    canSchedule = false;
    allowPickup = false;
    allowDelivery = false;
    reasonCodes.push('STORE_INACTIVE');
    console.log('❌ Store is inactive');
  }
  
  // 2. PRIORITY CHECK: Manual pause by merchant
  else if (!storeData.acceptingOrders || storeData.isPaused) {
    status = 'PAUSED_BY_MERCHANT';
    canOrderNow = false;
    canSchedule = storeData.autoScheduling || false;
    allowPickup = storeData.autoScheduling || false;
    allowDelivery = storeData.autoScheduling || false;
    reasonCodes.push('MERCHANT_PAUSED');
    console.log('⏸️ Store manually paused by merchant');
  }
  
  // 3. WORKING HOURS CHECK
  else {
    const isWithinHours = await checkWorkingHours(workingHours, timezone);
    if (!isWithinHours.isOpen) {
      status = 'CLOSED_HOURS';
      canOrderNow = false;
      allowPickup = false;
      allowDelivery = false;
      reasonCodes.push('OUTSIDE_HOURS');
      console.log('⏰ Outside working hours');
    }
  }
  
  // 4. CAPACITY AND CONGESTION CHECK
  const capacityInfo = await checkCapacity(storeData.businessId, storeData.maxOrdersPerHour || 20);
  if (capacityInfo.isNearCapacity && canOrderNow) {
    if (capacityInfo.utilizationPercent >= 100) {
      status = 'CAPACITY_FULL';
      canOrderNow = false;
      reasonCodes.push('CAPACITY_FULL');
      console.log('🚫 Store at full capacity');
    } else if (capacityInfo.utilizationPercent >= 80) {
      status = 'BUSY_THROTTLED';
      leadTimeMins += capacityInfo.waitTimeAdded;
      reasonCodes.push('HIGH_DEMAND');
      console.log(`⏱️ High demand - added ${capacityInfo.waitTimeAdded} mins wait time`);
    }
  }
  
  // 5. CLOSING SOON CHECK
  if (canOrderNow) {
    const closingSoonCheck = await checkClosingSoon(workingHours, timezone, leadTimeMins);
    if (closingSoonCheck.isClosingSoon) {
      status = 'CLOSING_SOON';
      canOrderNow = closingSoonCheck.canStillOrder;
      if (!canOrderNow) {
        reasonCodes.push('CLOSING_SOON');
        console.log('🕐 Too close to closing time');
      }
    }
  }
  
  // 6. DELIVERY AVAILABILITY CHECK
  const deliveryInfo = await checkDeliveryAvailability(storeData, userLocation);
  if (!deliveryInfo.available) {
    allowDelivery = false;
    reasonCodes.push(...deliveryInfo.reasonCodes);
  }
  
  // 7. DYNAMIC PRICING CALCULATION
  const pricingInfo = calculateDynamicPricing(storeData, capacityInfo, deliveryInfo);
  
  // 8. SCHEDULE SLOTS (for future orders)
  const schedulingInfo = await generateScheduleSlots(storeData, workingHours, timezone);
  
  // 9. NEXT AVAILABLE TIME
  const nextOpenAt = canOrderNow ? undefined : await calculateNextOpenTime(workingHours, timezone);
  
  console.log(`✅ Availability calculated: ${status} (canOrder: ${canOrderNow})`);
  
  return {
    storeId: storeData.businessId,
    storeName: storeData.businessName,
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
    pricing: pricingInfo,
    capacity: capacityInfo,
    delivery: deliveryInfo,
    scheduling: schedulingInfo,
    metadata: {
      timezone,
      currentTime: localTime,
      businessHours: await formatWorkingHours(workingHours),
      isPaused: !storeData.acceptingOrders || !!storeData.isPaused,
      isWithinHours: canOrderNow || status === 'OPEN',
      lastUpdated: new Date().toISOString()
    }
  };
}

// CAPACITY MANAGEMENT
async function checkCapacity(storeId: string, maxOrdersPerHour: number) {
  try {
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    
    // Get orders from last hour
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
    
    let waitTimeAdded = 0;
    if (utilizationPercent >= 80) {
      waitTimeAdded = Math.min(30, Math.floor((utilizationPercent - 80) * 1.5));
    }
    
    return {
      currentOrders,
      maxOrdersPerHour,
      utilizationPercent,
      isNearCapacity: utilizationPercent >= 70,
      waitTimeAdded
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

// DELIVERY AVAILABILITY WITH ZONE CHECKING
async function checkDeliveryAvailability(storeData: StoreData, userLocation?: string) {
  const deliveryInfo = {
    available: true,
    radius: storeData.deliveryRadius || 5,
    blackoutZones: [] as string[],
    estimatedTime: 25,
    driverAvailable: true, // Would integrate with driver availability service
    reasonCodes: [] as string[]
  };
  
  if (!storeData.deliveryRadius) {
    deliveryInfo.available = false;
    deliveryInfo.reasonCodes.push('NO_DELIVERY_SERVICE');
    return deliveryInfo;
  }
  
  // Check user location if provided
  if (userLocation) {
    const [userLat, userLng] = userLocation.split(',').map(Number);
    const storeLat = storeData.latitude;
    const storeLng = storeData.longitude;
    
    if (storeLat && storeLng) {
      const distance = calculateDistance(userLat, userLng, storeLat, storeLng);
      if (distance > deliveryInfo.radius) {
        deliveryInfo.available = false;
        deliveryInfo.reasonCodes.push('OUTSIDE_DELIVERY_RADIUS');
      }
      
      // Estimate delivery time based on distance
      deliveryInfo.estimatedTime = Math.max(15, Math.round(distance * 5));
    }
  }
  
  // Check delivery blackout zones
  try {
    const blackoutCommand = new ScanCommand({
      TableName: DELIVERY_ZONES_TABLE,
      FilterExpression: 'businessId = :businessId AND #type = :blackout AND isActive = :active',
      ExpressionAttributeNames: {
        '#type': 'type'
      },
      ExpressionAttributeValues: {
        ':businessId': storeData.businessId,
        ':blackout': 'BLACKOUT',
        ':active': true
      }
    });
    
    const blackoutResult = await docClient.send(blackoutCommand);
    if (blackoutResult.Items && blackoutResult.Items.length > 0) {
      deliveryInfo.blackoutZones = blackoutResult.Items.map(zone => zone.zoneId);
      // Would need to check if user location is within blackout zones
    }
  } catch (error) {
    console.error('Error checking delivery zones:', error);
  }
  
  return deliveryInfo;
}

// DYNAMIC PRICING CALCULATION
function calculateDynamicPricing(storeData: StoreData, capacityInfo: any, deliveryInfo: any) {
  const originalDeliveryFee = storeData.deliveryFee || 5000;
  let deliveryFee = originalDeliveryFee;
  let dynamicPricing = false;
  let surchargeReason: string | undefined;
  
  if (storeData.dynamicPricing) {
    // High demand surcharge
    if (capacityInfo.utilizationPercent >= 80) {
      const surchargePercent = Math.min(50, (capacityInfo.utilizationPercent - 80) * 2);
      deliveryFee = Math.round(originalDeliveryFee * (1 + surchargePercent / 100));
      dynamicPricing = true;
      surchargeReason = 'HIGH_DEMAND';
    }
    
    // Distance-based pricing
    if (deliveryInfo.estimatedTime > 30) {
      deliveryFee += Math.round((deliveryInfo.estimatedTime - 30) * 100);
      dynamicPricing = true;
      surchargeReason = surchargeReason ? `${surchargeReason}_DISTANCE` : 'DISTANCE';
    }
  }
  
  return {
    deliveryFee,
    originalDeliveryFee,
    dynamicPricing,
    surchargeReason,
    minimumOrder: storeData.minimumOrder || 15000
  };
}

// SCHEDULE SLOTS GENERATION
async function generateScheduleSlots(storeData: StoreData, workingHours: WorkingHours[], timezone: string) {
  const slots: ScheduleSlot[] = [];
  const maxDays = 7;
  
  if (!storeData.autoScheduling) {
    return {
      available: false,
      availableSlots: slots,
      nextAvailableSlot: undefined
    };
  }
  
  try {
    for (let day = 0; day < maxDays; day++) {
      const targetDate = new Date(Date.now() + day * 24 * 60 * 60 * 1000);
      const weekday = targetDate.toLocaleDateString('en-US', { weekday: 'long', timeZone: timezone });
      
      const dayHours = workingHours.find(wh => wh.weekday === weekday);
      if (!dayHours || !dayHours.opening || !dayHours.closing) continue;
      
      // Generate 30-minute slots within business hours
      const openTime = parseTime(dayHours.opening);
      const closeTime = parseTime(dayHours.closing);
      
      for (let hour = openTime.hours; hour < closeTime.hours; hour++) {
        for (let minute = 0; minute < 60; minute += 30) {
          if (hour === closeTime.hours - 1 && minute >= closeTime.minutes) break;
          
          const slotTime = new Date(targetDate);
          slotTime.setHours(hour, minute, 0, 0);
          
          // Skip past slots
          if (slotTime <= new Date()) continue;
          
          slots.push({
            dateTime: slotTime.toISOString(),
            available: true,
            leadTime: storeData.preparationTime || 30,
            capacity: 5, // Max orders per slot
            orderCount: 0, // Would check existing scheduled orders
            deliveryAvailable: !!storeData.deliveryRadius,
            pickupAvailable: true
          });
        }
      }
    }
    
    return {
      available: slots.length > 0,
      availableSlots: slots.slice(0, 20), // Limit response size
      nextAvailableSlot: slots[0]?.dateTime
    };
  } catch (error) {
    console.error('Error generating schedule slots:', error);
    return {
      available: false,
      availableSlots: [],
      nextAvailableSlot: undefined
    };
  }
}

// UTILITY FUNCTIONS
function calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371; // Earth's radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLng/2) * Math.sin(dLng/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
}

function parseTime(timeString: string): { hours: number, minutes: number } {
  const [hours, minutes] = timeString.split(':').map(Number);
  return { hours, minutes };
}

// WORKING HOURS CHECKING
async function checkWorkingHours(workingHours: WorkingHours[], timezone: string) {
  try {
    const now = new Date();
    const todayInTimezone = new Date(now.toLocaleString("en-US", { timeZone: timezone }));
    const weekday = todayInTimezone.toLocaleDateString('en-US', { weekday: 'long' });
    const currentTime = todayInTimezone.toTimeString().slice(0, 5); // HH:MM format
    
    console.log(`🕒 Checking working hours for ${weekday} at ${currentTime} (${timezone})`);
    
    const todayHours = workingHours.find(wh => wh.weekday === weekday);
    
    if (!todayHours || !todayHours.opening || !todayHours.closing) {
      console.log(`❌ No working hours found for ${weekday}`);
      return { 
        isOpen: false, 
        reason: 'NO_HOURS_DEFINED',
        currentDay: weekday,
        currentTime
      };
    }
    
    const openTime = todayHours.opening;
    const closeTime = todayHours.closing;
    
    // Handle 24-hour format comparison
    const isOpen = currentTime >= openTime && currentTime < closeTime;
    
    console.log(`⏰ Hours: ${openTime}-${closeTime}, Current: ${currentTime}, Open: ${isOpen}`);
    
    return {
      isOpen,
      reason: isOpen ? 'WITHIN_HOURS' : 'OUTSIDE_HOURS',
      currentDay: weekday,
      currentTime,
      openTime,
      closeTime
    };
  } catch (error) {
    console.error('Error checking working hours:', error);
    return { 
      isOpen: false, 
      reason: 'ERROR_CHECKING_HOURS',
      currentDay: 'Unknown',
      currentTime: 'Unknown'
    };
  }
}

// CLOSING SOON CHECK
async function checkClosingSoon(workingHours: WorkingHours[], timezone: string, leadTimeMins: number) {
  try {
    const now = new Date();
    const todayInTimezone = new Date(now.toLocaleString("en-US", { timeZone: timezone }));
    const weekday = todayInTimezone.toLocaleDateString('en-US', { weekday: 'long' });
    const currentTime = todayInTimezone.toTimeString().slice(0, 5);
    
    const todayHours = workingHours.find(wh => wh.weekday === weekday);
    
    if (!todayHours || !todayHours.closing) {
      return { isClosingSoon: false, canStillOrder: true };
    }
    
    const closeTime = todayHours.closing;
    const [closeHour, closeMinute] = closeTime.split(':').map(Number);
    const [currentHour, currentMinute] = currentTime.split(':').map(Number);
    
    const closeTimeInMinutes = closeHour * 60 + closeMinute;
    const currentTimeInMinutes = currentHour * 60 + currentMinute;
    const minutesUntilClose = closeTimeInMinutes - currentTimeInMinutes;
    
    // Add buffer time (10 minutes) to ensure order can be prepared
    const cutoffTime = leadTimeMins + 10;
    
    const isClosingSoon = minutesUntilClose <= 60; // Within 1 hour of closing
    const canStillOrder = minutesUntilClose > cutoffTime;
    
    if (isClosingSoon) {
      console.log(`⏰ Closing soon: ${minutesUntilClose} mins left, cutoff: ${cutoffTime} mins, can order: ${canStillOrder}`);
    }
    
    return {
      isClosingSoon,
      canStillOrder,
      minutesUntilClose,
      cutoffTime
    };
  } catch (error) {
    console.error('Error checking closing soon:', error);
    return { isClosingSoon: false, canStillOrder: true };
  }
}

// CALCULATE NEXT AVAILABLE TIME
async function calculateNextOpenTime(workingHours: WorkingHours[], timezone: string): Promise<string | undefined> {
  try {
    const now = new Date();
    const daysToCheck = 7; // Check next 7 days
    
    for (let dayOffset = 0; dayOffset < daysToCheck; dayOffset++) {
      const checkDate = new Date(now);
      checkDate.setDate(checkDate.getDate() + dayOffset);
      
      const weekday = checkDate.toLocaleDateString('en-US', { weekday: 'long', timeZone: timezone });
      const dayHours = workingHours.find(wh => wh.weekday === weekday);
      
      if (!dayHours || !dayHours.opening) continue;
      
      // For today, check if opening time is in the future
      if (dayOffset === 0) {
        const todayInTimezone = new Date(now.toLocaleString("en-US", { timeZone: timezone }));
        const currentTime = todayInTimezone.toTimeString().slice(0, 5);
        
        if (currentTime < dayHours.opening) {
          // Still can open today
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
    
    return undefined; // No opening time found in next 7 days
  } catch (error) {
    console.error('Error calculating next open time:', error);
    return undefined;
  }
}

// FORMAT WORKING HOURS FOR RESPONSE
async function formatWorkingHours(workingHours: WorkingHours[]) {
  const formatted: Record<string, { opening: string | null, closing: string | null }> = {};
  
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
