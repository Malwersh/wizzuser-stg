'use strict';
const {CognitoIdentityProviderClient,GetUserCommand}=require('@aws-sdk/client-cognito-identity-provider');
const {GetCommand,ScanCommand,QueryCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
const {accountGuard}=require('../create-order/account-guard');
const cognito=new CognitoIdentityProviderClient({maxAttempts:2});
const fail=(code,statusCode=409)=>Object.assign(Error(code),{code,statusCode});
const saved=a=>a&&a.recordType!=='CHECKOUT_ADDRESS';
const isDefault=a=>a.isDefault===true||a.isDefault==='true';
async function writeContext(db,event,userId){
 let profile;
 const guard=await accountGuard({event,userId,pool:process.env.USER_POOL_ID,clientId:process.env.USER_POOL_CLIENT_ID,profilesTable:process.env.USERS_TABLE,
  getUser:token=>cognito.send(new GetUserCommand({AccessToken:token})),getProfile:async id=>{profile=(await db.send(new GetCommand({TableName:process.env.USERS_TABLE,Key:{userId:id},ConsistentRead:true}))).Item;return profile;}});
 if(!guard.condition)throw fail('AUTH_REQUIRED',401);
 return {fence:guard.condition,profile,userId};
}
async function readSavedBook(db,write,{mutation=true}={}){
 const table=process.env.ADDRESSES_TABLE,meta=write.profile.addressBook319;
 let rows=[];
 if(meta!==undefined){
  if(meta.schemaVersion!==1||!Number.isSafeInteger(meta.revision)||meta.revision<1||!Array.isArray(meta.ids)||meta.ids.length>10||new Set(meta.ids).size!==meta.ids.length||meta.ids.some(x=>typeof x!=='string'||!x)||!(meta.defaultId===null||meta.ids.includes(meta.defaultId))||(meta.ids.length>0&&meta.defaultId===null))throw fail('ADDRESS_BOOK_STATE_INVALID',503);
  rows=await Promise.all(meta.ids.map(async addressId=>(await db.send(new GetCommand({TableName:table,Key:{addressId},ConsistentRead:true}))).Item));
  if(rows.some(a=>!saved(a)||a.userId!==write.userId))throw fail('ADDRESS_BOOK_STATE_CHANGED');
 }else{
  // Strong scan is used only for the first legacy mutation. Reads use the user index then refresh each owned row.
  let cursor;
  for(let pages=0;pages<100;pages++){
   const page=mutation?await db.send(new ScanCommand({TableName:table,ConsistentRead:true,FilterExpression:'userId=:owner AND (attribute_not_exists(recordType) OR recordType<>:checkout)',ExpressionAttributeValues:{':owner':write.userId,':checkout':'CHECKOUT_ADDRESS'},...(cursor?{ExclusiveStartKey:cursor}:{})})):await db.send(new QueryCommand({TableName:table,IndexName:'userId-index',KeyConditionExpression:'userId=:owner',FilterExpression:'attribute_not_exists(recordType) OR recordType<>:checkout',ExpressionAttributeValues:{':owner':write.userId,':checkout':'CHECKOUT_ADDRESS'},...(cursor?{ExclusiveStartKey:cursor}:{})}));rows.push(...(page.Items||[]).filter(a=>saved(a)&&a.userId===write.userId));cursor=page.LastEvaluatedKey;if(!cursor)break;
  }
  if(cursor)throw fail('ADDRESS_BOOK_DISCOVERY_UNAVAILABLE',503);
  rows.sort((a,b)=>String(a.createdAt||'').localeCompare(String(b.createdAt||''))||a.addressId.localeCompare(b.addressId));
  if(rows.length>10)throw fail('ADDRESS_BOOK_REVIEW_REQUIRED',409);
 }
 if(meta===undefined&&!mutation){rows=(await Promise.all(rows.map(async a=>(await db.send(new GetCommand({TableName:table,Key:{addressId:a.addressId},ConsistentRead:true}))).Item))).filter(a=>saved(a)&&a.userId===write.userId);}
 const defaultId=meta?.defaultId??rows.find(isDefault)?.addressId??rows[0]?.addressId??null;
 return {rows,meta,ids:rows.map(a=>a.addressId),defaultId};
}
async function commitBook({db,write,operation,makeDefault=false,regionChecks=[],expectedAddress=null}){
 const table=process.env.ADDRESSES_TABLE,userId=write.userId;
 const hidden=operation.Put?.Item.recordType==='CHECKOUT_ADDRESS';
 if(hidden){await db.send(new TransactWriteCommand({TransactItems:[write.fence,...regionChecks,operation]}));return {defaultId:null};}
 const book=await readSavedBook(db,write),ids=[...book.ids];
 const addressId=operation.Put?.Item.addressId||operation.Update?.Key.addressId||operation.Delete?.Key.addressId;
 const old=book.rows.find(a=>a.addressId===addressId);
 if(!operation.Put&&!old)throw fail('ADDRESS_NOT_SAVED',404);
 if(expectedAddress&&old&&(old.updatedAt!==expectedAddress.updatedAt||old.latitude!==expectedAddress.latitude||old.longitude!==expectedAddress.longitude))throw fail('ADDRESS_BOOK_CHANGED');
 if(operation.Put){if(ids.length>=10)throw fail('ADDRESS_LIMIT_REACHED',400);if(ids.includes(addressId))throw fail('ADDRESS_ALREADY_EXISTS');ids.push(addressId);}
 if(operation.Delete)ids.splice(ids.indexOf(addressId),1);
 const defaultId=makeDefault&&!operation.Delete?addressId:ids.includes(book.defaultId)?book.defaultId:ids[0]??null;
 const meta={schemaVersion:1,revision:(book.meta?.revision??0)+1,ids,defaultId};
 const fence=write.fence.ConditionCheck,names={...(fence.ExpressionAttributeNames||{}),'#book':'addressBook319'},values={...(fence.ExpressionAttributeValues||{}),':bookNext':meta};
 if(book.meta!==undefined)values[':bookOld']=book.meta;
 const profile={Update:{TableName:fence.TableName,Key:fence.Key,UpdateExpression:'SET #book=:bookNext',ConditionExpression:`(${fence.ConditionExpression}) AND `+(book.meta===undefined?'attribute_not_exists(#book)':'#book=:bookOld'),ExpressionAttributeNames:names,ExpressionAttributeValues:values}};
 const now=new Date().toISOString(),flag=defaultId===addressId?'true':'false';
 if(operation.Put)operation.Put.Item.isDefault=flag;
 if(operation.Update){const u=operation.Update;u.ExpressionAttributeNames={...u.ExpressionAttributeNames,'#bookDefault':'isDefault'};u.ExpressionAttributeValues={...u.ExpressionAttributeValues,':bookDefault':flag};u.UpdateExpression+=', #bookDefault=:bookDefault';delete u.ReturnValues;}
 // Target is always guarded against a concurrent edit as well as ownership.
 const target=operation.Update||operation.Delete;
 if(target){target.ExpressionAttributeNames={...target.ExpressionAttributeNames,'#bookUpdated':'updatedAt'};target.ExpressionAttributeValues={...target.ExpressionAttributeValues,':bookOwner':userId,...(old.updatedAt!==undefined?{':bookUpdated':old.updatedAt}:{})};target.ConditionExpression=`(${target.ConditionExpression||'attribute_exists(addressId)'}) AND userId=:bookOwner AND `+(old.updatedAt===undefined?'attribute_not_exists(#bookUpdated)':'#bookUpdated=:bookUpdated');}
 const changes=book.rows.filter(a=>a.addressId!==addressId&&isDefault(a)!==(a.addressId===defaultId)).map(a=>({Update:{TableName:table,Key:{addressId:a.addressId},UpdateExpression:'SET isDefault=:d, updatedAt=:now',ConditionExpression:'attribute_exists(addressId) AND userId=:owner AND '+(a.updatedAt===undefined?'attribute_not_exists(#updated)':'#updated=:updated'),ExpressionAttributeNames:{'#updated':'updatedAt'},ExpressionAttributeValues:{':d':a.addressId===defaultId?'true':'false',':now':now,':owner':userId,...(a.updatedAt!==undefined?{':updated':a.updatedAt}:{})}}}));
 try{await db.send(new TransactWriteCommand({TransactItems:[profile,...regionChecks,operation,...changes]}));}catch(e){if(e.name==='TransactionCanceledException')throw fail('ADDRESS_BOOK_CHANGED');throw e;}
 return {defaultId,meta};
}
function fullAddress319(a,previous={}){
 const text=String(a.detailed_address??a.detailedAddress??a.fullAddress??'').trim();
 const known=new Set([a.province,a.district,a.regionNameAr,a.region_name_ar,a.neighborhood,a.landmark,previous.province,previous.district,previous.regionNameAr,previous.neighborhood,previous.landmark,'العراق'].filter(Boolean).flatMap(v=>[String(v).trim(),'قرب '+String(v).trim()]));
 const extras=text.split(/[،,\n]/).map(v=>v.trim()).filter(v=>v&&!known.has(v)&&!/^[-+]?\d+\.\d+$/.test(v));
 return [...new Set([a.province,a.district,a.regionNameAr||a.region_name_ar,a.neighborhood,...extras,a.landmark?'قرب '+a.landmark:null].filter(Boolean))].join('، ');
}
function formatAddress(a,defaultId){return {id:a.addressId,user_id:a.userId,name:a.name||'عنوان التوصيل',province:a.province||'',district:a.district||'',neighborhood:a.neighborhood||'',landmark:a.landmark||'',full_address:a.fullAddress||a.detailedAddress||'',detailed_address:a.detailedAddress||null,latitude:a.latitude??null,longitude:a.longitude??null,region_id:a.regionId||null,region_name_ar:a.regionNameAr||null,address_type:a.addressType||'other',is_default:a.addressId===defaultId,building_number:a.buildingNumber||null,floor_number:a.floorNumber||null,apartment_number:a.apartmentNumber||null,phone_number:a.phoneNumber||null,created_at:a.createdAt,updated_at:a.updatedAt};}
module.exports={writeContext,readSavedBook,commitBook,saved,isDefault,formatAddress,fullAddress319};
