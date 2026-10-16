'use strict';
// Commercial terms and funding/ledger references are internal server data.
exports.customerOrderView = order => {
    if (!order || typeof order !== 'object') return order;
    const {financialSnapshot, commercialPricing, ...view} = order;
    return view;
};
