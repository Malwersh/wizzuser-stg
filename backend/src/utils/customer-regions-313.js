'use strict';
const enabled=v=>v===true||v===1||v==='1'||v==='true';
const fail=(code,status=503)=>Object.assign(Error(code),{code,status,statusCode:status});
const delivery=d=>{const v=d?.effective_config?.delivery;return enabled(v)||(!!v&&typeof v==='object'&&!Array.isArray(v)&&(v.available===undefined||enabled(v.available))&&(v.enabled===undefined||enabled(v.enabled)));};
function create({db,sdk,tables}){
 if(Object.values(tables).some(x=>!x))throw fail('REGION_CONFIG_UNAVAILABLE');
 async function get(table,id){return (await db.send(new sdk.GetCommand({TableName:table,Key:{regionId:id},ConsistentRead:true}))).Item;}
 async function ancestry(id){
  const path=[],seen=new Set();let next=id;
  for(let level=3;level>=0;level--){
   if(typeof next!=='string'||!next||seen.has(next))throw fail('REGION_UNAVAILABLE',404);seen.add(next);
   const [base,derived]=await Promise.all([get(tables.regions,next),get(tables.derived,next)]);
   if(!base||!derived||Number(base.level)!==level||!enabled(base.is_active)||base.archived||!enabled(derived.effective_is_active))throw fail('REGION_UNAVAILABLE',404);
   path.unshift({base,derived});next=base.parent_id;
  }
  if(next&&!['ROOT','root'].includes(next))throw fail('REGION_UNAVAILABLE',404);
  if(!delivery(path[3].derived))throw fail('REGION_DELIVERY_UNAVAILABLE',404);
  return path;
 }
 async function scan(table){let rows=[],cursor;do{const r=await db.send(new sdk.ScanCommand({TableName:table,ConsistentRead:true,...(cursor?{ExclusiveStartKey:cursor}:{})}));rows.push(...r.Items||[]);cursor=r.LastEvaluatedKey;if(rows.length>20000)throw fail('REGION_CATALOG_TOO_LARGE');}while(cursor);return rows;}
 async function catalog(){
  const [base,derived]=await Promise.all([scan(tables.regions),scan(tables.derived)]),refs=new Map(base.map(r=>[r.regionId,r])),effects=new Map(derived.map(r=>[r.regionId,r])),visible=new Map();
  for(const leaf of base.filter(r=>Number(r.level)===3)){
   let current=leaf,chain=[],seen=new Set(),ok=delivery(effects.get(leaf.regionId));
   for(let level=3;level>=0;level--){if(!current||seen.has(current.regionId)||Number(current.level)!==level||!enabled(current.is_active)||current.archived||!enabled(effects.get(current.regionId)?.effective_is_active)){ok=false;break;}seen.add(current.regionId);chain.unshift(current);current=refs.get(current.parent_id);}
   if(!ok||chain.length!==4||(chain[0].parent_id&&!['ROOT','root'].includes(chain[0].parent_id)))continue;
   // Keep only Iraq's published root, identified by its ISO code or actual names.
   if(!['IQ','IRQ'].includes(String(chain[0].country_code||chain[0].code||'').toUpperCase())&&!/iraq|العراق/i.test([chain[0].name,chain[0].name_ar].join(' ')))continue;
   for(const r of chain){let bounds=null;if(Number(r.level)===3){const points=r.geometry?.coordinates?.flat(r.geometry.type==='MultiPolygon'?2:1);if(!points?.length||points.some(p=>!Array.isArray(p)||p.length<2||!p.every(Number.isFinite)))continue;bounds={south:Math.min(...points.map(p=>p[1])),north:Math.max(...points.map(p=>p[1])),west:Math.min(...points.map(p=>p[0])),east:Math.max(...points.map(p=>p[0]))};}visible.set(r.regionId,{id:r.regionId,labelAr:r.name_ar||r.name,labelEn:r.name||r.name_ar,level:Number(r.level),parentId:r.parent_id||null,...(bounds?{bounds}:{})});}
  }
  const items=[...visible.values()].filter(r=>r.level===3||[...visible.values()].some(c=>c.parentId===r.id)).sort((a,b)=>a.level-b.level||a.labelAr.localeCompare(b.labelAr,'ar'));
  return {schemaVersion:313,items};
 }
 async function resolve(latitude,longitude){
  if(typeof latitude!=='number'||typeof longitude!=='number'||!Number.isFinite(latitude)||!Number.isFinite(longitude)||Math.abs(latitude)>90||Math.abs(longitude)>180)throw fail('INVALID_LOCATION',400);
  const resolver=require('./region-coverage-runtime-312').createRegionResolver({db,sdk,tables});let coverage;try{coverage=await resolver({latitude,longitude});}catch(e){throw fail(e.code||'REGION_LOOKUP_UNAVAILABLE',e.code==='AMBIGUOUS_COVERAGE'?409:503);}if(!coverage)throw fail('REGION_NOT_FOUND',404);
  const path=await ancestry(coverage.regionId);return {coverage,path,regionId:coverage.regionId,regionNameAr:path[3].base.name_ar||path[3].base.name,regionNameEn:path[3].base.name||path[3].base.name_ar,city:path[1].base.name_ar||path[1].base.name};
 }
 function checks(path){return path.flatMap(({base,derived})=>[
  {ConditionCheck:{TableName:tables.regions,Key:{regionId:base.regionId},ConditionExpression:'#a=:a AND '+(base.version===undefined?'attribute_not_exists(#v)':'#v=:v'),ExpressionAttributeNames:{'#a':'is_active','#v':'version'},ExpressionAttributeValues:{':a':base.is_active,...(base.version===undefined?{}:{':v':base.version})}}},
  {ConditionCheck:{TableName:tables.derived,Key:{regionId:base.regionId},ConditionExpression:'#a=:a AND '+(derived.version===undefined?'attribute_not_exists(#v)':'#v=:v'),ExpressionAttributeNames:{'#a':'effective_is_active','#v':'version'},ExpressionAttributeValues:{':a':derived.effective_is_active,...(derived.version===undefined?{}:{':v':derived.version})}}}
 ]);}
 return {catalog,ancestry,resolve,checks};
}
function contains(geometry,latitude,longitude){
 const ring=(points)=>{let inside=false;for(let i=0,j=points.length-1;i<points.length;j=i++){
 const [x,y]=points[i],[a,b]=points[j];const cross=(longitude-x)*(b-y)-(latitude-y)*(a-x);
 if(Math.abs(cross)<1e-12&&longitude>=Math.min(x,a)&&longitude<=Math.max(x,a)&&latitude>=Math.min(y,b)&&latitude<=Math.max(y,b))return null;
 if((y>latitude)!==(b>latitude)&&longitude<(a-x)*(latitude-y)/(b-y)+x)inside=!inside;}return inside;};
 const polygons=geometry?.type==='Polygon'?[geometry.coordinates]:geometry?.type==='MultiPolygon'?geometry.coordinates:[];
 return polygons.some(p=>ring(p[0])===true&&p.slice(1).every(h=>ring(h)===false));
}
function bounds(geometry){const p=geometry.coordinates.flat(geometry.type==='MultiPolygon'?2:1);return {south:Math.min(...p.map(v=>v[1])),north:Math.max(...p.map(v=>v[1])),west:Math.min(...p.map(v=>v[0])),east:Math.max(...p.map(v=>v[0]))};}
module.exports={create,delivery,enabled,contains,bounds};
