// Availability Monitor & AI-Powered Optimization
import { APIGatewayProxyEvent, APIGatewayProxyResult, ScheduledEvent } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, GetCommand, PutCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';
// Note: CloudWatch metrics functionality temporarily disabled
// import { CloudWatchClient, PutMetricDataCommand } from '@aws-sdk/client-cloudwatch';

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);
// CloudWatch temporarily disabled - uncomment when AWS SDK is properly installed
// const cloudWatch = new CloudWatchClient({});

const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const ORDERS_TABLE = requireEnv('WIZZORDERS_TABLE');
const WEBSOCKET_TABLE = requireEnv('WEBSOCKET_TABLE');

interface MonitoringResult {
  overallHealth: 'HEALTHY' | 'WARNING' | 'CRITICAL';
  storesChecked: number;
  storesWithIssues: number;
  optimizationsSuggested: number;
  issues: Array<{
    storeId: string;
    storeName: string;
    issueType: string;
    severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
    description: string;
    recommendation: string;
  }>;
  optimizations: Array<{
    storeId: string;
    storeName: string;
    type: string;
    impact: 'LOW' | 'MEDIUM' | 'HIGH';
    description: string;
    suggestedAction: string;
  }>;
}

// Lambda handler for scheduled monitoring
export const handler = async (event: ScheduledEvent | APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  console.log('Starting availability monitoring and optimization...');
  
  try {
    const result = await performMonitoring();
    
    // Send alerts for critical issues
    await processAlerts(result);
    
    // CloudWatch metrics temporarily disabled
    // await publishMetrics(result);
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        success: true,
        timestamp: new Date().toISOString(),
        monitoring: result
      })
    };
  } catch (error) {
    console.error('Monitoring failed:', error);
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        success: false,
        error: 'Monitoring failed',
        details: error instanceof Error ? error.message : 'Unknown error'
      })
    };
  }
};

async function performMonitoring(): Promise<MonitoringResult> {
  const result: MonitoringResult = {
    overallHealth: 'HEALTHY',
    storesChecked: 0,
    storesWithIssues: 0,
    optimizationsSuggested: 0,
    issues: [],
    optimizations: []
  };

  try {
    // Get all active businesses
    const businesses = await getAllBusinesses();
    result.storesChecked = businesses.length;

    for (const business of businesses) {
      await checkBusinessHealth(business, result);
      await suggestOptimizations(business, result);
    }

    // Determine overall health
    const criticalIssues = result.issues.filter(i => i.severity === 'CRITICAL').length;
    const highIssues = result.issues.filter(i => i.severity === 'HIGH').length;

    if (criticalIssues > 0) {
      result.overallHealth = 'CRITICAL';
    } else if (highIssues > 2 || result.storesWithIssues > result.storesChecked * 0.3) {
      result.overallHealth = 'WARNING';
    }

    console.log(`Monitoring complete: ${result.storesChecked} stores checked, ${result.storesWithIssues} with issues`);
    return result;

  } catch (error) {
    console.error('Error in performMonitoring:', error);
    throw error;
  }
}

async function getAllBusinesses(): Promise<any[]> {
  try {
    const command = new ScanCommand({
      TableName: BUSINESSES_TABLE,
      FilterExpression: '#status = :approved',
      ExpressionAttributeNames: {
        '#status': 'status'
      },
      ExpressionAttributeValues: {
        ':approved': 'approved'
      }
    });

    const result = await docClient.send(command);
    return result.Items || [];
  } catch (error) {
    console.error('Error getting businesses:', error);
    return [];
  }
}

