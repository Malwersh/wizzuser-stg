// Shared discount validation/calculation engine for WizzUser backend.
// Ported from whizzMerchants-stg discount_management_handler.js so that
// customer-facing Lambdas evaluate WhizzMerchants_Discounts identically.
// All monetary inputs and outputs are in IQD fils (dinars x 1000).

// The table stores snake_case (valid_from, minimum_order_amount, ...);
// reading camelCase names directly would silently disable those checks.
function normalizeDiscount(d) {
    if (!d) return d;
    return {
        ...d,
        validFrom: d.validFrom || d.valid_from,
        validTo: d.validTo || d.valid_to,
        minimumOrderAmount: d.minimumOrderAmount ?? d.minimum_order_amount ?? 0,
        usageLimit: d.usageLimit ?? d.usage_limit ?? null,
        usageCount: d.usageCount ?? d.usage_count ?? 0,
        conditionalParameters: d.conditionalParameters || d.conditional_parameters || {},
    };
}

// Returns { valid: true } or { valid: false, message }
function validateDiscount(discount, orderTotalFils) {
    if (discount.status !== 'active') {
        return { valid: false, message: 'Discount is not active' };
    }

    const now = new Date();
    if (discount.validFrom && now < new Date(discount.validFrom)) {
        return { valid: false, message: 'Discount is not valid yet' };
    }
    if (discount.validTo && now > new Date(discount.validTo)) {
        return { valid: false, message: 'Discount has expired' };
    }

    const minOrderFils = Math.round((discount.minimumOrderAmount || 0) * 1000);
    if (orderTotalFils < minOrderFils) {
        return {
            valid: false,
            message: `Order must be at least ${discount.minimumOrderAmount} IQD`
        };
    }

    if (discount.usageLimit && discount.usageCount >= discount.usageLimit) {
        return { valid: false, message: 'Discount usage limit reached' };
    }

    return { valid: true };
}

// items: [{ id/itemId, categoryId, price (fils), quantity }]
function calculateDiscountAmount(discount, orderTotalFils, items, deliveryFeeFils) {
    let discountableAmount = 0;

    switch (discount.applicability) {
        case 'allItems':
            discountableAmount = orderTotalFils;
            break;
        case 'specificItems':
            discountableAmount = (items || [])
                .filter(item => (discount.applicable_item_ids || []).includes(item.itemId || item.id))
                .reduce((sum, item) => sum + (item.price * item.quantity), 0);
            break;
        case 'specificCategories':
            discountableAmount = (items || [])
                .filter(item => (discount.applicable_category_ids || []).includes(item.categoryId))
                .reduce((sum, item) => sum + (item.price * item.quantity), 0);
            break;
        case 'minimumOrder':
            discountableAmount = orderTotalFils;
            break;
        default:
            discountableAmount = orderTotalFils;
    }

    switch (discount.type) {
        case 'percentage':
            // Clamp: never discount more than the discountable amount
            return Math.min(discountableAmount * (discount.value / 100), discountableAmount);
        case 'fixedAmount':
            // value is stored in dinars by the merchant app
            return Math.min(Math.round(discount.value * 1000), discountableAmount);
        case 'buyXGetY':
        case 'conditional':
            return calculateBuyXGetYDiscount(discount, items);
        case 'freeDelivery':
            return Math.max(0, deliveryFeeFils || 0);
        default:
            return 0;
    }
}

function calculateBuyXGetYDiscount(discount, items) {
    const params = discount.conditionalParameters || {};
    const buyItemId = params.buyItemId;
    const buyQuantity = params.buyQuantity;
    const getItemId = params.getItemId;
    const getQuantity = params.getQuantity;

    if (!buyItemId || !buyQuantity || !getItemId || !getQuantity) {
        return 0;
    }

    const buyItem = (items || []).find(item => (item.itemId || item.id) === buyItemId);
    if (!buyItem || buyItem.quantity < buyQuantity) {
        return 0;
    }

    const getItem = (items || []).find(item => (item.itemId || item.id) === getItemId);
    if (!getItem) {
        return 0;
    }

    const setsEligible = Math.floor(buyItem.quantity / buyQuantity);
    const freeItems = Math.min(setsEligible * getQuantity, getItem.quantity);

    if (discount.value === 0) {
        return freeItems * getItem.price;
    }
    return freeItems * getItem.price * (discount.value / 100);
}

module.exports = {
    normalizeDiscount,
    validateDiscount,
    calculateDiscountAmount,
    calculateBuyXGetYDiscount,
};
