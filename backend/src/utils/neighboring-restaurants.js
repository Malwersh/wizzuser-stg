'use strict';

const { bounds, contains } = require('./customer-regions-313');
const { haversineDistance } = require('./haversine');
const { isIP } = require('node:net');
const previewPageSize = 8;
const expandedModes = new Set(['SAME_DISTRICT', 'SAME_GOVERNORATE', 'ADJACENT_REGIONS']);

function createNeighboringRestaurants({ db, sdk, tables, regionApi, preview }) {
 async function prepare(regionId, point) {
  if (!point || !tables.policy || !preview) return null;
  const { Item } = await db.send(new sdk.GetCommand({
   TableName: tables.policy, Key: { pk: 'OPERATIONAL_SETTINGS#DELIVERY_PRICING', sk: 'CURRENT' }, ConsistentRead: true,
   ProjectionExpression: '#values.deliveryRules', ExpressionAttributeNames: { '#values': 'values' },
  }));
  const rules = (Item?.values?.deliveryRules || []).filter(rule =>
   rule.status === 'PUBLISHED' && rule.coverage?.enabled === true &&
   rule.coverage.supportedZoneIds?.includes(regionId) &&
   Number.isSafeInteger(rule.coverage.maxRoadMeters) && rule.coverage.maxRoadMeters > 0
  );
  const maxRoadMeters = Math.max(0, ...rules.map(rule => rule.coverage.maxRoadMeters));
  if (!maxRoadMeters) return null;
  const regions = [];
  let cursor;
  if (tables.neighbors && rules.some(rule => expandedModes.has(rule.coverage.crossRegionMode))) {
   do {
    const response = await db.send(new sdk.QueryCommand({
     TableName: tables.neighbors, IndexName: 'source-region-index', KeyConditionExpression: 'source_region_id = :source',
     ExpressionAttributeValues: { ':source': regionId, ':adjacent': 'adjacent' },
     FilterExpression: 'relationship_type = :adjacent', ProjectionExpression: 'target_region_id',
     ...(cursor ? { ExclusiveStartKey: cursor } : {}),
    }));
    regions.push(...(response.Items || []).map(row => row.target_region_id));
    cursor = response.LastEvaluatedKey;
   } while (cursor);
  }
  const paths = await Promise.all([...new Set(regions)].filter(id => typeof id === 'string' && id !== regionId).map(async id => {
   try { return await regionApi.ancestry(id); }
   catch (error) { if (error.status !== 404) throw error; return null; }
  }));
  const shapes = paths.filter(Boolean).map(path => ({ regionId: path[3].base.regionId, geometry: path[3].base.geometry }));

  // The straight-line radius only rules out impossible routes. The quote verifies the road and the selected rule.
  const maxKm = maxRoadMeters / 1000;
  const latitudeDelta = maxKm / 110;
  const highestLatitude = Math.min(90, Math.abs(point.latitude) + latitudeDelta);
  const longitudeDelta = maxKm / (110 * Math.cos(highestLatitude * Math.PI / 180));
  const window = { south: point.latitude - latitudeDelta, north: point.latitude + latitudeDelta,
                   west: point.longitude - longitudeDelta, east: point.longitude + longitudeDelta };
  const nearbyShapes = shapes.filter(({ geometry }) => {
   const box = bounds(geometry);
   return box.south <= window.north && box.north >= window.south &&
    box.west <= window.east && box.east >= window.west;
  });
  return { regionId, point, maxKm, shapes: nearbyShapes, box: window };
 }

 function candidate(search, business, latitude, longitude) {
  if (!search || !business.businessId || business.acceptingOrders === false || business.ordersBlocked === true ||
      !Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  const distanceKm = haversineDistance(search.point.latitude, search.point.longitude, latitude, longitude);
  if (distanceKm > search.maxKm) return null;
  const matches = search.shapes.filter(({ geometry }) => contains(geometry, latitude, longitude));
  return matches.length === 1 ? { business: { ...business, regionId: matches[0].regionId }, distanceKm } : null;
 }

 async function qualify(search, candidates) {
  if (!candidates.length) return [];
  const rows = await preview(candidates.map(({ business }) => ({
   branchId: business.businessId, regionId: search.regionId, point: search.point,
  })));
  const approved = new Map(rows.filter(row => Number.isFinite(row.roadDistanceMeters) && row.roadDistanceMeters >= 0)
   .map(row => [row.branchId, row]));
  return candidates.flatMap(({ business }) => {
   const quote = approved.get(business.businessId);
   if (!quote) return [];
   return [{ ...business, isNeighborRegion: business.regionId !== search.regionId, roadDistanceMeters: quote.roadDistanceMeters,
    ...(Number.isFinite(quote.arrivalMinutes) ? { deliveryTime: quote.arrivalMinutes } : {}) }];
  });
 }

 return { prepare, candidate, qualify };
}

function buildNeighboringRestaurants({ db, sdk, regionApi, sourceIp, env = process.env }) {
 const target = env.NEIGHBOR_PREVIEW_FUNCTION;
 if (!target) return null;
 if (!env.NEIGHBOR_PRICING_TABLE || typeof sourceIp !== 'string' || !isIP(sourceIp)) {
  throw Object.assign(Error('DELIVERY_CHECK_UNAVAILABLE'), { status: 503, code: 'DELIVERY_CHECK_UNAVAILABLE' });
 }
 const { LambdaClient, InvokeCommand } = require('@aws-sdk/client-lambda');
 const lambda = new LambdaClient({ maxAttempts: 1 });
 return createNeighboringRestaurants({
  db, sdk, regionApi, tables: { policy: env.NEIGHBOR_PRICING_TABLE, neighbors: env.REGION_NEIGHBORS_TABLE },
  preview: async selections => {
   const result = await lambda.send(new InvokeCommand({
    FunctionName: target, Payload: Buffer.from(JSON.stringify({ neighboringBranchPreviews: selections, sourceIp })),
   }), { abortSignal: AbortSignal.timeout(10500) });
   if (result.FunctionError || !result.Payload) throw Error('DELIVERY_CHECK_UNAVAILABLE');
   const payload = JSON.parse(Buffer.from(result.Payload).toString('utf8'));
   if (!Array.isArray(payload.eligible)) throw Error('DELIVERY_CHECK_UNAVAILABLE');
   return payload.eligible;
  },
 });
}

module.exports = { createNeighboringRestaurants, buildNeighboringRestaurants, previewPageSize };
