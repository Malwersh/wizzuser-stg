'use strict';
const {GetCommand}=require('@aws-sdk/lib-dynamodb');
const {checkoutTables}=require('../create-order/quote-runtime/checkoutTables');
async function attribution(db,slideId,snapshot){if(!snapshot||typeof slideId!=='string'||!/^[-\w]{1,150}$/.test(slideId))return [];
 const tables=checkoutTables(process.env);
 const state=(await db.send(new GetCommand({TableName:tables.policy,Key:{pk:'HOME_SLIDESHOW',sk:'CURRENT'},ConsistentRead:true}))).Item;
 const row=state?.slides?.find(x=>x.id===slideId);
 const s=tables.policy.startsWith('wizz-production-')?(row?.paused?null:row?.published):row;
 const a=s?.action,now=Date.now();
 if(!(Date.parse(s?.startAt)<=now&&Date.parse(s?.endAt)>now))return [];
 if(!a||a.id!==snapshot.discountId||!['campaign','platform','discount'].includes(a.type)||((a.type==='discount')!==(snapshot.source==='MERCHANT')))return [];
 return [{Update:{TableName:tables.journey,Key:{pk:'STATS#'+slideId,sk:'TOTAL'},UpdateExpression:'ADD #orders :one, #saved :amount',ExpressionAttributeNames:{'#orders':'orders','#saved':'savingsFils'},ExpressionAttributeValues:{':one':1,':amount':snapshot.amount}}}];
}
module.exports={attribution};
