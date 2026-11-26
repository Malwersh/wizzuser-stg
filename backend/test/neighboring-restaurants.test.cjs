'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createNeighboringRestaurants } = require('../src/utils/neighboring-restaurants');

const point = { latitude: 31.91, longitude: 44.31 };
const shape = { type: 'Polygon', coordinates: [[[44.32,31.90],[44.34,31.90],[44.34,31.93],[44.32,31.93],[44.32,31.90]]] };
class GetCommand { constructor(input) { this.input = input; } }
class QueryCommand { constructor(input) { this.input = input; } }

function fixture(mode) {
 const calls = [], selections = [];
 const service = createNeighboringRestaurants({
  db: { async send(command) {
   calls.push(command.input);
   if (command instanceof GetCommand) return { Item: { values: { deliveryRules: [{
    status: 'PUBLISHED', coverage: { enabled: true, maxRoadMeters: 5000, supportedZoneIds: ['destination'], crossRegionMode: mode },
   }] } } };
   assert.equal(command.input.FilterExpression, 'relationship_type = :adjacent');
   assert.equal(command.input.ExpressionAttributeValues[':source'], 'destination');
   if (!command.input.ExclusiveStartKey) {
    return { Items: [{ target_region_id: 'neighbor' }], LastEvaluatedKey: { neighbor_pair_id: 'destination#neighbor' } };
   }
   return { Items: [{ target_region_id: 'inactive' }, { target_region_id: 'neighbor' }] };
  } },
  sdk: { GetCommand, QueryCommand }, tables: { policy: 'staff', neighbors: 'neighbors' },
  regionApi: { async ancestry(regionId) {
   if (regionId === 'inactive') throw Object.assign(Error(), { status: 404 });
   return [{}, {}, {}, { base: { regionId, geometry: shape } }];
  } },
  async preview(batch) {
   selections.push(...batch);
   return [{ branchId: 'approved', roadDistanceMeters: 3100, arrivalMinutes: 20 }];
  },
 });
 return { calls, selections, service };
}

test('existing rules and same-region-only rules do not ask for neighboring results', async () => {
 for (const mode of [undefined, 'SAME_REGION']) {
  const f = fixture(mode);
  const coverage = await f.service.prepare('destination', point);
  assert.equal(coverage.maxKm, 5);
  assert.deepEqual(coverage.shapes, []);
  assert.equal(f.calls.length, 1);
  assert.deepEqual(f.selections, []);
 }
});

test('catalog only returns branches confirmed by the road preview inside the destination area', async () => {
 const {service} = fixture(undefined);
 const search = await service.prepare('destination', point);
 const item = businessId => ({business: {businessId, regionId: 'destination'}, distanceKm: 1});
 assert.deepEqual(await service.qualify(search, [item('rejected'), item('approved')]), [{
  businessId:'approved',regionId:'destination',isNeighborRegion:false,roadDistanceMeters:3100,deliveryTime:20,
 }]);
});

test('published rule, validated neighboring region, near point and successful road quote all govern discovery', async () => {
 const f = fixture('SAME_DISTRICT');
 const search = await f.service.prepare('destination', point);
 assert.equal(search.shapes.length, 1);
 assert.equal(f.calls.length, 3);
 assert.equal(f.service.candidate(search, { businessId: 'far' }, 32.0, 44.33), null);
 assert.equal(f.service.candidate(search, { businessId: 'blocked', ordersBlocked: true }, 31.915, 44.33), null);
 const candidate = id => f.service.candidate(search, { businessId: id }, 31.915, 44.33);
 assert.deepEqual(await f.service.qualify(search, [candidate('rejected'), candidate('approved')]), [{
  businessId: 'approved', regionId: 'neighbor', isNeighborRegion: true, roadDistanceMeters: 3100, deliveryTime: 20,
 }]);
 assert.deepEqual(f.selections, ['rejected', 'approved'].map(branchId => ({ branchId, regionId: 'destination', point })));
});
