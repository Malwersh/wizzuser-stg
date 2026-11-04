'use strict';
const crypto=require('node:crypto');
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand,PutCommand,QueryCommand,UpdateCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
const {SecretsManagerClient,GetSecretValueCommand}=require('@aws-sdk/client-secrets-manager');
const {CognitoIdentityProviderClient,ListUsersCommand,AdminCreateUserCommand,AdminSetUserPasswordCommand,AdminInitiateAuthCommand,AdminRespondToAuthChallengeCommand}=require('@aws-sdk/client-cognito-identity-provider');
const {normalizeIraqiPhone}=require('./iraqi-phone');const {digest,matches}=require('./challenge-policy');const {newProof}=require('./login-proof');
const {attributes,eligible,belongs,publicProfile}=require('./profile-policy');
const {lifecycleFence}=require('./lifecycle-fence');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({})),c=new CognitoIdentityProviderClient({}),secrets=new SecretsManagerClient({});
const table=process.env.OTP_TABLE,pool=process.env.USER_POOL_ID,usersTable=process.env.USERS_TABLE;
const legalDocuments=require('./customer-legal-contract-344');
const validEnrollment=body=>typeof body.name==='string' && body.name.trim().length>=2 && body.name.trim().length<=80 && !/[\u0000-\u001f]/.test(body.name) && body.termsAccepted===true && body.privacyAccepted===true && body.usageAccepted===true;
const now=()=>Math.floor(Date.now()/1000);const reply=(statusCode,body)=>({statusCode,headers:{'Content-Type':'application/json','Cache-Control':'no-store'},body:JSON.stringify(body)});
async function config(){const r=await secrets.send(new GetSecretValueCommand({SecretId:process.env.OTP_SECRET_ARN}));const v=JSON.parse(r.SecretString);if(!v.apiKey||!v.hmacKey)throw Error('Configuration');return v;}
async function findUser(phone){const r=await c.send(new ListUsersCommand({UserPoolId:pool,Filter:`phone_number = "${phone}"`,Limit:2}));if(r.PaginationToken||r.Users.length>1)throw Error('RecoveryRequired');return r.Users[0];}
async function profilesByPhone(phone){const rows=new Map();for(const value of [phone,'0'+phone.slice(4),phone.slice(4)]){const r=await db.send(new QueryCommand({TableName:usersTable,IndexName:'phone-index',KeyConditionExpression:'phone = :phone',ExpressionAttributeValues:{':phone':value},Limit:2}));if(r.LastEvaluatedKey)throw Error('RecoveryRequired');for(const p of r.Items||[])rows.set(p.userId,p);}return [...rows.values()];}
async function profileFor(user,phone){
 const a=attributes(user),r=await db.send(new GetCommand({TableName:usersTable,Key:{userId:a.sub},ConsistentRead:true}));if(r.Item){if(!belongs(r.Item,user))throw Error('RecoveryRequired');return r.Item;}
 let rows=await profilesByPhone(phone);
 if(a.email && a.email_verified==='true'){const r=await db.send(new QueryCommand({TableName:usersTable,IndexName:'email-index',KeyConditionExpression:'email = :email',ExpressionAttributeValues:{':email':a.email},Limit:2}));if(r.LastEvaluatedKey)throw Error('RecoveryRequired');rows=[...new Map([...rows,...(r.Items||[])].map(p=>[p.userId,p])).values()];}
 if(rows.length!==1 || !belongs(rows[0],user))throw Error('RecoveryRequired');return rows[0];
}
async function send(phone,event,key){
 const existing=await findUser(phone);
 if(existing&&!existing.Enabled)throw Error('AccountClosing');
 const sendFence=existing?[lifecycleFence(process.env.DELETION_TABLE,attributes(existing).sub)]:[];
 const time=now(),day=Math.floor(time/86400),ip=event.requestContext?.identity?.sourceIp||'unknown';
 const limits=[{id:`COOLDOWN#${phone}`,cooldown:true},{id:`DAILY#${day}#${phone}`,limit:10},{id:`IP#${day}#${crypto.createHash('sha256').update(ip).digest('hex')}`,limit:30},{id:`GLOBAL#${day}`,limit:200}];
 await db.send(new TransactWriteCommand({TransactItems:[...sendFence,...limits.map(x=>({Update:{TableName:table,Key:{id:x.id},UpdateExpression:x.cooldown?'SET nextAllowedAt = :next, expiresAt = :ttl':'SET expiresAt = :ttl ADD sends :one',ConditionExpression:x.cooldown?'attribute_not_exists(nextAllowedAt) OR nextAllowedAt <= :now':'attribute_not_exists(sends) OR sends < :limit',ExpressionAttributeValues:x.cooldown?{':next':time+60,':ttl':time+86400,':now':time}:{':ttl':time+172800,':one':1,':limit':x.limit}}}))]}));
 const id=crypto.randomUUID(),code=String(crypto.randomInt(0,1000000)).padStart(6,'0');
 await db.send(new TransactWriteCommand({TransactItems:[...sendFence,{Put:{TableName:table,Item:{id,phone,username:phone,purpose:'customer-phone-otp',expiresAt:time+300,attempts:0,used:false,digest:digest(key.hmacKey,id,phone,code)},ConditionExpression:'attribute_not_exists(id)'}},{Put:{TableName:table,Item:{id:`ACTIVE#${phone}`,sessionId:id,expiresAt:time+300}}}]}));
 const response=await fetch('https://api.otpiq.com/api/sms',{method:'POST',headers:{Authorization:`Bearer ${key.apiKey}`,'Content-Type':'application/json'},body:JSON.stringify({phoneNumber:phone.slice(1),smsType:'verification',provider:'whatsapp-telegram-sms',verificationCode:code}),signal:AbortSignal.timeout(10000)});
 if(!response.ok)return reply(503,{message:'تعذر إرسال الرمز. حاول لاحقًا'});return reply(200,{sessionId:id,expiresIn:300,resendAfter:60});
}
async function provision(phone,body){
 const name=String(body.name||'').trim();if(name.length<2||name.length>80||/[\u0000-\u001f]/.test(name)||body.termsAccepted!==true||body.privacyAccepted!==true)return null;
 if((await profilesByPhone(phone)).length)throw Error('RecoveryRequired');
 const r=await c.send(new AdminCreateUserCommand({UserPoolId:pool,Username:phone,MessageAction:'SUPPRESS',UserAttributes:[{Name:'name',Value:name},{Name:'phone_number',Value:phone},{Name:'phone_number_verified',Value:'true'}],TemporaryPassword:`Aa1!${crypto.randomBytes(32).toString('hex')}`}));
 const user=r.User,a=attributes(user);
 await db.send(new PutCommand({TableName:table,Item:{id:`PROVISION#${phone}`,username:user.Username,sub:a.sub,name,createdAt:new Date().toISOString()}}));
 await c.send(new AdminSetUserPasswordCommand({UserPoolId:pool,Username:user.Username,Password:`Aa1!${crypto.randomBytes(48).toString('hex')}`,Permanent:true}));
 user.UserStatus='CONFIRMED';return user;
}
async function verify(phone,body,key){
 if(typeof body.sessionId!=='string'||!/^[0-9]{6}$/.test(body.code||''))return reply(400,{message:'أدخل رمزًا من 6 أرقام'});
 const [{Item:r},{Item:active}]=await Promise.all([db.send(new GetCommand({TableName:table,Key:{id:body.sessionId},ConsistentRead:true})),db.send(new GetCommand({TableName:table,Key:{id:`ACTIVE#${phone}`},ConsistentRead:true}))]);
 const time=now();if(!r||r.purpose!=='customer-phone-otp'||r.phone!==phone||active?.sessionId!==r.id||r.used||r.attempts>=5||r.expiresAt<=time)return reply(400,{message:'انتهى الرمز أو جلسة التحقق؛ اطلب رمزًا جديدًا'});
 const correct=matches(key.hmacKey,r,phone,body.code,time);
 if(!correct){await db.send(new UpdateCommand({TableName:table,Key:{id:r.id},UpdateExpression:'ADD attempts :one',ConditionExpression:'used = :no AND attempts < :max AND expiresAt > :now',ExpressionAttributeValues:{':no':false,':max':5,':now':time,':one':1}}));return reply(400,{message:'رمز التحقق غير صحيح'});}
 let user=await findUser(phone),profile;
 if(user){
  const {Item:p}=await db.send(new GetCommand({TableName:table,Key:{id:`PROVISION#${phone}`},ConsistentRead:true}));
  if(user.Enabled&&user.UserStatus==='FORCE_CHANGE_PASSWORD'&&p?.username===user.Username&&attributes(user).phone_number_verified==='true'){
   await c.send(new AdminSetUserPasswordCommand({UserPoolId:pool,Username:user.Username,Password:`Aa1!${crypto.randomBytes(48).toString('hex')}`,Permanent:true}));user.UserStatus='CONFIRMED';
  }
  if(!eligible(user))throw Error('RecoveryRequired');
  try{profile=await profileFor(user,phone);}catch(e){if(e.message!=='RecoveryRequired'||p?.username!==user.Username||p?.sub!==attributes(user).sub)throw e;}
 }else if(!validEnrollment(body)){return reply(200,{needsName:true});}
 let legalConsent=null;
 if(!profile){
  if(!validEnrollment(body))return reply(200,{needsName:true});
  if(!body.legalAcceptance)throw Object.assign(Error('LEGAL_ACCEPTANCE_REQUIRED'),{statusCode:409});
  legalConsent=await legalDocuments.consent(db,GetCommand,process.env.LEGAL_SETTINGS_TABLE,body.legalAcceptance);
 }
 // Consume current OTP atomically before any account creation or authentication.
 await db.send(new TransactWriteCommand({TransactItems:[...(legalConsent?[legalConsent.condition]:[]),{ConditionCheck:{TableName:table,Key:{id:`ACTIVE#${phone}`},ConditionExpression:'sessionId = :id',ExpressionAttributeValues:{':id':r.id}}},{Update:{TableName:table,Key:{id:r.id},UpdateExpression:'SET used = :yes ADD attempts :one',ConditionExpression:'used = :no AND attempts < :max AND expiresAt > :now',ExpressionAttributeValues:{':yes':true,':no':false,':max':5,':now':time,':one':1}}}]}));
 if(!user){user=await provision(phone,body);if(!user)return reply(400,{message:'الاسم والموافقة على الشروط مطلوبان'});}
 const a=attributes(user),timestamp=new Date().toISOString();
 const fence=lifecycleFence(process.env.DELETION_TABLE,a.sub);
 const lifecycle=await db.send(new GetCommand({TableName:process.env.DELETION_TABLE,Key:fence.ConditionCheck.Key,ConsistentRead:true}));
 if(lifecycle.Item)throw Error('AccountClosing');
 if(!profile){
  const {Item:p}=await db.send(new GetCommand({TableName:table,Key:{id:`PROVISION#${phone}`},ConsistentRead:true}));if(p?.username!==user.Username||p?.sub!==a.sub)throw Error('RecoveryRequired');
  profile={userId:a.sub,cognitoSub:a.sub,cognitoUsername:user.Username,name:p.name,phone,phoneVerified:true,registrationMethod:'phone-otp',isActive:true,termsAccepted:true,privacyAccepted:true,usageAccepted:true,legalAcceptance:{schemaVersion:1,subjectId:a.sub,acceptedAt:timestamp,...legalDocuments.pin(legalConsent.bundle),documentSnapshot:legalConsent.bundle},preferredLanguage:'ar',createdAt:p.createdAt||timestamp,updatedAt:timestamp};
  await db.send(new TransactWriteCommand({TransactItems:[fence,{Put:{TableName:usersTable,Item:profile,ConditionExpression:'attribute_not_exists(userId)'}}]}));
 }
 if(profile.isActive===false)throw Error('RecoveryRequired');
 // Never overwrite existing balances; create only the canonical zero wallet.
 const walletKey={walletId:`WALLET#CUSTOMER#${a.sub}`,sk:'META'};
 const existingWallet=(await db.send(new GetCommand({TableName:process.env.WALLETS_TABLE,Key:walletKey,ConsistentRead:true}))).Item;
 if(existingWallet){if(existingWallet.ownerId!==a.sub||existingWallet.status!=='ACTIVE'||existingWallet.deletionRequestId)throw Error('AccountClosing');}
 else await db.send(new TransactWriteCommand({TransactItems:[fence,{Put:{TableName:process.env.WALLETS_TABLE,Item:{...walletKey,ownerType:'CUSTOMER',ownerId:a.sub,currency:'IQD',status:'ACTIVE',availableBalance:0,lockedBalance:0,minRequiredBalance:0,version:1,createdAt:timestamp,updatedAt:timestamp},ConditionExpression:'attribute_not_exists(walletId)'}}]}));
 const proof=newProof(key.hmacKey,user.Username,now());
 await db.send(new TransactWriteCommand({TransactItems:[fence,{Put:{TableName:table,Item:proof.record,ConditionExpression:'attribute_not_exists(id)'}},{Put:{TableName:table,Item:{id:`LOGIN#${user.Username}`,proofId:proof.record.id,expiresAt:proof.record.expiresAt}}}]}));
 const start=await c.send(new AdminInitiateAuthCommand({UserPoolId:pool,ClientId:process.env.CLIENT_ID,AuthFlow:'CUSTOM_AUTH',AuthParameters:{USERNAME:user.Username}}));
 if(start.ChallengeName!=='CUSTOM_CHALLENGE'||!start.Session)throw Error('AuthenticationFailed');
 const auth=await c.send(new AdminRespondToAuthChallengeCommand({UserPoolId:pool,ClientId:process.env.CLIENT_ID,ChallengeName:'CUSTOM_CHALLENGE',Session:start.Session,ChallengeResponses:{USERNAME:user.Username,ANSWER:proof.answer}}));
 if(!auth.AuthenticationResult?.AccessToken||!auth.AuthenticationResult?.RefreshToken)throw Error('AuthenticationFailed');
 const result=auth.AuthenticationResult;return reply(200,{user:publicProfile(profile),accessToken:result.AccessToken,idToken:result.IdToken,refreshToken:result.RefreshToken});
}
exports.handler=async e=>{try{if(process.env.ENVIRONMENT!=='staging')throw Error('Environment');if(e.httpMethod==='GET'&&e.path==='/legal')return reply(200,{bundle:await legalDocuments.published(db,GetCommand,process.env.LEGAL_SETTINGS_TABLE,e.queryStringParameters?.audience??'CUSTOMER')});const body=JSON.parse(e.body||'{}'),phone=normalizeIraqiPhone(body.phone),key=await config();if(e.path.endsWith('/send'))return await send(phone,e,key);if(e.path.endsWith('/verify'))return await verify(phone,body,key);return reply(404,{message:'غير موجود'});}catch(x){if(['LEGAL_VERSION_CHANGED','LEGAL_ACCEPTANCE_REQUIRED'].includes(x.message))return reply(409,{code:x.message,message:'تحدّثت السياسات؛ راجع النص المنشور ووافق عليه قبل إكمال التسجيل'});if(x.message==='LEGAL_DOCUMENTS_UNAVAILABLE')return reply(503,{code:x.message,message:'تعذر تحميل السياسات المنشورة. أعد المحاولة لاحقًا'});if(x.message==='AccountClosing')return reply(409,{code:'ACCOUNT_CLOSING',message:'هذا الحساب قيد الحذف ولا يمكن تسجيل الدخول إليه'});if(x.message==='RecoveryRequired')return reply(409,{code:'PHONE_LINK_REQUIRED',message:'هذا الحساب يحتاج ربط الهاتف بأمان. سجّل الدخول بالبريد ثم وثّق رقمك'});if(['TransactionCanceledException','ConditionalCheckFailedException','TooManyRequestsException'].includes(x.name))return reply(429,{message:'انتظر قليلًا قبل إعادة المحاولة'});if(x instanceof SyntaxError||x.message?.includes('Only Iraqi')||x instanceof TypeError)return reply(400,{message:'أدخل رقم هاتف عراقي صحيح'});console.error('Customer phone auth failed',{name:x.name,kind:x.message==='AuthenticationFailed'?'authentication':'service'});return reply(503,{message:'تعذر إكمال العملية؛ اطلب رمزًا جديدًا وحاول مرة أخرى'});}};
