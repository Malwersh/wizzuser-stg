const {test}=require('node:test'),assert=require('node:assert/strict');
const {pointView321,prepare321}=require('../src/functions/create-order/point-invoice-321');
for(const name of ['GetCommand','QueryCommand','TransactWriteCommand','PutCommand','UpdateCommand','DeleteCommand'])global[name]=({[name]:class{constructor(input){this.input=input;}}})[name];
test('point and quote remain per-request memory; no mutation can escape to real database',async()=>{
 const calls=[],base={async send(c){calls.push(c);return{Item:{real:true}};}},address={addressId:'point',userId:'owner',latitude:31,longitude:44},v=pointView321(base,{address,userId:'owner'});
 assert.deepEqual((await v.db.send(new GetCommand({TableName:'WizzUser_addresses_staging',Key:{addressId:'point'}}))).Item,address);assert.equal(calls.length,0);
 const item={pk:'CUSTOMER#owner',sk:'QUOTE#q'};
 await v.db.send(new TransactWriteCommand({TransactItems:[{ConditionCheck:{TableName:'profile'}},{Put:{TableName:'staging-DeliveryQuotes',Item:item}}]}));
 assert.deepEqual((await v.db.send(new GetCommand({TableName:'staging-DeliveryQuotes',Key:item}))).Item,item);assert.equal(calls.length,1);assert(calls[0].input.TransactItems.every(o=>o.ConditionCheck));
 await assert.rejects(v.db.send(new TransactWriteCommand({TransactItems:[{Put:{TableName:'WizzOrders',Item:{}}}]})));
 v.seal();for(const name of [PutCommand,UpdateCommand,DeleteCommand,TransactWriteCommand])await assert.rejects(v.db.send(new name({})));
 await v.db.send(new GetCommand({TableName:'catalog',Key:{id:'p'}}));assert.equal(calls.length,2);
 const other=pointView321(base,{address:{...address,latitude:32},userId:'owner'});assert.equal((await other.db.send(new GetCommand({TableName:'staging-DeliveryQuotes',Key:item}))).Item,undefined);
});
test('point action cannot run on order creation route, accept consent/quote/address or malformed point',async()=>{
 const env={POINT_INVOICE_ENABLED:'true',ENVIRONMENT:'staging',USERS_TABLE:'WizzUser_users_staging',AWS_REGION:'us-east-1'};
 const body={action:'preview_commercial_point',userId:'owner',items:[{}],pricingPoint:{latitude:31,longitude:44}};
 for(const [route,changes]of [['/orders',{}],['/orders/commercial-preview',{commercialConsent:{}}],['/orders/commercial-preview',{quoteId:'q'}],['/orders/commercial-preview',{deliveryAddress:{}}],['/orders/commercial-preview',{pricingPoint:{latitude:'31',longitude:44}}]])await assert.rejects(prepare321({event:{resource:route},body:{...body,...changes},env}),e=>['INVALID_POINT_INVOICE'].includes(e.code));
});
test('authenticated point preview runs existing invoice calculation privately and strips all order/quote authority',async()=>{
 const profile={userId:'owner',cognitoSub:'sub',isActive:true};const calls=[];
 const base={async send(c){calls.push(c);assert.equal(c.constructor.name,'GetCommand');assert.equal(c.input.TableName,'WizzUser_users_staging');return{Item:profile};}};
 const env={POINT_INVOICE_ENABLED:'true',ENVIRONMENT:'staging',AWS_REGION:'us-east-1',USERS_TABLE:'WizzUser_users_staging',USER_POOL_ID:'pool',USER_POOL_CLIENT_ID:'client',MAPBOX_SECRET_ARN:'server-only'};
 const token='header.'+Buffer.from(JSON.stringify({sub:'sub',iss:'https://cognito-idp.us-east-1.amazonaws.com/pool',client_id:'client',token_use:'access'})).toString('base64url')+'.signature';
 const event={resource:'/orders/commercial-preview',headers:{Authorization:'Bearer '+token}};
 let savedQuote;
 const runtime={GetCommand,GetUserCommand:class{},CognitoIdentityProviderClient:class{async send(){return{Username:'user',UserAttributes:[{Name:'sub',Value:'sub'}]};}},SecretsManagerClient:class{},createStagingSecretDeliveryRouting:()=>({}),createStagingDeliveryQuotes:({db})=>({async create(r){const a=(await db.send(new GetCommand({TableName:'WizzUser_addresses_staging',Key:{addressId:r.addressId}}))).Item;assert.equal(a.latitude,31);assert.equal(a.neighborhood,undefined);savedQuote={pk:'CUSTOMER#owner',sk:'QUOTE#'+r.requestId};await db.send(new TransactWriteCommand({TransactItems:[{Put:{TableName:'staging-DeliveryQuotes',Item:savedQuote}}]}));return{quoteId:r.requestId,customerDeliveryFee:{minorAmount:1500000}};}})};
 const response=await prepare321({event,env,base,runtime,body:{action:'preview_commercial_point',userId:'owner',storeId:'b',items:[{id:'p',quantity:1}],pricingPoint:{latitude:31,longitude:44}},run:async(e,db)=>{const r=JSON.parse(e.body);assert.equal(r.action,'preview_commercial');assert.equal(r.deliveryFee,1500);assert.equal(r.pricingPoint,undefined);assert((await db.send(new GetCommand({TableName:'staging-DeliveryQuotes',Key:savedQuote}))).Item);await assert.rejects(db.send(new PutCommand({TableName:'WizzOrders'})));return{statusCode:200,body:JSON.stringify({commercial:{schemaVersion:1,quoteId:r.quoteId,requestId:r.idempotencyKey,digest:'private-consent',expiresAt:'2026-10-27T00:02:00.000Z',serviceFee:{minorAmount:500000}}})};}});
 const invoice=JSON.parse(response.body).pointInvoice;assert.equal(invoice.quoteId,undefined);assert.equal(invoice.requestId,undefined);assert.equal(invoice.digest,undefined);assert.equal(invoice.requiresFinalConfirmation,true);assert.equal(invoice.serviceFee.minorAmount,500000);assert(calls.every(c=>c.constructor.name==='GetCommand'));
});

