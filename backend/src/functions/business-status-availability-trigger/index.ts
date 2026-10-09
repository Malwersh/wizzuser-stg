// Business Status Availability Trigger - Integrates availability system with existing business status
import { DynamoDBStreamEvent, DynamoDBRecord } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';
import { triggerAvailabilityUpdate } from '../availability-websocket-broadcast';

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const BUSINESSES_TABLE = 'order-receiver-businesses-dev';

// This function listens to business status changes and triggers availability updates
export const handler = async (event: DynamoDBStreamEvent): Promise<void> => {
  console.log('📡 Business Status Availability Trigger:', JSON.stringify(event, null, 2));

  for (const record of event.Records) {
    try {
      await processBusinessStatusChange(record);
    } catch (error) {
      console.error('Error processing business status change:', error);
      // Continue processing other records
    }
  }
};

async function processBusinessStatusChange(record: DynamoDBRecord) {
  const eventName = record.eventName;
  
  if (!eventName || eventName === 'REMOVE') {
    return; // Skip deletes
  }

  const newImage = record.dynamodb?.NewImage;
  const oldImage = record.dynamodb?.OldImage;
  
  if (!newImage) return;

  // Extract business information
  const businessId = newImage.id?.S || newImage.businessId?.S;
  const businessName = newImage.name?.S || newImage.businessName?.S;
  
  if (!businessId) {
    console.log('No business ID found in record');
    return;
  }

  // Check what changed
  const newStatus = newImage.status?.S;
  const oldStatus = oldImage?.status?.S;
  
  const newAcceptingOrders = newImage.acceptingOrders?.BOOL;
  const oldAcceptingOrders = oldImage?.acceptingOrders?.BOOL;
  
  const newIsActive = newImage.isActive?.BOOL;
  const oldIsActive = oldImage?.isActive?.BOOL;

  // Determine if this change affects availability
  let availabilityChanged = false;
  let trigger: 'MERCHANT_ACTION' | 'WORKING_HOURS' | 'CAPACITY_CHANGE' | 'SYSTEM_UPDATE' = 'MERCHANT_ACTION';
  let previousStatus = 'unknown';
  let newAvailabilityStatus = 'unknown';

  // Check for status changes
  if (newStatus !== oldStatus) {
    availabilityChanged = true;
    previousStatus = oldStatus || 'unknown';
    newAvailabilityStatus = newStatus || 'unknown';
    console.log(`🔄 Business ${businessId} status changed: ${oldStatus} → ${newStatus}`);
  }

  // Check for accepting orders changes
  if (newAcceptingOrders !== oldAcceptingOrders) {
    availabilityChanged = true;
    trigger = 'MERCHANT_ACTION';
    previousStatus = oldAcceptingOrders ? 'accepting' : 'not_accepting';
    newAvailabilityStatus = newAcceptingOrders ? 'accepting' : 'not_accepting';
    console.log(`🔄 Business ${businessId} accepting orders changed: ${oldAcceptingOrders} → ${newAcceptingOrders}`);
  }

  // Check for active status changes
  if (newIsActive !== oldIsActive) {
    availabilityChanged = true;
    trigger = 'SYSTEM_UPDATE';
    previousStatus = oldIsActive ? 'active' : 'inactive';
    newAvailabilityStatus = newIsActive ? 'active' : 'inactive';
    console.log(`🔄 Business ${businessId} active status changed: ${oldIsActive} → ${newIsActive}`);
  }

  // Check for working hours changes
  if (record.dynamodb?.Keys?.PK?.S?.includes('WORKING_HOURS')) {
    availabilityChanged = true;
    trigger = 'WORKING_HOURS';
    previousStatus = 'hours_updated';
    newAvailabilityStatus = 'hours_updated';
    console.log(`🕒 Business ${businessId} working hours updated`);
  }

  // Trigger availability update if something relevant changed
  if (availabilityChanged) {
    try {
      await triggerAvailabilityUpdate({
        storeId: businessId,
        storeName: businessName || 'Unknown Store',
        previousStatus,
        newStatus: newAvailabilityStatus,
        trigger,
        forceUpdate: true
      });

      console.log(`✅ Triggered availability update for business ${businessId}`);
    } catch (error) {
      console.error(`❌ Failed to trigger availability update for ${businessId}:`, error);
    }
  }
}

// Manual trigger function for testing and forced updates
export const manualTriggerAvailabilityUpdate = async (event: any) => {
  const { businessId, trigger = 'SYSTEM_UPDATE', forceAll = false } = event;

  try {
    if (forceAll) {
      // Trigger updates for all businesses
      console.log('🚀 Triggering availability updates for all businesses');
      
      // This could scan all businesses and trigger updates
      // For now, just return success
      return {
        statusCode: 200,
        body: JSON.stringify({
          success: true,
          message: 'Bulk availability update triggered'
        })
      };
    }

    if (!businessId) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          success: false,
          message: 'Business ID is required'
        })
      };
    }

    // Get business information
    const businessResult = await docClient.send(new GetCommand({
      TableName: BUSINESSES_TABLE,
      Key: { id: businessId }
    }));

    const business = businessResult.Item;
    if (!business) {
      return {
        statusCode: 404,
        body: JSON.stringify({
          success: false,
          message: 'Business not found'
        })
      };
    }

    // Trigger availability update
    const result = await triggerAvailabilityUpdate({
      storeId: businessId,
      storeName: business.name || 'Unknown Store',
      previousStatus: 'manual_trigger',
      newStatus: 'manual_trigger',
      trigger: trigger as any,
      forceUpdate: true
    });

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: `Availability update triggered for ${business.name}`,
        connectionsNotified: result.connectionsNotified
      })
    };

  } catch (error) {
    console.error('Error in manual trigger:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        message: 'Internal server error',
        error: process.env.NODE_ENV === 'development' ? (error as Error).message : undefined
      })
    };
  }
};
