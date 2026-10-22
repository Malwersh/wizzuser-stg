'use strict';
// Commercial terms and funding/ledger references are internal server data.
exports.customerOrderView = order => {
    if (!order || typeof order !== 'object') return order;
    const {financeRollout, financialSnapshot, commercialPricing, financialAcceptance, codFinancialEvidence, financialSearch, merchantResponseActor, merchantResponsePolicy, driverSearchUnavailable, ...view} = order;
    if(view.deliveryQuote?.deliveryFundingPin){const {deliveryFundingPin,...publicQuote}=view.deliveryQuote;view.deliveryQuote=publicQuote;}
    return {...view, ...(financialSearch?.status==='no_driver_available' && order.dispatchStatus==='no_driver_available' && ['ready_for_pickup','ready','reassigning'].includes(order.status) && order.driverId==null && order.assignedDriverId==null && financialAcceptance==null ? {driverSearchUnavailable:true} : {})};
};
