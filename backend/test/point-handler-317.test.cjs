const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function fixture({enabled=true,rateError=false,entry="point-handler-317"}={}){let legacy=0,preview=0,rate=0;const runtime={pointSelection317:v=>{if(Object.keys(v).sort().join(',')!=='branchId,point,regionId')throw Object.assign(Error('INVALID_STOREFRONT_REQUEST'),{code:'INVALID_STOREFRONT_REQUEST'});return v;},DynamoDBClient:class{},DynamoDBDocumentClient:{from:()=>({})},SecretsManagerClient:class{},CognitoIdentityProviderClient:class{},readDeliveryOperations:async()=>({values:{quoteMaxPerCustomerPerMinute:5}}),reservePublicPointPreview317:async o=>{rate++;assert.equal(o.sourceIp,'192.0.2.1');if(rateError)throw Object.assign(Error('QUOTE_RATE_LIMITED'),{code:'QUOTE_RATE_LIMITED'});},createStagingPointStorefrontPreview317:()=>({preview:async v=>{preview++;return {branchId:v.branchId,regionId:v.regionId,customerDeliveryFee:{minorAmount:1500000},informationalOnly:true};}})};
function load(filename) {
 const module={exports:{}};
 vm.runInNewContext(fs.readFileSync(__dirname+'/../src/functions/delivery-quotes/'+filename+'.js','utf8'),{
  module,exports:module.exports,Buffer,console:{info(){},warn(){}},
  process:{env:{STOREFRONT_POINT_PREVIEW_ENABLED:enabled?'true':'false',DELIVERY_QUOTES_ENABLED:'true',ENVIRONMENT:'staging',AWS_REGION:'us-east-1'}},
  require:n=>n==='node:net'?require(n):n==='../create-order/account-guard'?{}:n==='./neighboring-reader'?load('neighboring-reader'):n==='./legacy-index-317'?{handler:async()=>{legacy++;return {statusCode:401};}}:runtime
 });
 return module.exports;
}
const handler=load(entry).handler;
return {run:patch=>handler({httpMethod:'POST',body:JSON.stringify({action:'storefront_point_preview',branchId:'b',regionId:'r',point:{latitude:31,longitude:44}}),requestContext:{identity:{sourceIp:'192.0.2.1'}},...patch}),invoke:handler,counts:()=>({legacy,preview,rate})};}
test('public point action is isolated; unauthenticated financial actions still use unchanged legacy handler',async()=>{const f=fixture();assert.equal((await f.run()).statusCode,200);assert.equal((await f.run({body:JSON.stringify({branchId:'b',addressId:'a',requestId:'x'})})).statusCode,401);assert.deepEqual(f.counts(),{legacy:1,preview:1,rate:1});});
test('disabled feature, malformed selection, query injection and rate limit do not invoke provider',async()=>{assert.equal((await fixture({enabled:false}).run()).statusCode,503);const f=fixture();assert.equal((await f.run({body:JSON.stringify({action:'storefront_point_preview',branchId:'b',regionId:'r',point:{},addressId:'foreign'})})).statusCode,400);assert.equal((await f.run({queryStringParameters:{quoteId:'x'}})).statusCode,400);assert.equal(f.counts().preview,0);const g=fixture({rateError:true});assert.equal((await g.run()).statusCode,429);assert.equal(g.counts().preview,0);});

test('public path cannot be used to dispatch another financial action',async()=>{const f=fixture();assert.equal((await f.run({resource:'/storefront-point-preview',body:JSON.stringify({branchId:'b',addressId:'a',requestId:'x'})})).statusCode,400);assert.equal(f.counts().legacy,0);});
test('direct catalog invocation is metered and cannot be routed from a public body',async()=>{
 const f=fixture(),batch={sourceIp:'192.0.2.1',neighboringBranchPreviews:[{branchId:'b',regionId:'r',point:{latitude:31,longitude:44}}]};
 assert.equal((await f.run({resource:'/storefront-point-preview',body:JSON.stringify(batch)})).statusCode,400);
 assert.equal(f.counts().preview,0);
 assert.equal((await f.invoke(batch)).eligible[0].branchId,'b');
 assert.deepEqual(f.counts(),{legacy:0,preview:1,rate:1});
 assert.equal((await f.invoke({...batch,sourceIp:'invalid'})).eligible.length,0);
 assert.equal((await f.invoke({...batch,neighboringBranchPreviews:Array(9).fill(batch.neighboringBranchPreviews[0])})).eligible.length,0);
 assert.deepEqual(f.counts(),{legacy:0,preview:1,rate:1});
});
test('the standard quote entry accepts the same private catalog request',async()=>{
 const f=fixture({entry:'index'});
 const reply=await f.invoke({sourceIp:'192.0.2.1',neighboringBranchPreviews:[{
  branchId:'b',regionId:'r',point:{latitude:31,longitude:44}
 }]});
 assert.equal(reply.eligible[0].branchId,'b');
 assert.deepEqual(f.counts(),{legacy:0,preview:1,rate:1});
});
