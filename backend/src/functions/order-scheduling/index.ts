// Advanced Order Scheduling System
import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const ORDERS_TABLE = requireEnv('WIZZORDERS_TABLE');

interface ScheduleSlot {
  slotId: string;
  date: string;
  startTime: string;
  endTime: string;
  maxOrders: number;
  currentOrders: number;
  isAvailable: boolean;
  priceMultiplier: number;
  estimatedLeadTime: number;
}

interface BookingRequest {
  businessId: string;
  slotId: string;
  userId: string;
  orderDetails: {
    items: any[];
    totalAmount: number;
    deliveryAddress?: string;
    pickupRequest?: boolean;
  };
}

interface BookingResponse {
  success: boolean;
  bookingId?: string;
  scheduledTime?: string;
  estimatedDelivery?: string;
  priceMultiplier?: number;
  message?: string;
  error?: string;
}

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  console.log('Schedule request:', JSON.stringify(event, null, 2));

  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
  };

  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 200, headers, body: '' };
  }

  try {
    const { pathParameters, httpMethod, body } = event;
    const businessId = pathParameters?.businessId;

    if (!businessId) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'Business ID is required' })
      };
    }

    if (httpMethod === 'GET') {
      // Get available schedule slots
      const slots = await getAvailableSlots(businessId);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          success: true,
          businessId,
          availableSlots: slots
        })
      };
    } else if (httpMethod === 'POST') {
      // Book a schedule slot
      if (!body) {
        return {
          statusCode: 400,
          headers,
          body: JSON.stringify({ error: 'Request body is required' })
        };
      }

      const bookingRequest: BookingRequest = JSON.parse(body);
      const result = await bookScheduleSlot(bookingRequest);
      
      return {
        statusCode: result.success ? 200 : 400,
        headers,
        body: JSON.stringify(result)
      };
    }

    return {
      statusCode: 405,
      headers,
      body: JSON.stringify({ error: 'Method not allowed' })
    };

  } catch (error) {
    console.error('Schedule function error:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        error: 'Internal server error',
        details: error instanceof Error ? error.message : 'Unknown error'
      })
    };
  }
};

async function getAvailableSlots(businessId: string): Promise<ScheduleSlot[]> {
  try {
    // Get business data including schedule configuration
    const business = await getBusiness(businessId);
    if (!business) {
      throw new Error('Business not found');
    }

    const scheduleConfig = business.scheduleSlots;
    if (!scheduleConfig?.enabled) {
      return []; // Schedule slots not enabled for this business
    }

    // Generate slots for the next 7 days
    const slots: ScheduleSlot[] = [];
    const today = new Date();
    
    for (let dayOffset = 0; dayOffset < 7; dayOffset++) {
      const currentDate = new Date(today);
      currentDate.setDate(today.getDate() + dayOffset);
      
      const daySlots = await generateSlotsForDate(businessId, currentDate, scheduleConfig);
      slots.push(...daySlots);
    }

    // Filter out unavailable slots and add current booking data
    const availableSlots = await filterAndEnhanceSlots(businessId, slots);
    
    return availableSlots.sort((a, b) => 
      new Date(a.date + ' ' + a.startTime).getTime() - new Date(b.date + ' ' + b.startTime).getTime()
    );

  } catch (error) {
    console.error('Error getting available slots:', error);
    return [];
  }
}

async function generateSlotsForDate(businessId: string, date: Date, config: any): Promise<ScheduleSlot[]> {
  const slots: ScheduleSlot[] = [];
  const dateStr = date.toISOString().split('T')[0]; // YYYY-MM-DD
  const dayOfWeek = date.getDay(); // 0 = Sunday, 1 = Monday, etc.
  
  // Check if business is open on this day
  const dayConfig = config.weeklySchedule?.[dayOfWeek];
  if (!dayConfig?.enabled) {
    return slots;
  }

  // Generate time slots based on configuration
  const startHour = parseInt(dayConfig.openTime.split(':')[0]);
  const endHour = parseInt(dayConfig.closeTime.split(':')[0]);
  const slotDurationMins = config.slotDuration || 60; // Default 1 hour slots
  
  for (let hour = startHour; hour < endHour; hour++) {
    for (let minute = 0; minute < 60; minute += slotDurationMins) {
      const startTime = `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`;
      const endMinute = minute + slotDurationMins;
      const endHour = endMinute >= 60 ? hour + 1 : hour;
      const adjustedEndMinute = endMinute >= 60 ? endMinute - 60 : endMinute;
      const endTime = `${endHour.toString().padStart(2, '0')}:${adjustedEndMinute.toString().padStart(2, '0')}`;
      
      // Skip if slot extends beyond closing time
      if (endHour > endHour) continue;

      const slotDateTime = new Date(date);
      slotDateTime.setHours(hour, minute, 0, 0);
      
      // Skip past time slots
      if (slotDateTime <= new Date()) continue;

      slots.push({
        slotId: `${businessId}-${dateStr}-${startTime}`,
        date: dateStr,
        startTime,
        endTime,
        maxOrders: config.maxOrdersPerSlot || 10,
        currentOrders: 0, // Will be updated later
        isAvailable: true,
        priceMultiplier: calculatePriceMultiplier(slotDateTime, config),
        estimatedLeadTime: config.baseLeadTime || 30
      });
    }
  }

  return slots;
}

