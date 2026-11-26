'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),Module=require('node:module');
const original=Module._load;const delivered=[];
Module._load=function(id,...args){
 if(id==='./private-order-delivery-346')return {PrivateOrderApiClient:class{async send(c){delivered.push(c.input);}}};
 if(id==='./driver-trip-route-438')return {tripPoints:()=>({origin:[44.47,31.91],destination:[44.48,31.92]}),createDriverTripRouter:()=>async()=>({coordinates:[[44.47,31.91],[44.48,31.92]]})};
 return original.call(this,id,...args);
};
const {broadcast}=require('../src/live-trip-438');Module._load=original;
const event={source:'wizz.driver-location-438',schemaVersion:1,orderId:'trial',driverId:'driver'};
function db({status='heading_to_customer',finalStatus=status,liveDriver='driver'}={}){let reads=0;return{async send(c){const i=c.input;if(i.TableName==='WizzOrders')return {Item:{orderId:'trial',driverId:'driver',userSub:'owner',status:++reads===1?status:finalStatus}};if(i.TableName==='WizzDriverLiveState_staging')return{Item:{driverId:liveDriver,currentOrderId:'trial',tripLocation438:{orderId:'trial',lat:31.915,lng:44.476,accuracy:8,heading:90,observedAt:new Date().toISOString()}}};assert.equal(i.IndexName,'userId-connectedAt-index');assert.equal(i.ExpressionAttributeValues[':u'],'owner');return{Items:[{connectionId:'owner-connection'}]};}};}
test('simulated live trip reaches owner discovery with route and observed point',async()=>{delivered.length=0;assert.equal((await broadcast(db(),event)).sent,1);const p=JSON.parse(delivered[0].Data);assert.equal(p.type,'driver_location');assert.equal(p.location.latitude,31.915);assert.equal(p.route.coordinates.length,2);assert.equal(delivered[0].ConnectionId,'owner-connection');});
test('no publishing before pickup or after terminal state',async()=>{for(const status of ['confirmed','preparing','ready_for_pickup','delivered','cancelled'])assert.equal((await broadcast(db({status}),event)).skipped,true);});
test('race: cancellation during routing prevents publication',async()=>{delivered.length=0;assert.equal((await broadcast(db({finalStatus:'cancelled'}),event)).skipped,true);assert.equal(delivered.length,0);});
test('foreign assignment and public HTTP events rejected',async()=>{assert.equal((await broadcast(db({liveDriver:'other'}),event)).skipped,true);await assert.rejects(broadcast(db(),{...event,requestContext:{}}),/INTERNAL_TRACKING/);});
