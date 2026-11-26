const {test}=require('node:test'),assert=require('node:assert/strict');
const {mergeNotificationSettings:merge}=require('./notification-settings');
test('false remains false and unrelated existing preferences survive',()=>{assert.deepEqual(merge({sound_enabled:false,promotion_notifications:true},{promotion_notifications:false}),{sound_enabled:false,promotion_notifications:false});});
test('invalid types or unknown keys cannot be persisted',()=>{for(const value of [null,[],{},'false',{promotion_notifications:'false'},{admin:true}])assert.throws(()=>merge({},value),e=>e.statusCode===400);});
