const {test}=require('node:test'),assert=require('node:assert/strict');const {storefrontFacts:f}=require('./storefront-facts-170');
test('missing stored fields never become invented ratings, review counts, preparation or fees',()=>assert.deepEqual(f({}),{minimumOrderAmountIqd:null,storefrontDeliveryAgreements:[],rating:null,reviewCount:null,averagePreparationMinutes:null,delivery_time:'',delivery_fee:''}));
test('real values and free delivery metadata preserve zero without magnitude guesses',()=>{const x=f({rating:4.8,reviewCount:12,orderReceptionSettings:{defaultPreparationMinutes:10},deliveryFee:0,deliveryTime:'15 دقيقة'});assert.equal(x.rating,4.8);assert.equal(x.reviewCount,12);assert.equal(x.averagePreparationMinutes,10);assert.equal(x.delivery_fee,'0');});
test('invalid or unverified values cannot impersonate stored facts',()=>{const x=f({rating:9,reviewCount:-1,orderReceptionSettings:{defaultPreparationMinutes:2},deliveryFee:{amount:5000}});assert.equal(x.rating,null);assert.equal(x.reviewCount,null);assert.equal(x.averagePreparationMinutes,null);assert.equal(x.delivery_fee,'');});

test('agreement public projection excludes commission and payer terms',()=>{
 const x=f({minimum_order:4000,storefrontDeliveryAgreements:[{id:'agreement',version:1,effectiveFrom:'2026-10-19T00:00:00.000Z',effectiveTo:'2026-11-19T00:00:00.000Z',regionIds:['zone'],deliveryFeeIqd:1500,minimumOrderAmountIqd:7000,commission:15,funding:{kind:'PLATFORM'}}]});
 assert.equal(x.minimumOrderAmountIqd,4000);assert.equal(x.storefrontDeliveryAgreements.length,1);assert.equal(x.storefrontDeliveryAgreements[0].commission,undefined);assert.equal(x.storefrontDeliveryAgreements[0].funding,undefined);
});

test('verified customer aggregate overrides stale legacy rating and count',()=>{const x=f({rating:4.9,reviewCount:500,customerRating:4,customerRatingCount:1});assert.equal(x.rating,4);assert.equal(x.reviewCount,1);});
test('empty or malformed customer aggregate never falls back to legacy stars',()=>{for(const value of [{customerRating:null,customerRatingCount:0},{customerRating:9,customerRatingCount:1},{customerRating:4,customerRatingCount:0}]){const x=f({...value,rating:4.9,reviewCount:500});assert.equal(x.rating,null);assert.equal(x.reviewCount,0);}});
