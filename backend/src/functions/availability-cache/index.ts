// Smart Availability Cache with Real-time Updates
import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const CACHE_TABLE = process.env.AVAILABILITY_CACHE_TABLE || 'order-receiver-availability-cache-dev';
const CACHE_TTL_SECONDS = 300; // 5 minutes default

interface CacheEntry {
  cacheKey: string;
  storeId: string;
  availability: any;
  lastUpdated: string;
  ttl: number;
  version: number;
  invalidationTriggers: string[];
}

interface CacheInvalidationEvent {
  trigger: 'ORDER_CREATED' | 'ORDER_STATUS_CHANGED' | 'BUSINESS_STATUS_CHANGED' | 'WORKING_HOURS_UPDATED' | 'MANUAL_REFRESH';
  storeId: string;
  timestamp: string;
  metadata?: any;
}

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
};

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  console.log('Availability Cache Handler:', JSON.stringify(event, null, 2));

  try {
    if (event.httpMethod === 'OPTIONS') {
      return { statusCode: 200, headers, body: '' };
    }

    const { httpMethod, path } = event;

    // GET /cache/availability/{storeId} - Get cached availability
    if (httpMethod === 'GET' && path.includes('/cache/availability/')) {
      const storeId = event.pathParameters?.storeId;
      const userLocation = event.queryStringParameters?.location;
      const forceRefresh = event.queryStringParameters?.refresh === 'true';
      
      if (!storeId) {
        return {
          statusCode: 400,
          headers,
          body: JSON.stringify({ success: false, message: 'Store ID is required' })
        };
      }

      const result = await getCachedAvailability(storeId, userLocation, forceRefresh);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    // POST /cache/invalidate - Invalidate cache for specific triggers
    if (httpMethod === 'POST' && path.includes('/cache/invalidate')) {
      const invalidationEvent: CacheInvalidationEvent = JSON.parse(event.body || '{}');
      const result = await invalidateCache(invalidationEvent);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    // PUT /cache/warm - Warm cache for specific stores
    if (httpMethod === 'PUT' && path.includes('/cache/warm')) {
      const { storeIds } = JSON.parse(event.body || '{}');
      const result = await warmCache(storeIds);
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify(result)
      };
    }

    // GET /cache/stats - Get cache statistics
    if (httpMethod === 'GET' && path.includes('/cache/stats')) {
      const result = await getCacheStats();
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
    console.error('Cache handler error:', error);
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

// GET CACHED AVAILABILITY WITH SMART REFRESH
async function getCachedAvailability(storeId: string, userLocation?: string, forceRefresh = false) {
  try {
    const cacheKey = generateCacheKey(storeId, userLocation);
    console.log(`🔍 Checking cache for key: ${cacheKey}`);

    // Try to get from cache first
    if (!forceRefresh) {
      const cached = await getCacheEntry(cacheKey);
      if (cached && !isCacheExpired(cached)) {
        console.log(`✅ Cache hit for ${storeId}`);
        return {
          success: true,
          availability: cached.availability,
          source: 'cache',
          cached: true,
          lastUpdated: cached.lastUpdated,
          version: cached.version
        };
      }
    }

    console.log(`🔄 Cache miss or refresh for ${storeId}, fetching fresh data`);
    
    // Fetch fresh availability data
    const freshAvailability = await fetchFreshAvailability(storeId, userLocation);
    
    // Store in cache
    await setCacheEntry(cacheKey, storeId, freshAvailability);
    
    return {
      success: true,
      availability: freshAvailability,
      source: 'fresh',
      cached: false,
      lastUpdated: new Date().toISOString(),
      version: 1
    };

  } catch (error) {
    console.error('Error getting cached availability:', error);
    return {
      success: false,
      message: 'Failed to get availability',
      error: (error as Error).message
    };
  }
}

// FETCH FRESH AVAILABILITY DATA
async function fetchFreshAvailability(storeId: string, userLocation?: string) {
  console.log(`🔄 Fetching fresh availability for store ${storeId}`);
  
  // Call the main store-availability function
  const availabilityFunction = process.env.STORE_AVAILABILITY_FUNCTION_NAME || 'store-availability';
  
  // For now, we'll simulate calling the availability function
  // In production, this would invoke the Lambda or call the logic directly
  
  // Mock fresh availability data - replace with actual function call
  const mockAvailability = {
    storeId,
    storeName: `Store ${storeId}`,
    status: 'OPEN',
    reasonCodes: [],
    canOrderNow: true,
    canSchedule: true,
    allowPickup: true,
    allowDelivery: true,
    leadTimeMins: 30,
    pricing: {
      deliveryFee: 5000,
      originalDeliveryFee: 5000,
      dynamicPricing: false,
      minimumOrder: 15000
    },
    capacity: {
      currentOrders: 5,
      maxOrdersPerHour: 20,
      utilizationPercent: 25,
      isNearCapacity: false,
      waitTimeAdded: 0
    },
    metadata: {
      timezone: 'Asia/Baghdad',
      currentTime: new Date().toISOString(),
      lastUpdated: new Date().toISOString()
    }
  };
  
  return mockAvailability;
}

// CACHE ENTRY MANAGEMENT
async function getCacheEntry(cacheKey: string): Promise<CacheEntry | null> {
  try {
    const command = new GetCommand({
      TableName: CACHE_TABLE,
      Key: { cacheKey }
    });
    
    const result = await docClient.send(command);
    return result.Item as CacheEntry || null;
  } catch (error) {
    console.error('Error getting cache entry:', error);
    return null;
  }
}

async function setCacheEntry(cacheKey: string, storeId: string, availability: any) {
  try {
    const ttl = Math.floor(Date.now() / 1000) + CACHE_TTL_SECONDS;
    const cacheEntry: CacheEntry = {
      cacheKey,
      storeId,
      availability,
      lastUpdated: new Date().toISOString(),
      ttl,
      version: 1,
      invalidationTriggers: ['ORDER_CREATED', 'BUSINESS_STATUS_CHANGED', 'WORKING_HOURS_UPDATED']
    };
    
    const command = new PutCommand({
      TableName: CACHE_TABLE,
      Item: cacheEntry
    });
    
    await docClient.send(command);
    console.log(`✅ Cached availability for ${storeId}`);
  } catch (error) {
    console.error('Error setting cache entry:', error);
  }
}

function isCacheExpired(cacheEntry: CacheEntry): boolean {
  const currentTimestamp = Math.floor(Date.now() / 1000);
  return currentTimestamp > cacheEntry.ttl;
}

// CACHE INVALIDATION
async function invalidateCache(invalidationEvent: CacheInvalidationEvent) {
  try {
    console.log(`🗑️ Invalidating cache for trigger: ${invalidationEvent.trigger}, store: ${invalidationEvent.storeId}`);
    
    const storeId = invalidationEvent.storeId;
    
    // For simplicity, we'll delete all cache entries for this store
    // In production, you might want to be more selective based on triggers
    const cacheKeysToInvalidate = [
      generateCacheKey(storeId), // Base key without location
      // Could scan for all keys starting with storeId if needed
    ];
    
    const deletePromises = cacheKeysToInvalidate.map(async (cacheKey) => {
      try {
        const command = new DeleteCommand({
          TableName: CACHE_TABLE,
          Key: { cacheKey }
        });
        await docClient.send(command);
        console.log(`✅ Invalidated cache key: ${cacheKey}`);
      } catch (error) {
        console.error(`❌ Failed to invalidate cache key: ${cacheKey}`, error);
      }
    });
    
    await Promise.all(deletePromises);
    
    return {
      success: true,
      message: `Cache invalidated for store ${storeId}`,
      trigger: invalidationEvent.trigger,
      timestamp: new Date().toISOString()
    };
    
  } catch (error) {
    console.error('Error invalidating cache:', error);
    return {
      success: false,
      message: 'Failed to invalidate cache',
      error: (error as Error).message
    };
  }
}

// CACHE WARMING
async function warmCache(storeIds: string[]) {
  try {
    console.log(`🔥 Warming cache for ${storeIds.length} stores`);
    
    const warmPromises = storeIds.map(async (storeId) => {
      try {
        await getCachedAvailability(storeId, undefined, true); // Force refresh
        return { storeId, success: true };
      } catch (error) {
        console.error(`Failed to warm cache for store ${storeId}:`, error);
        return { storeId, success: false, error: (error as Error).message };
      }
    });
    
    const results = await Promise.all(warmPromises);
    const successful = results.filter(r => r.success).length;
    const failed = results.filter(r => !r.success).length;
    
    return {
      success: true,
      message: `Cache warmed for ${successful} stores`,
      stats: { successful, failed, total: storeIds.length },
      results
    };
    
  } catch (error) {
    console.error('Error warming cache:', error);
    return {
      success: false,
      message: 'Failed to warm cache',
      error: (error as Error).message
    };
  }
}

// CACHE STATISTICS
async function getCacheStats() {
  try {
    // In a real implementation, you'd scan the cache table for stats
    // For now, return mock stats
    return {
      success: true,
      stats: {
        totalEntries: 150,
        hitRate: 87.5,
        avgTtl: 240,
        topStores: [
          { storeId: 'store-1', requests: 245, hitRate: 92 },
          { storeId: 'store-2', requests: 189, hitRate: 88 },
          { storeId: 'store-3', requests: 156, hitRate: 85 }
        ],
        invalidations: {
          ORDER_CREATED: 45,
          BUSINESS_STATUS_CHANGED: 12,
          WORKING_HOURS_UPDATED: 8,
          MANUAL_REFRESH: 23
        }
      },
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    console.error('Error getting cache stats:', error);
    return {
      success: false,
      message: 'Failed to get cache stats',
      error: (error as Error).message
    };
  }
}

// UTILITY FUNCTIONS
function generateCacheKey(storeId: string, userLocation?: string): string {
  const baseKey = `availability:${storeId}`;
  
  if (userLocation) {
    // Round coordinates to reduce cache fragmentation
    const [lat, lng] = userLocation.split(',').map(coord => Math.round(parseFloat(coord) * 100) / 100);
    return `${baseKey}:${lat},${lng}`;
  }
  
  return baseKey;
}

// CACHE MIDDLEWARE FOR EXPRESS/LAMBDA
export const cacheMiddleware = {
  // Pre-populate cache before high-traffic times
  async scheduleWarmup(storeIds: string[]) {
    console.log(`🕐 Scheduled cache warmup for ${storeIds.length} stores`);
    return await warmCache(storeIds);
  },
  
  // Auto-invalidate based on business events
  async onOrderCreated(storeId: string, orderData: any) {
    await invalidateCache({
      trigger: 'ORDER_CREATED',
      storeId,
      timestamp: new Date().toISOString(),
      metadata: { orderId: orderData.orderId }
    });
  },
  
  async onBusinessStatusChanged(storeId: string, newStatus: any) {
    await invalidateCache({
      trigger: 'BUSINESS_STATUS_CHANGED',
      storeId,
      timestamp: new Date().toISOString(),
      metadata: { newStatus }
    });
  },
  
  async onWorkingHoursUpdated(storeId: string) {
    await invalidateCache({
      trigger: 'WORKING_HOURS_UPDATED',
      storeId,
      timestamp: new Date().toISOString()
    });
  }
};