async function checkBusinessHealth(business: any, result: MonitoringResult): Promise<void> {
  const storeId = business.businessId;
  const storeName = business.businessName || 'Unknown Store';
  let hasIssues = false;

  try {
    // Check 1: Working hours configuration
    if (!business.workingHours || Object.keys(business.workingHours).length === 0) {
      result.issues.push({
        storeId,
        storeName,
        issueType: 'MISSING_WORKING_HOURS',
        severity: 'HIGH',
        description: 'No working hours configured',
        recommendation: 'Configure working hours for all days of the week'
      });
      hasIssues = true;
    }

    // Check 2: Location data
    if (!business.latitude || !business.longitude) {
      result.issues.push({
        storeId,
        storeName,
        issueType: 'MISSING_LOCATION',
        severity: 'HIGH',
        description: 'Missing GPS coordinates',
        recommendation: 'Add accurate GPS coordinates for delivery calculation'
      });
      hasIssues = true;
    }

    // Check 3: Recent order volume and capacity
    const recentOrders = await getRecentOrders(storeId);
    const currentHour = new Date().getHours();
    const hourlyOrders = recentOrders.filter(order => {
      const orderTime = new Date(order.createdAt);
      return orderTime.getHours() === currentHour;
    }).length;

    if (hourlyOrders > 20) { // Threshold for high volume
      result.issues.push({
        storeId,
        storeName,
        issueType: 'HIGH_ORDER_VOLUME',
        severity: 'MEDIUM',
        description: `High order volume: ${hourlyOrders} orders this hour`,
        recommendation: 'Consider increasing lead time or enabling order throttling'
      });
      hasIssues = true;
    }

    // Check 4: Delivery coverage
    if (business.deliverySettings?.enabled && !business.deliverySettings?.zones?.length) {
      result.issues.push({
        storeId,
        storeName,
        issueType: 'MISSING_DELIVERY_ZONES',
        severity: 'MEDIUM',
        description: 'Delivery enabled but no zones configured',
        recommendation: 'Configure delivery zones or disable delivery'
      });
      hasIssues = true;
    }

    if (hasIssues) {
      result.storesWithIssues++;
    }

  } catch (error) {
    console.error(`Error checking health for store ${storeId}:`, error);
    result.issues.push({
      storeId,
      storeName,
      issueType: 'MONITORING_ERROR',
      severity: 'LOW',
      description: 'Failed to perform health check',
      recommendation: 'Check store configuration and try again'
    });
    result.storesWithIssues++;
  }
}

async function suggestOptimizations(business: any, result: MonitoringResult): Promise<void> {
  const storeId = business.businessId;
  const storeName = business.businessName || 'Unknown Store';

  try {
    // Optimization 1: Lead time optimization based on order history
    const recentOrders = await getRecentOrders(storeId);
    if (recentOrders.length > 10) {
      const avgFulfillmentTime = calculateAverageFulfillmentTime(recentOrders);
      const currentLeadTime = business.leadTime || 30;

      if (avgFulfillmentTime < currentLeadTime * 0.7) {
        result.optimizations.push({
          storeId,
          storeName,
          type: 'REDUCE_LEAD_TIME',
          impact: 'HIGH',
          description: `Average fulfillment: ${avgFulfillmentTime}min, current lead time: ${currentLeadTime}min`,
          suggestedAction: `Consider reducing lead time to ${Math.ceil(avgFulfillmentTime * 1.2)}min`
        });
        result.optimizationsSuggested++;
      } else if (avgFulfillmentTime > currentLeadTime * 1.2) {
        result.optimizations.push({
          storeId,
          storeName,
          type: 'INCREASE_LEAD_TIME',
          impact: 'HIGH',
          description: `Average fulfillment: ${avgFulfillmentTime}min, current lead time: ${currentLeadTime}min`,
          suggestedAction: `Consider increasing lead time to ${Math.ceil(avgFulfillmentTime * 1.1)}min`
        });
        result.optimizationsSuggested++;
      }
    }

    // Optimization 2: Pricing optimization for delivery distance
    if (business.deliverySettings?.enabled && !business.deliverySettings?.distancePricing) {
      result.optimizations.push({
        storeId,
        storeName,
        type: 'ENABLE_DISTANCE_PRICING',
        impact: 'MEDIUM',
        description: 'Distance-based pricing not configured',
        suggestedAction: 'Enable distance-based delivery pricing to optimize revenue'
      });
      result.optimizationsSuggested++;
    }

    // Optimization 3: Schedule slots utilization
    const scheduleSlots = business.scheduleSlots;
    if (scheduleSlots?.enabled && scheduleSlots?.slots?.length > 0) {
      const lowUtilizationSlots = scheduleSlots.slots.filter((slot: any) => 
        slot.utilization && slot.utilization < 0.3
      );
      
      if (lowUtilizationSlots.length > 0) {
        result.optimizations.push({
          storeId,
          storeName,
          type: 'OPTIMIZE_SCHEDULE_SLOTS',
          impact: 'MEDIUM',
          description: `${lowUtilizationSlots.length} slots with low utilization`,
          suggestedAction: 'Consider adjusting time slots or pricing for better utilization'
        });
        result.optimizationsSuggested++;
      }
    }

  } catch (error) {
    console.error(`Error suggesting optimizations for store ${storeId}:`, error);
  }
}

