'use strict';
const {GetCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
async function driverStateUpdate(db,connectionId,claimedDriverId,update){
 const table='WizzUser_websocket_connections_staging';
 const {Item:c}=await db.send(new GetCommand({TableName:table,Key:{connectionId},ConsistentRead:true}));
 const sub=c?.cognitoSub;
 if(!sub||c.authenticated!==true||c.entityType!=='driver'||c.driverId!==sub||c.userId!==sub||c.status!=='active'||claimedDriverId!==sub||update.TableName!=='WizzDriverLiveState_staging'||update.Key.driverId!==sub)throw Error('DRIVER_CONNECTION_REQUIRED');
 const {Item:p}=await db.send(new GetCommand({TableName:'WhizzDrivers_staging',Key:{driverId:sub},ConsistentRead:true}));
 const status=String(p?.status||'').toUpperCase(),review=String(p?.registrationStatus||'').toUpperCase();
 const blocked=['BANNED','SUSPENDED','REJECTED','PENDING_REVIEW','PENDING_PROFILE','PENDING_DOCS'];
 if(!p||p.deletionRequestId||blocked.includes(status)||blocked.includes(review)||!(['APPROVED','VERIFIED'].includes(status)||['APPROVED','VERIFIED'].includes(review)||p.isVerified===true||p.is_verified===true||p.documentsVerified===true))throw Error('DRIVER_NOT_VERIFIED');
 const names={},values={':sub':sub},parts=['attribute_exists(driverId)','attribute_not_exists(deletionRequestId)'];
 for(const field of ['status','registrationStatus','isVerified','is_verified','documentsVerified']){names['#'+field]=field;if(p[field]!==undefined){values[':'+field]=p[field];parts.push('#'+field+' = :'+field);}else parts.push('attribute_not_exists(#'+field+')');}
 // :sub is used by the profile key itself, not an expression. Remove it here.
 delete values[':sub'];
 await db.send(new TransactWriteCommand({TransactItems:[
  {ConditionCheck:{TableName:'staging-AccountDeletion',Key:{pk:'ACCOUNT_LIFECYCLE#DRIVER#'+sub,sk:'META'},ConditionExpression:'attribute_not_exists(pk)'}},
  {ConditionCheck:{TableName:table,Key:{connectionId},ConditionExpression:'authenticated = :yes AND cognitoSub = :sub AND driverId = :sub AND userId = :sub AND entityType = :driver AND #s = :active',ExpressionAttributeNames:{'#s':'status'},ExpressionAttributeValues:{':yes':true,':sub':sub,':driver':'driver',':active':'active'}}},
  {ConditionCheck:{TableName:'WhizzDrivers_staging',Key:{driverId:sub},ConditionExpression:parts.join(' AND '),ExpressionAttributeNames:names,ExpressionAttributeValues:values}},
  {Update:update},
 ]}));
 return sub;
}
module.exports={driverStateUpdate};