function calculatePriceMultiplier(slotDateTime: Date, config: any): number {
  const hour = slotDateTime.getHours();
  const dayOfWeek = slotDateTime.getDay();
  
  // Peak hours pricing
  const peakHours = config.peakHours || [];
  const isPeakHour = peakHours.some((peak: any) => 
    hour >= peak.startHour && hour <= peak.endHour
  );
  
  // Weekend pricing
  const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;
  
  let multiplier = 1.0;
  
  if (isPeakHour) {
    multiplier *= config.peakPriceMultiplier || 1.2;
  }
  
  if (isWeekend && config.weekendPriceMultiplier) {
    multiplier *= config.weekendPriceMultiplier;
  }
  
  return Math.round(multiplier * 100) / 100; // Round to 2 decimal places
}

async function filterAndEnhanceSlots(businessId: string, slots: ScheduleSlot[]): Promise<ScheduleSlot[]> {
  // Get current bookings for these slots
  const slotIds = slots.map(slot => slot.slotId);
  const bookings = await getCurrentBookings(businessId, slotIds);
  
  // Update slot availability based on current bookings
  return slots.map(slot => {
    const slotBookings = bookings.filter(booking => booking.slotId === slot.slotId);
    const currentOrders = slotBookings.length;
    
    return {
      ...slot,
      currentOrders,
      isAvailable: currentOrders < slot.maxOrders
    };
  }).filter(slot => slot.isAvailable);
}

async function getCurrentBookings(businessId: string, slotIds: string[]): Promise<any[]> {
  try {
    // Query orders table for scheduled orders
    const command = new QueryCommand({
      TableName: ORDERS_TABLE,
      IndexName: 'GSI_BusinessId',
      KeyConditionExpression: 'businessId = :businessId',
      FilterExpression: 'attribute_exists(scheduledSlotId) AND scheduledSlotId IN (:slotIds)',
      ExpressionAttributeValues: {
        ':businessId': businessId,
        ':slotIds': slotIds
      }
    });

    const result = await docClient.send(command);
    return result.Items || [];
  } catch (error) {
    console.error('Error getting current bookings:', error);
    return [];
  }
}

async function bookScheduleSlot(request: BookingRequest): Promise<BookingResponse> {
  try {
    // Validate the slot is still available
    const slots = await getAvailableSlots(request.businessId);
    const targetSlot = slots.find(slot => slot.slotId === request.slotId);
    
    if (!targetSlot) {
      return {
        success: false,
        error: 'Schedule slot is no longer available'
      };
    }

    // Create booking ID
    const bookingId = `booking-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    
    // Calculate scheduled delivery time
    const [date, time] = [targetSlot.date, targetSlot.startTime];
    const scheduledDateTime = new Date(`${date}T${time}:00`);
    const estimatedDelivery = new Date(scheduledDateTime.getTime() + (targetSlot.estimatedLeadTime * 60 * 1000));

    // Create the scheduled order
    const orderData = {
      orderId: bookingId,
      businessId: request.businessId,
      userId: request.userId,
      status: 'scheduled',
      scheduledSlotId: request.slotId,
      scheduledTime: scheduledDateTime.toISOString(),
      estimatedDeliveryTime: estimatedDelivery.toISOString(),
      orderDetails: request.orderDetails,
      priceMultiplier: targetSlot.priceMultiplier,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    // Save the order
    const putCommand = new PutCommand({
      TableName: ORDERS_TABLE,
      Item: orderData,
      ConditionExpression: 'attribute_not_exists(orderId)' // Ensure no duplicate
    });

    await docClient.send(putCommand);

    return {
      success: true,
      bookingId,
      scheduledTime: scheduledDateTime.toISOString(),
      estimatedDelivery: estimatedDelivery.toISOString(),
      priceMultiplier: targetSlot.priceMultiplier,
      message: `Order scheduled for ${targetSlot.date} at ${targetSlot.startTime}`
    };

  } catch (error) {
    console.error('Error booking schedule slot:', error);
    return {
      success: false,
      error: 'Failed to book schedule slot',
      message: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

async function getBusiness(businessId: string): Promise<any> {
  try {
    const command = new GetCommand({
      TableName: BUSINESSES_TABLE,
      Key: { businessId }
    });

    const result = await docClient.send(command);
    return result.Item;
  } catch (error) {
    console.error('Error getting business:', error);
    return null;
  }
}
