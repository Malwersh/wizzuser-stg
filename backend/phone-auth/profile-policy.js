'use strict';
function attributes(user){return Object.fromEntries((user.Attributes||[]).map(a=>[a.Name,a.Value]));}
function eligible(user){const a=attributes(user);return !!user.Enabled && user.UserStatus==='CONFIRMED' && a.phone_number_verified==='true' && !!a.sub;}
function belongs(profile,user){const a=attributes(user);return profile.userId===a.sub || profile.cognitoSub===a.sub || profile.cognitoUsername===user.Username || (a.email_verified==='true' && profile.email===a.email && profile.cognitoUsername===a.email);}
function publicProfile(p){return {userId:p.userId,name:p.name||'',phone:p.phone,phoneVerified:true,email:p.email||'',birthDate:p.birthDate,gender:p.gender,profileImage:p.profileImage,isActive:p.isActive!==false,preferredLanguage:p.preferredLanguage||'ar',addresses:p.addresses||[],termsAccepted:p.termsAccepted,privacyAccepted:p.privacyAccepted,createdAt:p.createdAt};}
module.exports={attributes,eligible,belongs,publicProfile};
