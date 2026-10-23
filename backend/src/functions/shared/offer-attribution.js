'use strict';
const {GetCommand}=require('@aws-sdk/lib-dynamodb');
const {TABLE}=require('./offer-eligibility');
async function attribution(db,slideId,snapshot){if(!snapshot||typeof slideId!=='string'||!/^[-\w]{1,150}$/.test(slideId))return [];
 const state=(await db.send(new GetCommand({TableName:'staging-PlatformStaff',Key:{pk:'HOME_SLIDESHOW',sk:'CURRENT'},ConsistentRead:true}))).Item;
 const s=state?.slides?.find(x=>x.id===slideId),a=s?.action;
 if(!a||a.id!==snapshot.discountId||!['campaign','platform','discount'].includes(a.type)||((a.type==='discount')!==(snapshot.source==='MERCHANT')))return [];
 return [{Update:{TableName:TABLE,Key:{pk:'STATS#'+slideId,sk:'TOTAL'},UpdateExpression:'ADD #orders :one, #saved :amount',ExpressionAttributeNames:{'#orders':'orders','#saved':'savingsFils'},ExpressionAttributeValues:{':one':1,':amount':snapshot.amount}}}];
}
module.exports={attribution};