test('actual bundled quote creation and delivery ConditionCheck shape is supported without persisting virtual records',async()=>{
 const transactions=[],base={async send(c){transactions.push(c.input.TransactItems);assert(c.input.TransactItems.every(o=>o.ConditionCheck));return{};}},point={addressId:'point',userId:'owner',latitude:31,longitude:44},v=pointView321(base,{address:point,userId:'owner'});
 const row={pk:'CUSTOMER#owner',sk:'QUOTE#q',digest:'expected'};
 const liveCheck={ConditionCheck:{TableName:'users',Key:{userId:'owner'},ConditionExpression:'attribute_exists(userId)'}};
 const pointCheck={ConditionCheck:{TableName:'WizzUser_addresses_staging',Key:{addressId:'point'},ConditionExpression:'latitude=:lat',ExpressionAttributeValues:{':lat':31}}};
 await v.db.send(new TransactWriteCommand({TransactItems:[liveCheck,pointCheck,{Put:{TableName:'staging-DeliveryQuotes',Item:row}}]}));
 const quoteCheck={ConditionCheck:{TableName:'staging-DeliveryQuotes',Key:{pk:row.pk,sk:row.sk},ConditionExpression:'#digest=:digest AND attribute_not_exists(consumption)',ExpressionAttributeValues:{':digest':'expected'}}};
 await v.db.send(new TransactWriteCommand({TransactItems:[liveCheck,pointCheck,quoteCheck]}));v.seal();
 await v.db.send(new TransactWriteCommand({TransactItems:[liveCheck,quoteCheck]}));assert.equal(transactions.length,3);assert(transactions.every(t=>t.length===1&&t[0].ConditionCheck.TableName==='users'));
 await assert.rejects(v.db.send(new TransactWriteCommand({TransactItems:[{ConditionCheck:{...quoteCheck.ConditionCheck,ExpressionAttributeValues:{':digest':'wrong'}}}]})),e=>e.code==='POINT_PREVIEW_QUOTE_CHANGED');
 await assert.rejects(v.db.send(new TransactWriteCommand({TransactItems:[{Put:{TableName:'staging-DeliveryQuotes',Item:{...row,sk:'QUOTE#new'}}}]})),e=>e.code==='POINT_PREVIEW_WRITE_FORBIDDEN');
});
test('real quote engine completes create and deliver inside point view with only live ConditionChecks sent out',async()=>{
 const root=__dirname+'/../../../whizzCentralPlatform-stg/backend/wallet-service';
 const {fixture}=require(root+'/test/helpers/delivery-quote-fixture.cjs');
 const {createStagingDeliveryQuotes}=require(root+'/dist/deliveryQuote');
 const {createStagingDeliveryRouting}=require(root+'/dist/regionCoverage');
 const {createStagingQuoteOrder}=require(root+'/dist/deliveryQuoteOrder');
 const f=fixture(),point={addressId:'point-address',userId:'u1',latitude:31.93,longitude:44.46};
 const v=pointView321(f.db,{address:point,userId:'u1'});
 const createRouter=db=>createStagingDeliveryRouting({db,getAccessToken:async()=>'test',profile:'driving',ttlSeconds:120,timeoutMs:1000,now:()=>f.time,fetchImpl:async()=>new Response(JSON.stringify({code:'Ok',routes:[{distance:2100,duration:300}]}))});
 const svc=createStagingDeliveryQuotes({db:v.db,authenticateCustomer:f.auth,createRouter,now:()=>f.time});
 const q=await svc.create({branchId:'b1',addressId:point.addressId,requestId:'12345678-1234-4123-8123-123456789abc'});
 assert.equal(q.customerDeliveryFee.minorAmount,3100000);assert.equal(f.saved.size,0);assert.equal(f.orders.size,0);assert.equal(f.address.addressId,'a1');
 v.seal();
 const content={storeId:'b1',userId:'u1',deliveryAddress:{id:point.addressId,latitude:point.latitude,longitude:point.longitude}};
 const order=await createStagingQuoteOrder({db:v.db,authenticateCustomer:f.auth,now:()=>f.time}).prepare({quoteId:q.quoteId,branchId:'b1',addressId:point.addressId,requestId:'22345678-1234-4123-8123-123456789abc',requestContent:content});
 assert.equal(order.deliveryFeeMinor,3100000);assert.equal(f.saved.size,0);assert.equal(f.orders.size,0);assert(f.transactions.length>=2);assert(f.transactions.every(t=>t.TransactItems.every(o=>Object.keys(o).join(',')==='ConditionCheck')));
});

