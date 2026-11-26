'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {merchantOrderConnections}=require('../src/functions/create-order/merchant-order-connections');

const scope={businessesTable:'businesses',connectionsTable:'connections',businessId:'branch'};
const connection=(id,userId,expiresAt)=>{
    return {connectionId:id,businessId:scope.businessId,userId,isActive:true,
        merchantScope345:{subjectId:userId,businessId:scope.businessId,expiresAt}};
};

test('notifications require a live socket belonging to the current branch owner',async()=>{
    const current=connection('current','new',200);
    const db={async send({input}){
        if(input.TableName==='businesses'){
            assert.equal(input.ConsistentRead,true);
            return {Item:{ownerId:'new',cognitoUserId:'new'}};
        }
        assert.equal(input.ExpressionAttributeValues[':owner'],'new');
        if(input.ExclusiveStartKey)return {Items:[current]};
        return {Items:[connection('old','old',200),connection('expired','new',90),
            {...current,connectionId:'legacy',merchantScope345:undefined}],
            LastEvaluatedKey:{connectionId:'legacy'}};
    }};
    assert.deepEqual(await merchantOrderConnections(db,scope,100),[current]);
});
