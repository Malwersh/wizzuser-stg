'use strict';

const {GetCommand,ScanCommand}=require('@aws-sdk/lib-dynamodb');

async function merchantOrderConnections(db,{businessesTable,connectionsTable,businessId},now=Math.floor(Date.now()/1000)){
    const {Item:branch}=await db.send(new GetCommand({
        TableName:businessesTable,
        Key:{businessId},
        ConsistentRead:true,
        ProjectionExpression:'ownerId, cognitoUserId, deletionRequestId'
    }));
    const ownerId=branch?.ownerId;
    if(!ownerId||branch.cognitoUserId!==ownerId||branch.deletionRequestId)return [];

    const connections=[];
    let cursor;
    do{
        const page=await db.send(new ScanCommand({
            TableName:connectionsTable,
            FilterExpression:'businessId=:branch AND isActive=:active AND #scope.#owner=:owner',
            ProjectionExpression:'connectionId, businessId, userId, isActive, #scope, #ttl',
            ExpressionAttributeNames:{'#scope':'merchantScope345','#owner':'subjectId','#ttl':'ttl'},
            ExpressionAttributeValues:{':branch':businessId,':active':true,':owner':ownerId},
            ExclusiveStartKey:cursor
        }));
        for(const row of page.Items||[]){
            const scope=row.merchantScope345;
            if(row.connectionId&&row.businessId===businessId&&row.userId===ownerId&&row.isActive===true&&
                scope?.subjectId===ownerId&&scope.businessId===businessId&&Number.isFinite(scope.expiresAt)&&
                scope.expiresAt>now&&(!row.ttl||row.ttl>now)){
                connections.push(row);
            }
        }
        cursor=page.LastEvaluatedKey;
    }while(cursor);
    return connections;
}

module.exports={merchantOrderConnections};
