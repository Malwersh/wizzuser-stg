 'use strict';
const crypto=require('node:crypto');
const {CognitoIdentityProviderClient,GetUserCommand,ListUsersCommand,AdminUpdateUserAttributesCommand}=require('@aws-sdk/client-cognito-identity-provider');
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand,QueryCommand,UpdateCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
const {SecretsManagerClient,GetSecretValueCommand}=require('@aws-sdk/client-secrets-manager');
const {normalizeIraqiPhone}=require('./iraqi-phone');
const {digest,matches}=require('./challenge-policy');
const {lifecycleFence}=require('./lifecycle-fence');
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
 if(!Number.isInteger(claims.auth_time)||now()-claims.auth_time>900||claims.auth_time>now()+30)throw Error('Reauthenticate');
 return {sub:attrs.sub,username:u.Username,attrs};
}
async function syncProfile(user,phone){
 // A confirmed Cognito email identifies the legacy profile. Neither profile ID
 // nor email is accepted from the request body.
 if(user.attrs.email_verified!=='true'||!user.attrs.email)return;
 const r=await db.send(new QueryCommand({TableName:process.env.USERS_TABLE,IndexName:'email-index',KeyConditionExpression:'email = :email',ExpressionAttributeValues:{':email':user.attrs.email},Limit:2}));
 if(r.LastEvaluatedKey||r.Items?.length!==1)return;
 const profile=r.Items[0];
 if(profile.cognitoUsername!==user.username&&profile.cognitoUsername!==user.attrs.email)return;
 await db.send(new UpdateCommand({TableName:process.env.USERS_TABLE,Key:{userId:profile.userId},UpdateExpression:'SET phone = :phone, phoneVerified = :verified, updatedAt = :at',ConditionExpression:'attribute_exists(userId) AND email = :email AND cognitoUsername = :username AND (attribute_not_exists(cognitoSub) OR cognitoSub = :sub) AND (attribute_not_exists(isActive) OR isActive = :active) AND attribute_not_exists(deletionRequestId)',ExpressionAttributeValues:{':phone':phone,':verified':true,':at':new Date().toISOString(),':email':user.attrs.email,':username':profile.cognitoUsername,':sub':user.sub,':active':true}}));
}
async function available(phone,user){
 const r=await c.send(new ListUsersCommand({UserPoolId:pool,Filter:`phone_number = "${phone}"`,Limit:2}));
 if(r.PaginationToken||r.Users.some(u=>u.Attributes.find(a=>a.Name==='sub')?.Value!==user.sub))throw Error('PhoneInUse');
 const {Item}=await db.send(new GetCommand({TableName:table,Key:{id:`PHONE#${phone}`},ConsistentRead:true}));
 if(Item&&Item.sub!==user.sub)throw Error('PhoneInUse');
}
async function secret(){const r=await secrets.send(new GetSecretValueCommand({SecretId:process.env.OTP_SECRET_ARN}));return JSON.parse(r.SecretString);}
async function send(user,phone,ip){
 await available(phone,user);
 const time=now(),day=Math.floor(time/86400),id=crypto.randomUUID(),key=await secret(),code=String(crypto.randomInt(0,1000000)).padStart(6,'0');
 const limits=[{id:`COOLDOWN#${user.sub}`,cooldown:true},{id:`PHONE_COOLDOWN#${phone}`,cooldown:true},{id:`DAILY#${day}#${user.sub}`,limit:10},{id:`IP#${day}#${crypto.createHash('sha256').update(ip).digest('hex')}`,limit:30},{id:`GLOBAL#${day}`,limit:200}];
 const record={id,sub:user.sub,username:user.sub,phone,used:false,attempts:0,purpose:'phone-link',expiresAt:time+300,digest:digest(key.hmacKey,id,user.sub,code)};
 await db.send(new TransactWriteCommand({TransactItems:[lifecycleFence(process.env.DELETION_TABLE,user.sub),...limits.map(x=>({Update:{TableName:table,Key:{id:x.id},UpdateExpression:x.cooldown?'SET nextAllowedAt = :next, expiresAt = :ttl':'SET expiresAt = :ttl ADD sends :one',ConditionExpression:x.cooldown?'attribute_not_exists(nextAllowedAt) OR nextAllowedAt <= :now':'attribute_not_exists(sends) OR sends < :limit',ExpressionAttributeValues:x.cooldown?{':next':time+60,':ttl':time+86400,':now':time}:{':ttl':time+172800,':one':1,':limit':x.limit}}})),{Put:{TableName:table,Item:record,ConditionExpression:'attribute_not_exists(id)'}},{Put:{TableName:table,Item:{id:`ACTIVE#${user.sub}`,sessionId:id,expiresAt:time+300}}}]}));
 const r=await fetch('https://api.otpiq.com/api/sms',{method:'POST',headers:{Authorization:`Bearer ${key.apiKey}`,'Content-Type':'application/json'},body:JSON.stringify({phoneNumber:phone.slice(1),smsType:'verification',provider:'whatsapp-sms',verificationCode:code}),signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw Error('DeliveryFailed');
 return {sessionId:id,expiresIn:300,resendAfter:60};
}
async function verify(user,body){
 if(typeof body.sessionId!=='string'||! /^[0-9]{6}$/.test(body.code||''))throw Error('InvalidCode');
 const [{Item:r},{Item:active}]=await Promise.all([db.send(new GetCommand({TableName:table,Key:{id:body.sessionId},ConsistentRead:true})),db.send(new GetCommand({TableName:table,Key:{id:`ACTIVE#${user.sub}`},ConsistentRead:true}))]);
 if(!r||r.purpose!=='phone-link'||r.sub!==user.sub||active?.sessionId!==r.id)throw Error('InvalidCode');
 const key=await secret(),correct=matches(key.hmacKey,r,user.sub,body.code,now());
 if(r.used||r.attempts>=5||r.expiresAt<=now())throw Error('InvalidCode');
 if(correct)await available(r.phone,user);
 await db.send(new TransactWriteCommand({TransactItems:[lifecycleFence(process.env.DELETION_TABLE,user.sub),{ConditionCheck:{TableName:table,Key:{id:`ACTIVE#${user.sub}`},ConditionExpression:'sessionId = :id',ExpressionAttributeValues:{':id':r.id}}},{Update:{TableName:table,Key:{id:r.id},UpdateExpression:correct?'SET used = :true ADD attempts :one':'ADD attempts :one',ConditionExpression:'used = :false AND attempts < :max AND expiresAt > :now AND #subject = :sub',ExpressionAttributeNames:{'#subject':'sub'},ExpressionAttributeValues:{':false':false,':max':5,':now':now(),':one':1,':sub':user.sub,...(correct?{':true':true}:{})}}},...(correct?[{Update:{TableName:table,Key:{id:`PHONE#${r.phone}`},UpdateExpression:'SET #subject = :sub, verifiedAt = :at',ConditionExpression:'attribute_not_exists(#subject) OR #subject = :sub',ExpressionAttributeNames:{'#subject':'sub'},ExpressionAttributeValues:{':sub':user.sub,':at':new Date().toISOString()}}}]:[])]}));
 if(!correct)throw Error('InvalidCode');
 // Never move an alias from another user, create an account, or change its sub.
 await c.send(new AdminUpdateUserAttributesCommand({UserPoolId:pool,Username:user.username,UserAttributes:[{Name:'phone_number',Value:r.phone},{Name:'phone_number_verified',Value:'true'}]}));
 await syncProfile(user,r.phone);
 return {phone:r.phone,verified:true};
}
exports.handler=async event=>{
 try{
  if(process.env.ENVIRONMENT!=='staging')throw Error('Unavailable');
  const u=await identity(event);
  if(event.httpMethod==='GET'&&event.path.endsWith('/status')){if(u.attrs.phone_number_verified==='true')await syncProfile(u,u.attrs.phone_number);return reply(200,{phone:u.attrs.phone_number||'',verified:u.attrs.phone_number_verified==='true'});}
  if(event.httpMethod!=='POST')return reply(405,{message:'هذه العملية غير متاحة'});
  const b=JSON.parse(event.body||'{}');
  if(event.path.endsWith('/send'))return reply(200,await send(u,normalizeIraqiPhone(b.phone),event.requestContext?.identity?.sourceIp||'unknown'));
  if(event.path.endsWith('/verify'))return reply(200,await verify(u,b));
  return reply(404,{message:'المسار غير متاح'});
 }catch(e){
  const m=e.message;
  if(m==='Unauthorized'||e.name==='NotAuthorizedException'||e.name==='UserNotFoundException')return reply(401,{message:'يرجى تسجيل الدخول مجددًا'});
  if(m==='Reauthenticate')return reply(403,{code:'REAUTH_REQUIRED',message:'أعد تسجيل الدخول قبل توثيق الهاتف'});
  if(m==='PhoneInUse'||e.name==='AliasExistsException')return reply(409,{message:'الرقم مرتبط بحساب آخر؛ استخدم استعادة الحساب'});
  if(m==='InvalidCode')return reply(400,{message:'الرمز غير صحيح أو انتهت صلاحيته'});
  if(e.name==='TransactionCanceledException')return reply(429,{message:'انتظر قبل إعادة المحاولة أو اطلب رمزًا جديدًا'});
  if(e instanceof SyntaxError||e instanceof TypeError||m?.includes('Only Iraqi'))return reply(400,{message:'أدخل رقم هاتف عراقي صحيح'});
  console.error('Phone link failed',e.name);return reply(503,{message:'تعذر إكمال العملية، حاول لاحقًا'});
 }
};
