String cancellationMessage(dynamic code, {dynamic fallback}) {
  const messages = {
    'AUTH_REQUIRED': 'سجّل الدخول مجدداً لإلغاء الطلب.',
    'CANCELLATION_NOT_AUTHORIZED': 'لا يمكنك إلغاء هذا الطلب من الحساب الحالي.',
    'ORDER_ALREADY_HANDLED': 'تغيرت حالة الطلب. حدّث تفاصيل الطلب أو تواصل مع الدعم.',
    'CANCELLATION_STATE_CHANGED': 'تغيرت حالة الطلب أثناء الإلغاء. حدّث الطلب ثم أعد المحاولة.',
    'INVALID_CANCELLATION_REASON': 'أدخل سبباً للإلغاء لا يتجاوز 500 حرف.',
    'FINANCIAL_ORDER_WORKFLOW_REQUIRED': 'تعذر إلغاء هذا الطلب من التطبيق حالياً. تواصل مع الدعم.',
    'MERCHANT_RESPONSE_FINANCIAL_REVIEW_REQUIRED': 'يتطلب إلغاء هذا الطلب مراجعة الدعم.',
    'OFFER_USAGE_REVIEW_REQUIRED': 'تعذر إكمال الإلغاء تلقائياً. تواصل مع الدعم.',
    'FINANCIAL_CANCELLATION_UNAVAILABLE': 'خدمة الإلغاء غير متاحة حالياً. أعد المحاولة.',
    'FINANCIAL_CANCELLATION_NOT_CONFIGURED': 'خدمة الإلغاء غير متاحة حالياً. تواصل مع الدعم.',
  };
  if (messages.containsKey(code)) return messages[code]!;
  if (fallback is String && fallback.isNotEmpty && !RegExp(r'^[A-Z0-9_]+$').hasMatch(fallback)) return fallback;
  return 'تعذر إلغاء الطلب. حدّث تفاصيل الطلب أو تواصل مع الدعم.';
}
