// Advanced Delivery Zone Management System
import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, ScanCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const DELIVERY_ZONES_TABLE = process.env.DELIVERY_ZONES_TABLE || 'order-receiver-delivery-zones-dev';
const DRIVER_LOCATIONS_TABLE = process.env.DRIVER_LOCATIONS_TABLE || 'order-receiver-driver-locations-dev';

interface DeliveryZone {
  zoneId: string;
  businessId: string;
  zoneName: string;
  type: 'ACTIVE' | 'BLACKOUT' | 'PREMIUM' | 'SURGE' | 'WEATHER_RESTRICTED';
  coordinates: Array<{lat: number, lng: number}>;
  deliveryFee: number;
  baseDeliveryFee: number;
  estimatedTime: number; // minutes
  isActive: boolean;
  effectiveFrom?: string;
  effectiveUntil?: string;
  surchargePercent?: number;
  weatherConditions?: string[];
  priority: number; // Higher priority zones override lower ones
  driverCapacity?: number;
  currentDrivers?: number;
  lastUpdated: string;
  createdBy: string;
}

interface DriverLocation {
  driverId: string;
  businessId: string;
  currentLat: number;
  currentLng: number;
  isAvailable: boolean;
  isOnline: boolean;
  currentOrderId?: string;
  estimatedReturnTime?: string;
  maxDeliveryRadius: number;
  vehicleType: 'MOTORCYCLE' | 'CAR' | 'BICYCLE' | 'WALKING';
  lastUpdate: string;
  activeZones: string[]; // Zones this driver can serve
}

interface ZoneCheckRequest {
  userLat: number;
  userLng: number;
  businessId: string;
  orderValue?: number;
  weatherCondition?: string;
}

