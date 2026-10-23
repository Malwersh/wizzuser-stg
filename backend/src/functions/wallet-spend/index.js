'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand,QueryCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
const {writeContext}=require('../create-order/guarded-write');
const {createHash}=require('node:crypto');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({}));
const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization'};
const reply=(statusCode,data)=>({statusCode,headers,body:JSON.stringify(data)});
const fail=(code,statusCode=409)=>Object.assign(Error(code),{statusCode});
exports.handler=async event=>{
 if(event.httpMethod==='OPTIONS')return reply(200,{});
 try{
  const body=typeof event.body==='string'?JSON.parse(event.body):event.body;
  const {userId,amount,orderId}=body||{};
  if(typeof userId!=='string'||!userId||!Number.isSafeInteger(amount)||amount<=0||typeof orderId!=='string'||!orderId||orderId.length>100)throw fail('INVALID_PAYMENT',400);
  const write=await writeContext(db,event,userId);
  const transactionId='SPEND#'+createHash('sha256').update(JSON.stringify([userId,orderId])).digest('hex');
  const txTable=process.env.TRANSACTIONS_TABLE,walletTable=process.env.WALLETS_TABLE;
  const read=async()=> (await db.send(new GetCommand({TableName:txTable,Key:{transactionId},ConsistentRead:true}))).Item;
  const match=t=>{if(t.userId!==userId||t.orderId!==orderId||t.amount!==amount||t.type!=='SPEND'||t.status!=='SUCCESS')throw fail('PAYMENT_CONFLICT');return reply(200,{success:true,transactionId,newBalance:t.balanceAfter,alreadyProcessed:true});};
  const saved=await read();if(saved)return match(saved);
  const {Item:order}=await db.send(new GetCommand({TableName:process.env.WIZZORDERS_TABLE,Key:{PK:'ORDER#'+orderId,SK:'META'},ConsistentRead:true}));
  if(!order||![order.userId,order.customerId].includes(userId))throw fail('ORDER_MISMATCH',403);
  const wallets=await db.send(new QueryCommand({TableName:walletTable,IndexName:'userId-index',KeyConditionExpression:'userId = :id',ExpressionAttributeValues:{':id':userId},Limit:2}));
  if(wallets.LastEvaluatedKey||wallets.Items?.length!==1)throw fail('WALLET_UNAVAILABLE');
  const w=wallets.Items[0];
  if(w.userId!==userId||w.status!=='ACTIVE'||w.deletionRequestId||w.currency!=='IQD'||!Number.isSafeInteger(w.balance)||w.balance<amount)throw fail('WALLET_UNAVAILABLE_OR_INSUFFICIENT');
  const now=new Date().toISOString();
  const entry={transactionId,walletId:w.walletId,userId,orderId,type:'SPEND',amount,currency:'IQD',status:'SUCCESS',balanceBefore:w.balance,balanceAfter:w.balance-amount,timestamp:now,createdAt:now};
  try{await db.send(new TransactWriteCommand({TransactItems:[write.fence,
   {Update:{TableName:walletTable,Key:{walletId:w.walletId},UpdateExpression:'SET balance = balance - :amount, updatedAt = :at ADD #v :one',ConditionExpression:'attribute_exists(walletId) AND userId = :owner AND #s = :active AND currency = :iqd AND balance = :before AND balance >= :amount AND attribute_not_exists(deletionRequestId)',ExpressionAttributeNames:{'#s':'status','#v':'version'},ExpressionAttributeValues:{':owner':userId,':active':'ACTIVE',':iqd':'IQD',':before':w.balance,':amount':amount,':at':now,':one':1}}},
   {Put:{TableName:txTable,Item:entry,ConditionExpression:'attribute_not_exists(transactionId)'}}]}));}
  catch(e){if(e.name==='TransactionCanceledException'){const completed=await read();if(completed)return match(completed);throw fail('PAYMENT_STATE_CHANGED');}throw e;}
  return reply(200,{success:true,transactionId,newBalance:entry.balanceAfter});
 }catch(e){return reply(e.statusCode||(e instanceof SyntaxError?400:503),{success:false,code:e.message,message:'تعذر تنفيذ الدفع؛ حدّث حالة المحفظة قبل إعادة المحاولة'});}
};
