'use strict';
const {GetCommand,QueryCommand}=require('@aws-sdk/lib-dynamodb');
const projection='userId,cognitoSub,cognitoUsername,phone,isActive,deletionRequestId,phoneChangePending,email';
function owned(p,u){return !!p && (!p.cognitoSub || p.cognitoSub===u.sub) && (p.userId===u.sub || p.cognitoSub===u.sub || p.cognitoUsername===u.username || (u.attrs.email_verified==='true' && p.email===u.attrs.email && p.cognitoUsername===u.attrs.email));}
async function profileFor(db,table,u){
 const direct=(await db.send(new GetCommand({TableName:table,Key:{userId:u.sub},ConsistentRead:true,ProjectionExpression:projection}))).Item;
 if(direct){if(!owned(direct,u))throw Error('ProfileMismatch');return direct;}
 const rows=new Map();
 const queries=[];
 if(u.attrs.phone_number_verified==='true' && /^\+9647\d{9}$/.test(u.attrs.phone_number||'')){
  const phone=u.attrs.phone_number;
  for(const value of [phone,'0'+phone.slice(4),phone.slice(4)])queries.push({IndexName:'phone-index',KeyConditionExpression:'phone = :value',ExpressionAttributeValues:{':value':value}});
 }
 if(u.attrs.email_verified==='true'&&u.attrs.email)queries.push({IndexName:'email-index',KeyConditionExpression:'email = :value',ExpressionAttributeValues:{':value':u.attrs.email}});
 for(const q of queries){
  const r=await db.send(new QueryCommand({TableName:table,...q,ProjectionExpression:projection,Limit:2}));
  if(r.LastEvaluatedKey)throw Error('ProfileMismatch');
  for(const row of r.Items||[])rows.set(row.userId,row);
 }
 // A pending change may already have moved Cognito's phone while a legacy
 // profile still has the old phone. Resolve only a server-recorded owner-bound operation.
 if(rows.size===0){
  const {Item:active}=await db.send(new GetCommand({TableName:process.env.OTP_TABLE,Key:{id:`ACTIVE#${u.sub}`},ConsistentRead:true}));
  if(active?.sessionId){
   const {Item:op}=await db.send(new GetCommand({TableName:process.env.OTP_TABLE,Key:{id:active.sessionId},ConsistentRead:true}));
   if(op?.sub===u.sub&&op.purpose==='phone-change-451'&&['APPLYING','COMPLETED'].includes(op.state)&&op.profileId){
    const {Item:p}=await db.send(new GetCommand({TableName:table,Key:{userId:op.profileId},ConsistentRead:true,ProjectionExpression:projection}));
    if(p&&owned(p,u)&&(p.phoneChangePending===op.id||(op.state==='COMPLETED'&&!p.phoneChangePending&&p.phone===op.phone)))rows.set(p.userId,p);
   }
  }
 }
 if(rows.size!==1||!owned([...rows.values()][0],u))throw Error('ProfileMismatch');
 return [...rows.values()][0];
}
function profileCondition(p,u){
 return {ConditionExpression:'attribute_exists(userId) AND (attribute_not_exists(isActive) OR isActive = :enabled) AND attribute_not_exists(deletionRequestId) AND (attribute_not_exists(cognitoSub) OR cognitoSub = :subject) AND '+(p.userId===u.sub?'userId = :owner':p.cognitoSub===u.sub?'cognitoSub = :owner':'cognitoUsername = :username'),ExpressionAttributeValues:{':enabled':true,':subject':u.sub,...(p.userId===u.sub||p.cognitoSub===u.sub?{':owner':u.sub}:{':username':p.cognitoUsername})}};
}
module.exports={profileFor,profileCondition,owned};
