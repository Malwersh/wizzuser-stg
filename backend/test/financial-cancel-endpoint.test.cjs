'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function fixture(error){
 const order={orderId:'o',userId:'u',storeId:'b',status:'pending',financialSnapshot:{},offerUsageReservation:{private:true}},calls=[];
 class GetCommand{constructor(input){this.input=input;}}
 const modules={
  '../shared/legacy-order-policy':require('../src/functions/shared/legacy-order-policy'),
  '../shared/customer-order-view':require('../src/functions/shared/customer-order-view'),
  '@aws-sdk/client-dynamodb':{DynamoDBClient:class{}},
  '@aws-sdk/lib-dynamodb':{GetCommand,DynamoDBDocumentClient:{from:()=>({send:async c=>{assert.equal(c.input.ConsistentRead,true);return {Item:order};}})}},
  '@aws-sdk/client-apigatewaymanagementapi':{},
  https:{request(){throw Error('Financial cancellation reached legacy service');}},
  '../shared/financial-pending-cancellation':{cancelFinancialPending:async input=>{calls.push(input);if(error)throw error;order.status='cancelled';return {status:'cancelled',replayed:false};}},
 };
 const exports={};
 vm.runInNewContext(fs.readFileSync(require.resolve('../src/functions/cancel-order/index'),'utf8'),{
  exports,Buffer,process:{env:{WIZZORDERS_TABLE:'WizzOrders'}},console:{log(){},error(){},warn(){}},
  require:n=>{assert.ok(n in modules,n);return modules[n];}
 });
 return {calls,invoke:()=>exports.handler({httpMethod:'POST',pathParameters:{orderId:'o'},headers:{Authorization:'Bearer customer'},body:JSON.stringify({reason:'reason'})})};
}
test('financial cancel endpoint invokes the dedicated path and returns the sanitized committed order',async()=>{
 const f=fixture(),response=await f.invoke();assert.equal(response.statusCode,200);
 assert.equal(f.calls.length,1);assert.equal(f.calls[0].event.headers.Authorization,'Bearer customer');
 const body=JSON.parse(response.body);assert.equal(body.status,'cancelled');assert.equal(body.holdReleased,false);
 assert.equal(body.order.financialSnapshot,undefined);assert.equal(body.order.offerUsageReservation,undefined);
});
test('financial cancel endpoint preserves conflict/auth status and never reports success after failed planning',async()=>{
 for(const statusCode of [401,403,409,503]){
  const f=fixture(Object.assign(Error('internal detail'),{statusCode,code:'CANCELLATION_STATE_CHANGED'}));
  const r=await f.invoke();assert.equal(r.statusCode,statusCode);
  const body=JSON.parse(r.body);assert.equal(body.success,false);assert.equal(body.code,'CANCELLATION_STATE_CHANGED');
  assert.equal(body.order,undefined);assert.ok(!r.body.includes('internal detail'));
 }
});
