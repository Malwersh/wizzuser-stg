'use strict';
function lifecycleFence(table,sub){
 if(table!=='staging-AccountDeletion'||typeof sub!=='string'||!sub)throw Error('InvalidLifecycleConfiguration');
 return {ConditionCheck:{TableName:table,Key:{pk:'ACCOUNT_LIFECYCLE#CUSTOMER#'+sub,sk:'META'},ConditionExpression:'attribute_not_exists(pk)'}};
}
module.exports={lifecycleFence};
