'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const policy=require('../src/functions/shared/legacy-order-policy');
class GetCommand{constructor(input){this.input=input;}}class UpdateCommand{constructor(input){this.input=input;}}
function fixture(row){let writes=0,update;const exports={};const db={async send(c){if(c instanceof GetCommand)return {Item:structuredClone(row)};update=c.input;writes++;throw Object.assign(Error('race'),{name:'ConditionalCheckFailedException'});}};
 const modules={'../create-order/commercial-order-router':require('../src/functions/create-order/commercial-order-router'),'../shared/legacy-order-policy':policy,'../shared/customer-order-view':require('../src/functions/shared/customer-order-view'),'@aws-sdk/client-dynamodb':{DynamoDBClient:class{}},'@aws-sdk/lib-dynamodb':{GetCommand,UpdateCommand,DynamoDBDocumentClient:{from:()=>db}}};
 vm.runInNewContext(fs.readFileSync(process.env.STATUS_HANDLER_FILE||'backend/src/functions/update-order-status/index.js','utf8'),{exports,require:n=>{if(n in modules)return modules[n];throw Error('unexpected side effect '+n);},process:{env:{WIZZORDERS_TABLE:'WizzOrders'}},Date,console:{log(){},warn(){},error(){}}});
 return {invoke:()=>exports.handler({httpMethod:'PUT',pathParameters:{orderId:'o'},body:JSON.stringify({status:'delivered'})}),writes:()=>writes,update:()=>update};
}
test('actual generic status handler rejects all financial markers before a status write or notification',async()=>{
 for(const field of policy.FINANCIAL_FIELDS){const f=fixture({PK:'ORDER#o',SK:'META',rev:1,storeId:'b',status:'picked_up',[field]:null});const r=await f.invoke();assert.equal(r.statusCode,409);assert.equal(JSON.parse(r.body).code,'FINANCIAL_ORDER_WORKFLOW_REQUIRED');assert.equal(f.writes(),0);}
});
test('legacy generic handler preserves revision CAS and fences financial markers appearing after its read',async()=>{
 const f=fixture({PK:'ORDER#o',SK:'META',rev:1,storeId:'b',status:'picked_up'});const r=await f.invoke();assert.equal(r.statusCode,409);assert.equal(f.writes(),1);
 assert.match(f.update().ConditionExpression,/#rev = :currentRev/);for(const field of policy.FINANCIAL_FIELDS)assert.ok(f.update().ConditionExpression.includes('attribute_not_exists('+field+')'));
});
