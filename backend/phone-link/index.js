 'use strict';
const crypto=require('node:crypto');
const {CognitoIdentityProviderClient,GetUserCommand,ListUsersCommand,AdminUpdateUserAttributesCommand}=require('@aws-sdk/client-cognito-identity-provider');
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand,QueryCommand,UpdateCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
const {SecretsManagerClient,GetSecretValueCommand}=require('@aws-sdk/client-secrets-manager');
const {normalizeIraqiPhone}=require('./iraqi-phone');
const {digest,matches}=require('./challenge-policy');
const {lifecycleFence}=require('./lifecycle-fence');
const {profileFor,profileCondition,owned}=require('./profile-link-451');
const c=new CognitoIdentityProviderClient({}),db=DynamoDBDocumentClient.from(new DynamoDBClient({})),secrets=new SecretsManagerClient({});
const table=process.env.OTP_TABLE,pool=process.env.USER_POOL_ID;
const reply=(statusCode,data)=>({statusCode,headers:{'Content-Type':'application/json','Cache-Control':'no-store'},body:JSON.stringify(data)});
const now=()=>Math.floor(Date.now()/1000);
async function identity(event){
 const token=(event.headers?.Authorization||event.headers?.authorization||'').replace(/^Bearer /,'');
 if(!token)throw Error('Unauthorized');
 // GetUser validates the token signature, expiry and live session. Decode claims
 // only after this succeeds, to restrict the valid session to this app and pool.
 const u=await c.send(new GetUserCommand({AccessToken:token}));
 const claims=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString());
 const attrs=Object.fromEntries(u.UserAttributes.map(a=>[a.Name,a.Value]));
 if(claims.iss!==`https://cognito-idp.us-east-1.amazonaws.com/${pool}`||claims.client_id!==process.env.CLIENT_ID||claims.token_use!=='access'||claims.sub!==attrs.sub)throw Error('Unauthorized');
 const lifecycle=await db.send(new GetCommand({TableName:process.env.DELETION_TABLE,Key:lifecycleFence(process.env.DELETION_TABLE,attrs.sub).ConditionCheck.Key,ConsistentRead:true}));
 if(lifecycle.Item)throw Error('ProfileMismatch');
 return {sub:attrs.sub,username:u.Username,attrs,authTime:claims.auth_time};
}
function recent(user){if(!Number.isInteger(user.authTime)||now()-user.authTime>900||user.authTime>now()+30)throw Error('Reauthenticate');}
async function available(phone,user){
 for(const value of [phone,'0'+phone.slice(4),phone.slice(4)]){
  const profiles=await db.send(new QueryCommand({TableName:process.env.USERS_TABLE,IndexName:'phone-index',KeyConditionExpression:'phone = :phone',ExpressionAttributeValues:{':phone':value},ProjectionExpression:'userId,cognitoSub,cognitoUsername,email',Limit:2}));
  if(profiles.LastEvaluatedKey||(profiles.Items||[]).some(p=>!owned(p,user)))throw Error('PhoneInUse');
 }
 const r=await c.send(new ListUsersCommand({UserPoolId:pool,Filter:`phone_number = "${phone}"`,Limit:2}));
 if(r.PaginationToken||r.Users.some(u=>u.Attributes.find(a=>a.Name==='sub')?.Value!==user.sub))throw Error('PhoneInUse');
 const {Item}=await db.send(new GetCommand({TableName:table,Key:{id:`PHONE#${phone}`},ConsistentRead:true}));
 if(Item&&Item.sub!==user.sub)throw Error('PhoneInUse');
}
async function secret(){const r=await secrets.send(new GetSecretValueCommand({SecretId:process.env.OTP_SECRET_ARN}));return JSON.parse(r.SecretString);}
async function send(user,phone,ip){
 recent(user);
 const profile=await profileFor(db,process.env.USERS_TABLE,user);
 if(profile.isActive===false||profile.deletionRequestId)throw Error('ProfileMismatch');
 if(profile.phoneChangePending)throw Error('ChangePending');
 if(user.attrs.phone_number_verified==='true'&&user.attrs.phone_number===phone&&profile.phone===phone)return {phone,verified:true,alreadyVerified:true};
 await available(phone,user);
 const time=now(),day=Math.floor(time/86400),id=crypto.randomUUID(),key=await secret(),code=String(crypto.randomInt(0,1000000)).padStart(6,'0');
 const limits=[{id:`COOLDOWN#${user.sub}`,cooldown:true},{id:`PHONE_COOLDOWN#${phone}`,cooldown:true},{id:`DAILY#${day}#${user.sub}`,limit:10},{id:`IP#${day}#${crypto.createHash('sha256').update(ip).digest('hex')}`,limit:30},{id:`GLOBAL#${day}`,limit:200}];
 const record={id,sub:user.sub,username:user.sub,phone,used:false,attempts:0,purpose:'phone-change-451',profileId:profile.userId,previousPhone:profile.phone??null,previousIdentityPhone:user.attrs.phone_number||null,expiresAt:time+300,digest:digest(key.hmacKey,id,user.sub,code)};
 await db.send(new TransactWriteCommand({TransactItems:[lifecycleFence(process.env.DELETION_TABLE,user.sub),...limits.map(x=>({Update:{TableName:table,Key:{id:x.id},UpdateExpression:x.cooldown?'SET nextAllowedAt = :next, expiresAt = :ttl':'SET expiresAt = :ttl ADD sends :one',ConditionExpression:x.cooldown?'attribute_not_exists(nextAllowedAt) OR nextAllowedAt <= :now':'attribute_not_exists(sends) OR sends < :limit',ExpressionAttributeValues:x.cooldown?{':next':time+60,':ttl':time+86400,':now':time}:{':ttl':time+172800,':one':1,':limit':x.limit}}})),{Put:{TableName:table,Item:record,ConditionExpression:'attribute_not_exists(id)'}},{Put:{TableName:table,Item:{id:`ACTIVE#${user.sub}`,sessionId:id,expiresAt:time+300}}}]}));
 const r=await fetch('https://api.otpiq.com/api/sms',{method:'POST',headers:{Authorization:`Bearer ${key.apiKey}`,'Content-Type':'application/json'},body:JSON.stringify({phoneNumber:phone.slice(1),smsType:'verification',provider:'whatsapp-telegram-sms',verificationCode:code}),signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw Error('DeliveryFailed');
 return {sessionId:id,expiresIn:300,resendAfter:60};
}
async function verify(user,body){
 if(typeof body.sessionId!=='string')throw Error('InvalidCode');
 const {Item:r}=await db.send(new GetCommand({TableName:table,Key:{id:body.sessionId},ConsistentRead:true}));
 if(!r||r.purpose!=='phone-change-451'||r.sub!==user.sub)throw Error('InvalidCode');
 const profile=await profileFor(db,process.env.USERS_TABLE,user);
 if(profile.userId!==r.profileId)throw Error('ProfileMismatch');
 if(r.state==='COMPLETED'){
  if(profile.phone!==r.phone||user.attrs.phone_number!==r.phone)throw Error('ChangePending');
  return {phone:r.phone,verified:true};
 }
 if(r.state!=='APPLYING'){
  recent(user);
  if(profile.phoneChangePending||user.attrs.phone_number!==(r.previousIdentityPhone||undefined))throw Error('ChangePending');
  const {Item:active}=await db.send(new GetCommand({TableName:table,Key:{id:`ACTIVE#${user.sub}`},ConsistentRead:true}));
  if(active?.sessionId!==r.id||r.used||r.attempts>=5||r.expiresAt<=now())throw Error('InvalidCode');
  const key=await secret(),correct=matches(key.hmacKey,r,user.sub,body.code,now());
  if(!correct){
   await db.send(new UpdateCommand({TableName:table,Key:{id:r.id},UpdateExpression:'ADD attempts :one',ConditionExpression:'used = :no AND attempts < :max AND expiresAt > :now',ExpressionAttributeValues:{':no':false,':max':5,':now':now(),':one':1}}));
   throw Error('InvalidCode');
  }
  await available(r.phone,user);
  const guard=profileCondition(profile,user);
  await db.send(new TransactWriteCommand({TransactItems:[
   lifecycleFence(process.env.DELETION_TABLE,user.sub),
   {Update:{TableName:table,Key:{id:`ACTIVE#${user.sub}`},UpdateExpression:'REMOVE expiresAt',ConditionExpression:'sessionId = :id',ExpressionAttributeValues:{':id':r.id}}},
   {Update:{TableName:table,Key:{id:r.id},UpdateExpression:'SET used = :yes, #state = :applying REMOVE expiresAt',ConditionExpression:'used = :no AND attempts < :max AND expiresAt > :now AND #subject = :sub',ExpressionAttributeNames:{'#subject':'sub','#state':'state'},ExpressionAttributeValues:{':yes':true,':applying':'APPLYING',':no':false,':max':5,':now':now(),':sub':user.sub}}},
   {Update:{TableName:process.env.USERS_TABLE,Key:{userId:profile.userId},...guard,UpdateExpression:'SET phoneChangePending = :id',ConditionExpression:guard.ConditionExpression+' AND attribute_not_exists(phoneChangePending) AND '+(r.previousPhone!==null?'phone = :old':'attribute_not_exists(phone)'),ExpressionAttributeValues:{...guard.ExpressionAttributeValues,':id':r.id,...(r.previousPhone!==null?{':old':r.previousPhone}:{})}}},
   {Update:{TableName:table,Key:{id:`PHONE#${r.phone}`},UpdateExpression:'SET #subject = :sub, operationId = :id',ConditionExpression:'attribute_not_exists(#subject) OR #subject = :sub',ExpressionAttributeNames:{'#subject':'sub'},ExpressionAttributeValues:{':sub':user.sub,':id':r.id}}}
  ]}));
 }else if(profile.phoneChangePending!==r.id){throw Error('ChangePending');}
 // Resume only the already authorized, owner-bound operation; never accept a new target here.
 const lifecycle=await db.send(new GetCommand({TableName:process.env.DELETION_TABLE,Key:lifecycleFence(process.env.DELETION_TABLE,user.sub).ConditionCheck.Key,ConsistentRead:true}));
 if(lifecycle.Item||profile.isActive===false||profile.deletionRequestId)throw Error('ProfileMismatch');
 if(user.attrs.phone_number!==r.phone){
  if((user.attrs.phone_number||null)!==r.previousIdentityPhone)throw Error('ChangePending');
  try {
  await c.send(new AdminUpdateUserAttributesCommand({UserPoolId:pool,Username:user.username,UserAttributes:[{Name:'phone_number',Value:r.phone},{Name:'phone_number_verified',Value:'true'}]}));
  } catch(error) {
   if(error.name==='AliasExistsException'){
    await db.send(new TransactWriteCommand({TransactItems:[
     {Update:{TableName:process.env.USERS_TABLE,Key:{userId:profile.userId},UpdateExpression:'REMOVE phoneChangePending',ConditionExpression:'phoneChangePending = :id',ExpressionAttributeValues:{':id':r.id}}},
     {Update:{TableName:table,Key:{id:r.id},UpdateExpression:'SET #state = :failed, expiresAt = :ttl',ConditionExpression:'#state = :applying AND #subject = :sub',ExpressionAttributeNames:{'#state':'state','#subject':'sub'},ExpressionAttributeValues:{':failed':'FAILED',':ttl':now()+86400,':applying':'APPLYING',':sub':user.sub}}},
     {Delete:{TableName:table,Key:{id:`PHONE#${r.phone}`},ConditionExpression:'#subject = :sub AND operationId = :id',ExpressionAttributeNames:{'#subject':'sub'},ExpressionAttributeValues:{':sub':user.sub,':id':r.id}}}
    ]}));
   }
   throw error;
  }

 }
 const guard=profileCondition(profile,user),at=new Date().toISOString();
 await db.send(new TransactWriteCommand({TransactItems:[
  lifecycleFence(process.env.DELETION_TABLE,user.sub),
  {Update:{TableName:process.env.USERS_TABLE,Key:{userId:profile.userId},...guard,UpdateExpression:'SET phone = :phone, phoneNumber = :phone, phoneVerified = :yes, updatedAt = :at REMOVE phoneChangePending',ConditionExpression:guard.ConditionExpression+' AND phoneChangePending = :id',ExpressionAttributeValues:{...guard.ExpressionAttributeValues,':phone':r.phone,':yes':true,':at':at,':id':r.id}}},
  {Update:{TableName:table,Key:{id:r.id},UpdateExpression:'SET #state = :done, expiresAt = :ttl, completedAt = :at',ConditionExpression:'#state = :applying AND #subject = :sub',ExpressionAttributeNames:{'#state':'state','#subject':'sub'},ExpressionAttributeValues:{':done':'COMPLETED',':ttl':now()+86400,':at':at,':applying':'APPLYING',':sub':user.sub}}},
  {Update:{TableName:table,Key:{id:`ACTIVE#${user.sub}`},UpdateExpression:'SET expiresAt = :ttl',ConditionExpression:'sessionId = :id',ExpressionAttributeValues:{':id':r.id,':ttl':now()+86400}}},
  ...(r.previousIdentityPhone&&r.previousIdentityPhone!==r.phone?[{Delete:{TableName:table,Key:{id:`PHONE#${r.previousIdentityPhone}`},ConditionExpression:'attribute_not_exists(#subject) OR #subject = :sub',ExpressionAttributeNames:{'#subject':'sub'},ExpressionAttributeValues:{':sub':user.sub}}}]:[])
 ]}));
 return {phone:r.phone,verified:true};
}
exports.handler=async event=>{
 try{
  if(process.env.ENVIRONMENT!=='staging')throw Error('Unavailable');
  const u=await identity(event);
  if(event.httpMethod==='GET'&&event.path.endsWith('/status')){const profile=await profileFor(db,process.env.USERS_TABLE,u);if(profile.isActive===false||profile.deletionRequestId)throw Error('ProfileMismatch');return reply(200,{phone:u.attrs.phone_number||'',verified:u.attrs.phone_number_verified==='true',requiresReauthentication:!Number.isInteger(u.authTime)||now()-u.authTime>900,pendingSessionId:profile.phoneChangePending||null});}
  if(event.httpMethod!=='POST')return reply(405,{message:'هذه العملية غير متاحة'});
  const b=JSON.parse(event.body||'{}');
  if(event.path.endsWith('/send'))return reply(200,await send(u,normalizeIraqiPhone(b.phone),event.requestContext?.identity?.sourceIp||'unknown'));
  if(event.path.endsWith('/verify'))return reply(200,await verify(u,b));
  return reply(404,{message:'المسار غير متاح'});
 }catch(e){
  const m=e.message;
  if(m==='Unauthorized'||e.name==='NotAuthorizedException'||e.name==='UserNotFoundException')return reply(401,{message:'يرجى تسجيل الدخول مجددًا'});
  if(m==='Reauthenticate')return reply(403,{code:'REAUTH_REQUIRED',message:'لأمان حسابك، أكّد هويتك برمز على رقمك الحالي قبل تغييره'});
  if(m==='ProfileMismatch')return reply(409,{code:'PROFILE_MISMATCH',message:'تعذر تأكيد ارتباط الرقم بالحساب؛ تواصل مع الدعم'});
  if(m==='ChangePending')return reply(409,{code:'PHONE_CHANGE_PENDING',message:'يوجد تحديث رقم قيد الإكمال؛ حدّث الحالة وأكمل العملية نفسها'});
  if(m==='PhoneInUse'||e.name==='AliasExistsException')return reply(409,{message:'الرقم مرتبط بحساب آخر؛ استخدم استعادة الحساب'});
  if(m==='InvalidCode')return reply(400,{message:'الرمز غير صحيح أو انتهت صلاحيته'});
  if(e.name==='TransactionCanceledException')return reply(429,{message:'انتظر قبل إعادة المحاولة أو اطلب رمزًا جديدًا'});
  if(e instanceof SyntaxError||e instanceof TypeError||m?.includes('Only Iraqi'))return reply(400,{message:'أدخل رقم هاتف عراقي صحيح'});
  console.error('Phone link failed',e.name);return reply(503,{message:'تعذر إكمال العملية، حاول لاحقًا'});
 }
};