async function getRecentOrders(businessId: string): Promise<any[]> {
  try {
    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    
    const command = new QueryCommand({
      TableName: ORDERS_TABLE,
      IndexName: 'GSI_BusinessId',
      KeyConditionExpression: 'businessId = :businessId',
      FilterExpression: 'createdAt >= :oneDayAgo',
      ExpressionAttributeValues: {
        ':businessId': businessId,
        ':oneDayAgo': oneDayAgo
      }
    });

    const result = await docClient.send(command);
    return result.Items || [];
  } catch (error) {
    console.error('Error getting recent orders:', error);
    return [];
  }
}

function calculateAverageFulfillmentTime(orders: any[]): number {
  const completedOrders = orders.filter(order => 
    order.status === 'completed' && order.completedAt && order.createdAt
  );

  if (completedOrders.length === 0) return 30; // Default

  const totalTime = completedOrders.reduce((total, order) => {
    const created = new Date(order.createdAt).getTime();
    const completed = new Date(order.completedAt).getTime();
    return total + (completed - created);
  }, 0);

  return Math.round(totalTime / completedOrders.length / (1000 * 60)); // Convert to minutes
}

async function processAlerts(result: MonitoringResult): Promise<void> {
  const criticalIssues = result.issues.filter(i => i.severity === 'CRITICAL');
  
  if (criticalIssues.length > 0) {
    console.log(`🚨 CRITICAL ALERT: ${criticalIssues.length} critical issues detected`);
    
    // Here you would typically send alerts to:
    // - SNS topics for email/SMS alerts
    // - Slack webhooks
    // - Monitoring dashboards
    
    for (const issue of criticalIssues) {
      console.log(`🚨 ${issue.storeName}: ${issue.description}`);
    }
  }

  if (result.overallHealth === 'WARNING') {
    console.log(`⚠️  WARNING: System health is degraded (${result.storesWithIssues}/${result.storesChecked} stores with issues)`);
  }
}

// CloudWatch metrics publishing temporarily disabled
/*
async function publishMetrics(result: MonitoringResult): Promise<void> {
  try {
    const metricData = [
      {
        MetricName: 'StoresChecked',
        Value: result.storesChecked,
        Unit: 'Count',
        Timestamp: new Date()
      },
      {
        MetricName: 'StoresWithIssues',
        Value: result.storesWithIssues,
        Unit: 'Count',
        Timestamp: new Date()
      },
      {
        MetricName: 'CriticalIssues',
        Value: result.issues.filter(i => i.severity === 'CRITICAL').length,
        Unit: 'Count',
        Timestamp: new Date()
      },
      {
        MetricName: 'OptimizationsSuggested',
        Value: result.optimizationsSuggested,
        Unit: 'Count',
        Timestamp: new Date()
      }
    ];

    const command = new PutMetricDataCommand({
      Namespace: 'WizzUser/Availability',
      MetricData: metricData
    });

    await cloudWatch.send(command);
    console.log('Metrics published to CloudWatch');
  } catch (error) {
    console.error('Error publishing metrics:', error);
  }
}
*/
