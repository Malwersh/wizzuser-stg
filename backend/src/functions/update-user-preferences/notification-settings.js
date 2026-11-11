'use strict';
const keys=['order_notifications','promotion_notifications','newsletter_notifications','reminder_notifications','sound_enabled','vibration_enabled'];
function mergeNotificationSettings(current,input){
 if(!input||typeof input!=='object'||Array.isArray(input)||!Object.keys(input).length||Object.entries(input).some(([key,value])=>!keys.includes(key)||typeof value!=='boolean')) {
  throw Object.assign(Error('INVALID_NOTIFICATION_SETTINGS'),{statusCode:400});
 }
 const result={};for(const key of keys)if(typeof current?.[key]==='boolean')result[key]=current[key];
 return {...result,...input};
}
module.exports={mergeNotificationSettings};
