'use strict';
// Display-only road geometry. Never used to price or settle an order.
const first=(...values)=>values.find(v=>typeof v==='string'&&v.trim())?.trim()||'';
function coordinate(...values){for(const v of values){if(v!==null&&v!==undefined&&v!==''&&Number.isFinite(Number(v)))return Number(v);}return NaN;}
function tripPoints(o){
 const store=o.storeAddress||{},customer=o.deliveryAddress||o.customerAddress||{};
 const origin=[coordinate(o.restaurantLng,o.pickupLongitude,store.longitude,store.lng),coordinate(o.restaurantLat,o.pickupLatitude,store.latitude,store.lat)];
 const destination=[coordinate(o.customerLng,o.deliveryLongitude,customer.lng,customer.longitude),coordinate(o.customerLat,o.deliveryLatitude,customer.lat,customer.latitude)];
 const valid=p=>Number.isFinite(p[0])&&Number.isFinite(p[1])&&Math.abs(p[0])<=180&&Math.abs(p[1])<=90&&!(p[0]===0&&p[1]===0);
 if(!valid(origin)||!valid(destination))throw Error('TRIP_COORDINATES_UNAVAILABLE');
 return {origin,destination};
}
function pickupView(o){const a=o.storeAddress;return {restaurantId:first(o.storeId,o.restaurantId,o.businessId),restaurantName:first(o.storeName,o.restaurantName,o.businessName),restaurantAddress:first(o.restaurantAddress,o.pickupAddress,typeof a==='string'?a:'',a?.fullAddress,a?.detailedAddress,a?.addressLine1),restaurantPhone:first(o.restaurantPhone,o.businessPhone,o.storePhone)};}
function createDriverTripRouter({getToken,request=fetch,now=Date.now}){
 const cache=new Map();
 return async(o)=>{
  const points=tripPoints(o),key=JSON.stringify(points),saved=cache.get(key);
  if(saved&&saved.expires>now())return saved.route;
  const controller=new AbortController();let timer;
  try{
   return await Promise.race([new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(Error('TRIP_ROUTE_UNAVAILABLE'));},10000);}), (async()=>{
    const token=await getToken();if(typeof token!=='string'||!token.trim()||/\s/.test(token))throw Error('TRIP_ROUTE_UNAVAILABLE');
    const url=new URL('https://api.mapbox.com/directions/v5/mapbox/driving/'+[points.origin,points.destination].map(p=>p.join(',')).join(';'));
    url.search=new URLSearchParams({access_token:token,alternatives:'false',overview:'full',geometries:'geojson',steps:'false'}).toString();
    const response=await request(url,{signal:controller.signal,redirect:'error'});if(!response.ok)throw Error('TRIP_ROUTE_UNAVAILABLE');
    const reader=response.body.getReader(),parts=[];let length=0;
    try{while(true){const part=await reader.read();if(part.done)break;length+=part.value.byteLength;if(length>1024*1024){await reader.cancel();throw Error('TRIP_ROUTE_UNAVAILABLE');}parts.push(part.value);}}finally{reader.releaseLock();}
    const data=JSON.parse(Buffer.concat(parts).toString('utf8')),r=data.routes?.[0],coords=r?.geometry?.coordinates;
    if(controller.signal.aborted||data.code!=='Ok'||r.geometry.type!=='LineString'||!Array.isArray(coords)||coords.length<2||coords.length>20000||!coords.every(p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&Math.abs(p[0])<=180&&Math.abs(p[1])<=90)||!Number.isFinite(r.distance)||r.distance<0||!Number.isFinite(r.duration)||r.duration<0)throw Error('TRIP_ROUTE_UNAVAILABLE');
    const route={...points,coordinates:coords,distanceMeters:Math.ceil(r.distance),durationSeconds:Math.ceil(r.duration),source:'MAPBOX_DIRECTIONS_V5',purpose:'DISPLAY_ONLY',measuredAt:new Date(now()).toISOString()};
    if(cache.size>=50)cache.clear();cache.set(key,{route,expires:now()+60000});return route;
   })()]);
  }catch{throw Error('TRIP_ROUTE_UNAVAILABLE');}finally{clearTimeout(timer);controller.abort();}
 };
}
let router;
async function readDriverTripRoute({db,GetCommand,table,driverId,orderId}){
 const read=async()=> (await db.send(new GetCommand({TableName:table,Key:{PK:'ORDER#'+orderId,SK:'META'},ConsistentRead:true}))).Item;
 const order=await read();
 const allowed=o=>o&&o.driverId===driverId&&['assigned','accepted','heading_to_store','arrived_at_store','picked_up','heading_to_customer','arrived_at_customer'].includes(o.status);
 if(!allowed(order))return {statusCode:404,result:{success:false,code:'ACTIVE_TRIP_REQUIRED'}};
 if(!router)router=createDriverTripRouter({getToken:async()=>{
  const arn=process.env.DRIVER_ROUTE_MAPBOX_SECRET_ARN;if(!arn)throw Error('TRIP_ROUTE_UNAVAILABLE');
  const {SecretsManagerClient,GetSecretValueCommand}=require('@aws-sdk/client-secrets-manager');
  const secret=await new SecretsManagerClient({}).send(new GetSecretValueCommand({SecretId:arn}));
  const value=secret.SecretString;try{const v=JSON.parse(value);return v.accessToken||v.access_token||v.token||v.MAPBOX_ACCESS_TOKEN;}catch{return value;}
 }});
 try{const route=await router(order);const current=await read();if(!allowed(current)||JSON.stringify(tripPoints(current))!==JSON.stringify(tripPoints(order)))return {statusCode:409,result:{success:false,code:'TRIP_CHANGED'}};return {statusCode:200,result:{success:true,orderId,route}};}
 catch{return {statusCode:503,result:{success:false,code:'TRIP_ROUTE_UNAVAILABLE',message:'تعذر تحميل مسار الطريق؛ أعد المحاولة أو افتح الملاحة'}};}
}
module.exports={tripPoints,pickupView,createDriverTripRouter,readDriverTripRoute};
