'use strict';
const {GetCommand,QueryCommand}=require('@aws-sdk/lib-dynamodb');
const {PostToConnectionCommand}=require('@aws-sdk/client-apigatewaymanagementapi');
const {PrivateOrderApiClient}=require('./private-order-delivery-346');
const {tripPoints,createDriverTripRouter}=require('./driver-trip-route-438');
const phases=new Set(['picked_up','heading_to_customer','arrived_at_customer','on_the_way','out_for_delivery']);
function sample(order,live,now=Date.now()){
 if(!order||!live||!phases.has(order.status)||order.isDeleted||order.deletedAt||order.deletionRequestId||!order.driverId||live.driverId!==order.driverId||live.currentOrderId!==order.orderId)return null;
 const p=live.tripLocation438,t=Date.parse(p?.observedAt),picked=Date.parse(order.pickedUpAt||order.pickedUpAtStoreAt||'');
 if(!p||p.orderId!==order.orderId||!Number.isFinite(t)||now-t>60000||t>now+5000||Number.isFinite(picked)&&t<picked||![p.lat,p.lng,p.accuracy,p.heading].every(Number.isFinite)||Math.abs(p.lat)>90||Math.abs(p.lng)>180||p.accuracy<0||p.accuracy>100||p.heading<0||p.heading>=360)return null;
 return {latitude:p.lat,longitude:p.lng,accuracy:p.accuracy,heading:p.heading,observedAt:p.observedAt};
}
let router;
async function broadcast(db,event){
 if(event.source!=='wizz.driver-location-438'||event.schemaVersion!==1||event.httpMethod||event.requestContext||typeof event.orderId!=='string'||typeof event.driverId!=='string')throw Error('INTERNAL_TRACKING_EVENT_REQUIRED');
 const read=async()=> (await db.send(new GetCommand({TableName:'WizzOrders',Key:{PK:'ORDER#'+event.orderId,SK:'META'},ConsistentRead:true}))).Item;
 const order=await read();if(order?.driverId!==event.driverId)return {skipped:true};
 const live=(await db.send(new GetCommand({TableName:'WizzDriverLiveState_staging',Key:{driverId:event.driverId},ConsistentRead:true}))).Item;
 const point=sample(order,live);if(!point)return {skipped:true};
 let route=null;
 try{
  if(!router)router=createDriverTripRouter({getToken:async()=>{const {SecretsManagerClient,GetSecretValueCommand}=require('@aws-sdk/client-secrets-manager');const v=(await new SecretsManagerClient({}).send(new GetSecretValueCommand({SecretId:process.env.DRIVER_ROUTE_MAPBOX_SECRET_ARN}))).SecretString;try{const j=JSON.parse(v);return j.accessToken||j.access_token||j.token||j.MAPBOX_ACCESS_TOKEN;}catch{return v;}}});
  route=await router(order);
 }catch{/* Location remains useful if road geometry is unavailable. */}
 const current=await read();if(current?.driverId!==event.driverId||!phases.has(current.status))return {skipped:true};
 const ids=new Set();
 for(const userId of new Set([order.userSub,order.customerSubjectId,order.userId,order.customerId].filter(Boolean))){
  let cursor;do{const r=await db.send(new QueryCommand({TableName:'WizzUser_websocket_connections_staging',IndexName:'userId-connectedAt-index',KeyConditionExpression:'userId=:u',ExpressionAttributeValues:{':u':userId},ProjectionExpression:'connectionId',ExclusiveStartKey:cursor}));for(const row of r.Items||[])ids.add(row.connectionId);cursor=r.LastEvaluatedKey;}while(cursor);
 }
 const api=new PrivateOrderApiClient({endpoint:'https://igcrhwc84c.execute-api.us-east-1.amazonaws.com/staging'});
 let sent=0;for(const connectionId of ids){try{await api.send(new PostToConnectionCommand({ConnectionId:connectionId,Data:Buffer.from(JSON.stringify({type:'driver_location',orderId:order.orderId,driverId:order.driverId,location:point,...(route?{route}:{}),...(()=>{try{return tripPoints(order);}catch{return {};}})()}))}));sent++;}catch(e){if(!e.status&&e.$metadata?.httpStatusCode!==410)throw e;}}
 return {sent};
}
module.exports={sample,broadcast};