test('full real point invoice prices an active customer basket without written address or any business mutation',async()=>{
 const root=__dirname+'/../../../whizzCentralPlatform-stg/backend/wallet-service';
 const {setup}=require(root+'/test/helpers/quote-order-handler-fixture.cjs');
 const sdk=require(root+'/node_modules/@aws-sdk/lib-dynamodb');
 const {createStagingDeliveryQuotes}=require(root+'/dist/deliveryQuote');
 const {createStagingDeliveryRouting}=require(root+'/dist/regionCoverage');
 const f=await setup();f.enableCommercial();f.env.FINANCIAL_SETTLEMENT_MODEL='FULL_CASH_AT_DELIVERY_V1';f.env.FINANCE_GENERAL_RELEASE_MODE='REQUIRED';f.orders.set('ORDER#active|META',{orderId:'active',userId:'u1',userSub:'sub1',status:'confirmed',createdAt:new Date(f.time-10000).toISOString()});
 const savedBefore=f.saved.size,recordsBefore=f.commercialRecords.size,txBefore=f.transactions.length;
 const runtime={...sdk,GetUserCommand:class{},CognitoIdentityProviderClient:class{async send(){return{Username:'username',UserAttributes:[{Name:'sub',Value:'sub1'}]};}},SecretsManagerClient:class{},createStagingDeliveryQuotes:o=>createStagingDeliveryQuotes({...o,now:()=>f.time}),createStagingSecretDeliveryRouting:({db})=>createStagingDeliveryRouting({db,getAccessToken:async()=>'test',profile:'driving',ttlSeconds:120,timeoutMs:1000,now:()=>f.time,fetchImpl:async()=>new Response(JSON.stringify({code:'Ok',routes:[{distance:2100,duration:300}]}))})};
 const {deliveryAddress,quoteId,idempotencyKey,...body}=f.body;
 const response=await prepare321({event:{httpMethod:'POST',resource:'/orders/commercial-preview',headers:{Authorization:'Bearer '+f.token}},body:{...body,action:'preview_commercial_point',pricingPoint:{latitude:31.93,longitude:44.46}},base:f.adapterDb,run:f.runReadOnlyTest,runtime,env:{...f.env,POINT_INVOICE_ENABLED:'true',ENVIRONMENT:'staging'}});
 assert.equal(response.statusCode,200,response.body);const p=JSON.parse(response.body).pointInvoice;assert.equal(p.customerTotal.minorAmount,7000000);assert.equal(p.serviceFee.minorAmount,500000);assert.equal(p.quoteId,undefined);assert.equal(f.saved.size,savedBefore);assert.equal(f.orders.size,1);assert.equal(f.commercialRecords.size,recordsBefore);assert(f.transactions.slice(txBefore).every(t=>t.TransactItems.every(o=>o.ConditionCheck)));
});

test('bundled SDK commands are normalized to the host SDK before profile reads and read-only transactions',async()=>{
 const {pointRuntimeDb348}=require('../src/functions/create-order/point-invoice-321');
 const HostGet=class GetCommand{constructor(input){this.input=input;}},HostTx=class TransactWriteCommand{constructor(input){this.input=input;}};
 const ForeignGet=class GetCommand{constructor(input){this.input=input;this.middlewareStack={foreign:true};}},ForeignTx=class TransactWriteCommand{constructor(input){this.input=input;}};
 const calls=[],base={send:async c=>{assert(c instanceof HostGet||c instanceof HostTx);calls.push(c);return{Item:{verified:true}};}};
 const db=pointRuntimeDb348(base,{GetCommand:HostGet,TransactWriteCommand:HostTx});
 assert.equal((await db.send(new ForeignGet({TableName:'profiles',Key:{userId:'owner'},ConsistentRead:true}))).Item.verified,true);
 await db.send(new ForeignTx({TransactItems:[{ConditionCheck:{TableName:'profiles',Key:{userId:'owner'}}}]}));
 assert.equal(calls.length,2);assert.equal(calls[0].input.ConsistentRead,true);
 await assert.rejects(db.send(new ForeignTx({TransactItems:[{Put:{TableName:'WizzOrders'}}]})),/WRITE_FORBIDDEN/);
 await assert.rejects(db.send(new PutCommand({TableName:'WizzOrders'})),/WRITE_FORBIDDEN/);
 assert.equal(calls.length,2);
});