interface ZoneCheckResponse {
  canDeliver: boolean;
  selectedZone?: DeliveryZone;
  deliveryFee: number;
  estimatedTime: number;
  availableDrivers: number;
  reasonCodes: string[];
  alternativeOptions?: {
    pickupAvailable: boolean;
    nearbyZones: Array<{
      zoneName: string;
      distance: number;
      deliveryFee: number;
    }>;
  };
  surcharges: Array<{
    type: string;
    amount: number;
    reason: string;
  }>;
}

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
};

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  console.log('Delivery Zone Management:', JSON.stringify(event, null, 2));

  try {
    if (event.httpMethod === 'OPTIONS') {
      return { statusCode: 200, headers, body: '' };
    }

    const { httpMethod, path } = event;

    // GET /delivery/check - Check if location can be delivered to
    if (httpMethod === 'POST' && path.includes('/delivery/check')) {
      const checkRequest: ZoneCheckRequest = JSON.parse(event.body || '{}');
      const result = await checkDeliveryZone(checkRequest);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    // GET /delivery/zones/{businessId} - Get all zones for business
    if (httpMethod === 'GET' && path.includes('/delivery/zones/')) {
      const businessId = event.pathParameters?.businessId;
      if (!businessId) {
        return {
          statusCode: 400,
          headers,
          body: JSON.stringify({ success: false, message: 'Business ID is required' })
        };
      }
      
      const result = await getBusinessZones(businessId);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    // POST /delivery/zones - Create new delivery zone
    if (httpMethod === 'POST' && path.includes('/delivery/zones')) {
      const zoneData = JSON.parse(event.body || '{}');
      const result = await createDeliveryZone(zoneData);
      return {
        statusCode: 201,
        headers,
        body: JSON.stringify(result)
      };
    }

    // PUT /delivery/zones/{zoneId} - Update delivery zone
    if (httpMethod === 'PUT' && path.includes('/delivery/zones/')) {
      const zoneId = event.pathParameters?.zoneId;
      const updateData = JSON.parse(event.body || '{}');
      const result = await updateDeliveryZone(zoneId!, updateData);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    // DELETE /delivery/zones/{zoneId} - Delete delivery zone
    if (httpMethod === 'DELETE' && path.includes('/delivery/zones/')) {
      const zoneId = event.pathParameters?.zoneId;
      const result = await deleteDeliveryZone(zoneId!);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    // POST /delivery/drivers/location - Update driver location
    if (httpMethod === 'POST' && path.includes('/delivery/drivers/location')) {
      const locationData = JSON.parse(event.body || '{}');
      const result = await updateDriverLocation(locationData);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    // GET /delivery/drivers/{businessId}/available - Get available drivers
    if (httpMethod === 'GET' && path.includes('/delivery/drivers/') && path.includes('/available')) {
      const businessId = event.pathParameters?.businessId;
      const userLocation = event.queryStringParameters?.location;
      const result = await getAvailableDrivers(businessId!, userLocation);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    return {
      statusCode: 404,
      headers,
      body: JSON.stringify({ success: false, message: 'Endpoint not found' })
    };

  } catch (error) {
    console.error('Delivery zone handler error:', error);
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

// CHECK DELIVERY ZONE AVAILABILITY
async function checkDeliveryZone(request: ZoneCheckRequest): Promise<ZoneCheckResponse> {
  try {
    console.log(`🗺️ Checking delivery for location (${request.userLat}, ${request.userLng}) for business ${request.businessId}`);

    // Get all active zones for this business
    const zones = await getActiveZonesForBusiness(request.businessId);
    
    if (zones.length === 0) {
      return {
        canDeliver: false,
        deliveryFee: 0,
        estimatedTime: 0,
        availableDrivers: 0,
        reasonCodes: ['NO_DELIVERY_ZONES'],
        alternativeOptions: {
          pickupAvailable: true,
          nearbyZones: []
        },
        surcharges: []
      };
    }

    // Find matching zones
    const matchingZones = zones.filter(zone => 
      isPointInPolygon(request.userLat, request.userLng, zone.coordinates) && 
      isZoneActive(zone)
    );

    if (matchingZones.length === 0) {
      // Find nearby zones for alternatives
      const nearbyZones = await findNearbyZones(request.userLat, request.userLng, zones);
      
      return {
        canDeliver: false,
        deliveryFee: 0,
        estimatedTime: 0,
        availableDrivers: 0,
        reasonCodes: ['OUTSIDE_DELIVERY_ZONES'],
        alternativeOptions: {
          pickupAvailable: true,
          nearbyZones
        },
        surcharges: []
      };
    }

    // Sort by priority and select the best zone
    const selectedZone = matchingZones.sort((a, b) => b.priority - a.priority)[0];
    
    // Check for blackout zones
    const blackoutZones = matchingZones.filter(zone => zone.type === 'BLACKOUT');
    if (blackoutZones.length > 0) {
      return {
        canDeliver: false,
        deliveryFee: 0,
        estimatedTime: 0,
        availableDrivers: 0,
        reasonCodes: ['DELIVERY_BLACKOUT'],
        alternativeOptions: {
          pickupAvailable: true,
          nearbyZones: []
        },
        surcharges: []
      };
    }

    // Check driver availability
    const availableDrivers = await countAvailableDrivers(request.businessId, selectedZone.zoneId);
    
    if (availableDrivers === 0) {
      return {
        canDeliver: false,
        deliveryFee: selectedZone.deliveryFee,
        estimatedTime: selectedZone.estimatedTime + 30, // Add wait time
        availableDrivers: 0,
        reasonCodes: ['NO_DRIVERS_AVAILABLE'],
        alternativeOptions: {
          pickupAvailable: true,
          nearbyZones: []
        },
        surcharges: []
      };
    }

    // Calculate final delivery fee with surcharges
    const surcharges = calculateSurcharges(selectedZone, request);
    const finalDeliveryFee = selectedZone.deliveryFee + surcharges.reduce((sum, s) => sum + s.amount, 0);

    // Adjust estimated time based on demand
    const adjustedTime = selectedZone.estimatedTime + (availableDrivers === 1 ? 15 : 0);

    return {
      canDeliver: true,
      selectedZone,
      deliveryFee: finalDeliveryFee,
      estimatedTime: adjustedTime,
      availableDrivers,
      reasonCodes: ['DELIVERY_AVAILABLE'],
      surcharges
    };

  } catch (error) {
    console.error('Error checking delivery zone:', error);
    return {
      canDeliver: false,
      deliveryFee: 0,
      estimatedTime: 0,
      availableDrivers: 0,
      reasonCodes: ['ERROR_CHECKING_DELIVERY'],
      alternativeOptions: {
        pickupAvailable: true,
        nearbyZones: []
      },
      surcharges: []
    };
  }
}

// GET ACTIVE ZONES FOR BUSINESS
async function getActiveZonesForBusiness(businessId: string): Promise<DeliveryZone[]> {
  try {
    const command = new QueryCommand({
      TableName: DELIVERY_ZONES_TABLE,
      KeyConditionExpression: 'businessId = :businessId',
      FilterExpression: 'isActive = :active',
      ExpressionAttributeValues: {
        ':businessId': businessId,
        ':active': true
      }
    });

    const result = await docClient.send(command);
    return result.Items as DeliveryZone[] || [];
  } catch (error) {
    console.error('Error getting active zones:', error);
    return [];
  }
}

// POINT IN POLYGON CHECK
function isPointInPolygon(lat: number, lng: number, polygon: Array<{lat: number, lng: number}>): boolean {
  let inside = false;
  
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = polygon[i].lng;
    const yi = polygon[i].lat;
    const xj = polygon[j].lng;
    const yj = polygon[j].lat;
    
    if (((yi > lat) !== (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
      inside = !inside;
    }
  }
  
  return inside;
}

// ZONE ACTIVE CHECK
function isZoneActive(zone: DeliveryZone): boolean {
  const now = new Date();
  
  if (zone.effectiveFrom && new Date(zone.effectiveFrom) > now) {
    return false;
  }
  
  if (zone.effectiveUntil && new Date(zone.effectiveUntil) < now) {
    return false;
  }
  
  return zone.isActive;
}

// FIND NEARBY ZONES
async function findNearbyZones(userLat: number, userLng: number, zones: DeliveryZone[]) {
  const nearbyZones = zones
    .map(zone => {
      // Calculate distance to zone center
      const centerLat = zone.coordinates.reduce((sum, coord) => sum + coord.lat, 0) / zone.coordinates.length;
      const centerLng = zone.coordinates.reduce((sum, coord) => sum + coord.lng, 0) / zone.coordinates.length;
      const distance = calculateDistance(userLat, userLng, centerLat, centerLng);
      
      return {
        zoneName: zone.zoneName,
        distance: Math.round(distance * 100) / 100,
        deliveryFee: zone.deliveryFee
      };
    })
    .filter(zone => zone.distance <= 5) // Within 5km
    .sort((a, b) => a.distance - b.distance)
    .slice(0, 3); // Top 3 nearest

  return nearbyZones;
}

// COUNT AVAILABLE DRIVERS
async function countAvailableDrivers(businessId: string, zoneId: string): Promise<number> {
  try {
    const command = new ScanCommand({
      TableName: DRIVER_LOCATIONS_TABLE,
      FilterExpression: 'businessId = :businessId AND isAvailable = :available AND isOnline = :online AND contains(activeZones, :zoneId)',
      ExpressionAttributeValues: {
        ':businessId': businessId,
        ':available': true,
        ':online': true,
        ':zoneId': zoneId
      }
    });

    const result = await docClient.send(command);
    return result.Items?.length || 0;
  } catch (error) {
    console.error('Error counting available drivers:', error);
    return 0;
  }
}

// CALCULATE SURCHARGES
function calculateSurcharges(zone: DeliveryZone, request: ZoneCheckRequest) {
  const surcharges: Array<{type: string, amount: number, reason: string}> = [];

  // Weather surcharge
  if (request.weatherCondition && zone.weatherConditions?.includes(request.weatherCondition)) {
    surcharges.push({
      type: 'WEATHER',
      amount: Math.round(zone.deliveryFee * 0.2), // 20% weather surcharge
      reason: `Weather condition: ${request.weatherCondition}`
    });
  }

  // Premium zone surcharge
  if (zone.type === 'PREMIUM') {
    surcharges.push({
      type: 'PREMIUM_ZONE',
      amount: Math.round(zone.deliveryFee * (zone.surchargePercent || 25) / 100),
      reason: 'Premium delivery zone'
    });
  }

  // Surge pricing
  if (zone.type === 'SURGE') {
    surcharges.push({
      type: 'SURGE',
      amount: Math.round(zone.deliveryFee * (zone.surchargePercent || 50) / 100),
      reason: 'High demand area'
    });
  }

  return surcharges;
}

// BUSINESS ZONE MANAGEMENT
async function getBusinessZones(businessId: string) {
  try {
    const command = new QueryCommand({
      TableName: DELIVERY_ZONES_TABLE,
      KeyConditionExpression: 'businessId = :businessId',
      ExpressionAttributeValues: {
        ':businessId': businessId
      }
    });

    const result = await docClient.send(command);
    return {
      success: true,
      zones: result.Items || [],
      count: result.Items?.length || 0
    };
  } catch (error) {
    console.error('Error getting business zones:', error);
    return {
      success: false,
      message: 'Failed to get zones',
      error: (error as Error).message
    };
  }
}

async function createDeliveryZone(zoneData: Partial<DeliveryZone>) {
  try {
    const zoneId = `zone-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    
    const zone: DeliveryZone = {
      zoneId,
      businessId: zoneData.businessId!,
      zoneName: zoneData.zoneName!,
      type: zoneData.type || 'ACTIVE',
      coordinates: zoneData.coordinates!,
      deliveryFee: zoneData.deliveryFee!,
      baseDeliveryFee: zoneData.baseDeliveryFee || zoneData.deliveryFee!,
      estimatedTime: zoneData.estimatedTime || 30,
      isActive: zoneData.isActive !== false,
      priority: zoneData.priority || 1,
      lastUpdated: new Date().toISOString(),
      createdBy: zoneData.createdBy || 'system',
      ...zoneData
    };

    const command = new PutCommand({
      TableName: DELIVERY_ZONES_TABLE,
      Item: zone
    });

    await docClient.send(command);
    
    return {
      success: true,
      zone,
      message: 'Delivery zone created successfully'
    };
  } catch (error) {
    console.error('Error creating delivery zone:', error);
    return {
      success: false,
      message: 'Failed to create zone',
      error: (error as Error).message
    };
  }
}

async function updateDeliveryZone(zoneId: string, updateData: Partial<DeliveryZone>) {
  try {
    const updateExpression = Object.keys(updateData)
      .map(key => `#${key} = :${key}`)
      .join(', ');
    
    const expressionAttributeNames = Object.keys(updateData)
      .reduce((acc, key) => ({ ...acc, [`#${key}`]: key }), {});
    
    const expressionAttributeValues = Object.entries(updateData)
      .reduce((acc, [key, value]) => ({ ...acc, [`:${key}`]: value }), {});

    const command = new UpdateCommand({
      TableName: DELIVERY_ZONES_TABLE,
      Key: { zoneId },
      UpdateExpression: `SET ${updateExpression}, lastUpdated = :lastUpdated`,
      ExpressionAttributeNames: expressionAttributeNames,
      ExpressionAttributeValues: {
        ...expressionAttributeValues,
        ':lastUpdated': new Date().toISOString()
      },
      ReturnValues: 'ALL_NEW'
    });

    const result = await docClient.send(command);
    
    return {
      success: true,
      zone: result.Attributes,
      message: 'Delivery zone updated successfully'
    };
  } catch (error) {
    console.error('Error updating delivery zone:', error);
    return {
      success: false,
      message: 'Failed to update zone',
      error: (error as Error).message
    };
  }
}

async function deleteDeliveryZone(zoneId: string) {
  try {
    const command = new DeleteCommand({
      TableName: DELIVERY_ZONES_TABLE,
      Key: { zoneId }
    });

    await docClient.send(command);
    
    return {
      success: true,
      message: 'Delivery zone deleted successfully'
    };
  } catch (error) {
    console.error('Error deleting delivery zone:', error);
    return {
      success: false,
      message: 'Failed to delete zone',
      error: (error as Error).message
    };
  }
}

// DRIVER LOCATION MANAGEMENT
async function updateDriverLocation(locationData: Partial<DriverLocation>) {
  try {
    const driverLocation: DriverLocation = {
      driverId: locationData.driverId!,
      businessId: locationData.businessId!,
      currentLat: locationData.currentLat!,
      currentLng: locationData.currentLng!,
      isAvailable: locationData.isAvailable !== false,
      isOnline: locationData.isOnline !== false,
      maxDeliveryRadius: locationData.maxDeliveryRadius || 5,
      vehicleType: locationData.vehicleType || 'MOTORCYCLE',
      lastUpdate: new Date().toISOString(),
      activeZones: locationData.activeZones || [],
      ...locationData
    };

    const command = new PutCommand({
      TableName: DRIVER_LOCATIONS_TABLE,
      Item: driverLocation
    });

    await docClient.send(command);
    
    return {
      success: true,
      driverLocation,
      message: 'Driver location updated successfully'
    };
  } catch (error) {
    console.error('Error updating driver location:', error);
    return {
      success: false,
      message: 'Failed to update driver location',
      error: (error as Error).message
    };
  }
}

async function getAvailableDrivers(businessId: string, userLocation?: string) {
  try {
    const command = new ScanCommand({
      TableName: DRIVER_LOCATIONS_TABLE,
      FilterExpression: 'businessId = :businessId AND isAvailable = :available AND isOnline = :online',
      ExpressionAttributeValues: {
        ':businessId': businessId,
        ':available': true,
        ':online': true
      }
    });

    const result = await docClient.send(command);
    let drivers = result.Items as DriverLocation[] || [];

    // Filter by distance if user location provided
    if (userLocation) {
      const [userLat, userLng] = userLocation.split(',').map(Number);
      drivers = drivers.filter(driver => {
        const distance = calculateDistance(userLat, userLng, driver.currentLat, driver.currentLng);
        return distance <= driver.maxDeliveryRadius;
      });
    }
    
    return {
      success: true,
      drivers,
      count: drivers.length,
      total: result.Items?.length || 0
    };
  } catch (error) {
    console.error('Error getting available drivers:', error);
    return {
      success: false,
      message: 'Failed to get available drivers',
      error: (error as Error).message
    };
  }
}

// UTILITY FUNCTION
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
