import '../widgets/basket_line_card.dart' show basketMoney;
import '../widgets/platform_benefits_sheet.dart';
import '../services/offer_checkout_failures.dart';
import '../services/storefront_pricing.dart';
import '../services/delivery_address_manager.dart';
import '../models/delivery_address.dart';
import '../widgets/storefront_value.dart';
// lib/screens/checkout_screen.dart
import '../constants/app_colors.dart';
import '../config/api_config.dart';
import '../services/delivery_quote_checkout.dart';
import '../widgets/commercial_confirmation_sheet.dart';
import '../widgets/driver_tip_selector.dart';
import 'dart:convert';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_model.dart';
import '../models/address_model.dart';
import '../models/store_discount.dart';
import '../providers/app_state_provider.dart';
import '../services/address_service.dart';
import '../services/session_service.dart';
import '../services/order_service.dart';
import '../services/pending_offer.dart';
import '../services/business_status_service.dart';
import 'order_tracking_screen.dart';
import 'address_selection_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final String? storeId;
  final String? storeName;

  const CheckoutScreen({super.key, this.storeId, this.storeName});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final OrderService _orderService = OrderService();
  late final DeliveryQuoteCheckout _quotedCheckout;
  StreamSubscription<DeliveryAddress?>? _activeAddressUpdates;
  bool get _quotesEnabled => ApiConfig.deliveryQuotesEnabled;
  String? _branchId(AppStateProvider state) =>
      widget.storeId ??
      (state.cartItems.isEmpty
          ? null
          : state.cartItems.first['store_id'] as String?);
  void _quoteChanged() {
    if (mounted) setState(() {
      final pendingTip = _quotedCheckout.pendingTipIqd;
      if (pendingTip != null) _driverTipIqd = pendingTip;
    });
  }

  Future<void> _syncActiveAddress() async {
    final a = _selectedAddress;
    if (a == null || a.latitude == null || a.longitude == null) return;
    final current = DeliveryAddressManager.instance.activeAddress;
    if (current?.addressId == a.id &&
        current?.latitude == a.latitude &&
        current?.longitude == a.longitude)
      return;
    await DeliveryAddressManager.instance.setActiveAddress(
      DeliveryAddress.fromJson({
        'addressId': a.id,
        'userId': a.userId,
        'formattedAddress': a.fullAddress,
        'latitude': a.latitude,
        'longitude': a.longitude,
        'label': a.name,
        'city': a.district,
        'regionId': a.regionId,
        'source': 'saved',
        'timestamp': a.updatedAt.toIso8601String(),
      }),
    );
  }

  Future<void> _loadQuote({bool renew = false}) async {
    if (!_quotesEnabled || !mounted || _selectedAddress == null) return;
    await SessionService.instance.getToken();
    if (!mounted) return;
    await _syncActiveAddress();
    final state = context.read<AppStateProvider>();
    final branch = _branchId(state);
    if (branch != null) {
      // Prepare the binding quote while the customer reviews the form. The final
      // review still checks expiry and the server prices the exact basket.
      await Future.wait([
        StorefrontPricing.instance.load(
          branch,
          state.cartItems,
          hasGoodsDiscount: _effectiveDiscount > 0,
          force: renew,
        ),
        _quotedCheckout.ensureFresh(branch, _selectedAddress!.id),
      ]);
    }
  }

  Future<void> _ensureQuoteFresh(String branch, String address) async {
    await SessionService.instance.getToken();
    await _quotedCheckout.ensureFresh(branch, address);
  }

  bool _quoteMatches(AppStateProvider state) =>
      _selectedAddress != null &&
      _branchId(state) != null &&
      _quotedCheckout.matches(_branchId(state)!, _selectedAddress!.id);

  double get _actualDeliveryFee =>
      _quotesEnabled ? (_quotedCheckout.quote?.fee ?? 0) : 10.0;
  String? _validatedDiscountContext;
  String? _pendingAttemptContext;
  bool _applyingPending=false;
  String? _autoItemContext,_autoItemId;
  bool _autoItemsEnabled=true;
  AppStateProvider? _cartListener;
  String _discountContext({bool includeTip = false}) {
    final state = context.read<AppStateProvider>();
    return jsonEncode([
      SessionService.instance.currentUserId,
      _branchId(state),
      state.cartItems,
      _selectedAddress?.id,
      _actualDeliveryFee,
      // Tips change final consent, but are not inputs to discount eligibility.
      if (includeTip) _driverTipIqd,
    ]);
  }
  bool get _discountCurrent => (_selectedDiscountId == null && _appliedPromoCode == null && _platformDiscountId == null && _deliveryBenefitId == null) ||
      (_validatedDiscountContext == _discountContext() && (!_quotesEnabled || _quoteMatches(context.read<AppStateProvider>())));
  double get _effectiveDiscount => _discountCurrent ? _discount : 0;
  DetailedAddress? _selectedAddress;
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  String _deliveryInstructions = '';
  int _driverTipIqd = 0;
  bool _isLoading = false;
  bool _preparingReview = false;

  // Merchant discounts
  List<StoreDiscount> _availableDiscounts = [];
  String? _selectedDiscountId;
  double _discount = 0.0;
  bool _isLoadingDiscounts = false;
  String? _discountLoadError;
  int _discountAttempt = 0;
  bool _isValidatingDiscount = false;

  // Platform promo code
  final TextEditingController _promoCodeController = TextEditingController();
  String? _appliedPromoCode;
  String? _platformDiscountId;
  String? _deliveryBenefitId;
  double _deliveryBenefitSaving = 0;
  double get _effectiveDeliveryBenefitSaving => _deliveryBenefitId != null && _discountCurrent ? _deliveryBenefitSaving : 0;
  List<dynamic> _discountLines=[];

  // Kept separately so a failed switch between discount types
  // restores the previously applied amount instead of wiping it
  double _promoDiscountAmount = 0.0;
  double _merchantDiscountAmount = 0.0;

  // User information for checkout
  bool _isGuestUser = false;
  String _guestName = '';
  String _guestPhone = '';
  String _guestEmail = '';

  // User login type detection
  bool _isLoggedInWithEmail = false;
  bool _isLoggedInWithPhone = false;
  String _userExistingEmail = '';
  String _userExistingPhone = '';

  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _guestNameController = TextEditingController();
  final TextEditingController _guestPhoneController = TextEditingController();
  final TextEditingController _guestEmailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    StorefrontPricing.instance.addListener(_quoteChanged);
    _quotedCheckout = DeliveryQuoteCheckout(
      account: () => SessionService.instance.currentUserId,
      token: () => SessionService.instance.accessToken,
    )..addListener(_quoteChanged);
    _activeAddressUpdates = DeliveryAddressManager.instance.addressStream
        .listen((address) {
          if (!mounted ||
              address == null ||
              _selectedAddress == null ||
              _quotedCheckout.pending)
            return;
          if (address.addressId == _selectedAddress!.id &&
              address.latitude == _selectedAddress!.latitude &&
              address.longitude == _selectedAddress!.longitude)
            return;
          _discountAttempt++;
          _quotedCheckout.invalidate();
          unawaited(_loadUserAddress());
        });
    if (_quotesEnabled) {
      _quotedCheckout.restore().then((_) {
        if (mounted) _loadQuote();
      });
    }
    // تأخير تهيئة البيانات لتحسين الأداء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cartListener=context.read<AppStateProvider>();
      _cartListener!.addListener(_pendingCartChanged);
      _initializeUserData().then((_)=>_autoApplyOffer());
      _loadStoreDiscounts();
      _clearLegacyPendingPromo();
    });
  }

  /// If the user tapped a promo code on the home-screen floating card,
  /// it is stored as pending — prefill and apply it automatically here.
  void _pendingCartChanged(){WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_autoApplyOffer();});}
  Future<void> _autoApplyOffer() async {
    if(!mounted||_isValidatingDiscount||_applyingPending||_selectedAddress==null)return;
    final pending=PendingOffer.current;if(pending==null){await _autoApplyItemOffer();return;}
    final state=context.read<AppStateProvider>();if((pending.merchantId.isNotEmpty&&pending.merchantId!=_branchId(state))||state.cartItems.isEmpty)return;
    if(_quotesEnabled&&!_quoteMatches(state))return;
    final key=_discountContext();if(_pendingAttemptContext==key)return;_pendingAttemptContext=key;_applyingPending=true;
    try{final offer=pending.offer;if(offer['source']=='merchant'){
      await _selectDiscount(StoreDiscount(discountId:offer['id'],businessId:pending.merchantId,title:offer['title']??'',description:offer['description']??'',type:offer['type']??'percentage',value:(offer['value'] as num?)?.toDouble()??0));
    }else {_promoCodeController.text=offer['code']??'';await _applyPromoCode();}
    }finally{_applyingPending=false;if(mounted){setState(()=>_isValidatingDiscount=false);if(key!=_discountContext())_pendingCartChanged();}}
  }
  Future<void> _autoApplyItemOffer() async {
    if(!mounted||!_autoItemsEnabled||_isValidatingDiscount||_applyingPending||_selectedAddress==null||_appliedPromoCode!=null||_platformDiscountId!=null||_deliveryBenefitId!=null)return;
    if(_selectedDiscountId!=null&&_selectedDiscountId!=_autoItemId)return;
    final state=context.read<AppStateProvider>(),branch=_branchId(context.read<AppStateProvider>());
    if(branch==null||state.cartItems.isEmpty||(_quotesEnabled&&!_quoteMatches(state)))return;
    final key=_discountContext();if(_autoItemContext==key)return;
    final candidates=_availableDiscounts.where((d)=>['specificItems','specificCategories'].contains(d.applicability)).toList();
    if(candidates.isEmpty)return;_autoItemContext=key;_applyingPending=true;setState(()=>_isValidatingDiscount=true);
    try {StoreDiscount? best;Map<String,dynamic>? bestPreview;double savings=0;
      for(var offset=0;offset<candidates.length;offset+=4){
        final group=candidates.skip(offset).take(4).toList();
        final results=await Future.wait(group.map((d)=>_orderService.validateDiscount(storeId:branch,discountId:d.discountId,orderTotal:state.cartTotal,items:List<Map<String,dynamic>>.from(state.cartItems),deliveryFee:_actualDeliveryFee,addressId:_selectedAddress!.id)));
        if(!mounted||key!=_discountContext())return;
        for(var i=0;i<results.length;i++){final amount=(results[i]['discount'] as num?)?.toDouble()??0;if(results[i]['valid']==true&&amount>savings){best=group[i];bestPreview=Map<String,dynamic>.from(results[i]);savings=amount;}}
      }
      if(best!=null){_autoItemId=best.discountId;await _selectDiscount(best, preview: bestPreview, previewContext: key);}
      else if(_selectedDiscountId==_autoItemId){await _selectDiscount(null);}
    }finally{_applyingPending=false;if(mounted){setState(()=>_isValidatingDiscount=false);if(key!=_discountContext())_pendingCartChanged();}}
  }
  Future<void> _clearLegacyPendingPromo() async {
    // Unscoped legacy selections cannot safely be attached to the current account.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_promo_code');
  }

  Future<void> _loadStoreDiscounts() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final storeId =
        widget.storeId ??
        (appState.cartItems.isNotEmpty
            ? appState.cartItems.first['store_id']
            : null);
    if (storeId == null || storeId.toString().isEmpty) return;

    setState(() {
      _isLoadingDiscounts = true;
      _availableDiscounts = [];
      _discountLoadError = null;
    });

    final scope = [SessionService.instance.currentUserId, storeId.toString(), _selectedAddress?.id];
    try {
      final discounts = await _orderService.getStoreDiscounts(storeId.toString(), addressId:_selectedAddress?.id);
      if (!mounted || scope[0] != SessionService.instance.currentUserId || scope[1] != _branchId(context.read<AppStateProvider>()) || scope[2] != _selectedAddress?.id) return;
      setState(() { _availableDiscounts = discounts; _isLoadingDiscounts = false; _discountLoadError = null; });
      await _autoApplyOffer();
    } catch (_) {
      if (!mounted || scope[0] != SessionService.instance.currentUserId || scope[1] != _branchId(context.read<AppStateProvider>()) || scope[2] != _selectedAddress?.id) return;
      setState(() { _availableDiscounts = []; _isLoadingDiscounts = false; _discountLoadError = 'تعذر تحميل العروض'; });
    }
  }

  Future<void> _applyPromoCode() async {
    final code = _promoCodeController.text.trim();
    if(!_applyingPending&&PendingOffer.current?.offer['code']!=code)PendingOffer.clear();
    final selectedPlatformId=_applyingPending?PendingOffer.current?.offer['id'] as String?:null;
    if (code.isEmpty&&selectedPlatformId==null) {
      _showMessage('أدخل كود الخصم أولاً', isError: true);
      return;
    }

    final appState = Provider.of<AppStateProvider>(context, listen: false);

    setState(() {
      _isValidatingDiscount = true;
    });

    if (_quotesEnabled &&
        !_quotedCheckout.pending &&
        _selectedAddress != null) {
      final branch = _branchId(appState);
      if (branch != null) await _ensureQuoteFresh(branch, _selectedAddress!.id);
      if (!mounted) return;
    }
    if (_quotedCheckout.pending ||
        (_quotesEnabled && !_quoteMatches(appState))) {
      setState(() {
        _isValidatingDiscount = false;
      });
      _showMessage(
        _quotedCheckout.pending
            ? 'تابع محاولة تأكيد الطلب السابقة أولًا'
            : 'تعذر التحقق من الخصم؛ تحقق من الاتصال وأعد المحاولة',
        isError: true,
      );
      return;
    }
    final attempt = ++_discountAttempt;
    final validationContext = _discountContext();
    var result = await _orderService.validatePromoCode(
      code: code,
      platformDiscountId:selectedPlatformId,
      deliveryBenefitId:_deliveryBenefitId,
      existingPlatformDiscountId:_platformDiscountId,
      existingDiscountId:_selectedDiscountId,
      existingPromoCode:_platformDiscountId==null ? _appliedPromoCode : null,
      storeId: _branchId(appState) ?? '',
      items: appState.cartItems,
      orderTotal: appState.cartTotal,
      deliveryFee: _actualDeliveryFee,
      addressId:_selectedAddress?.id,
    );

    if (!mounted || attempt != _discountAttempt) return;
    if (validationContext != _discountContext()) {
      setState(() {
        _isValidatingDiscount = false;
      });
      return;
    }
    Map<String,dynamic>? companion;
    if(result['valid']==true&&result['deliveryBenefit']==true&&_platformDiscountId!=null){
      companion=await _orderService.validatePromoCode(code:_appliedPromoCode??'',platformDiscountId:_platformDiscountId,deliveryBenefitId:selectedPlatformId,storeId:_branchId(appState)??'',items:appState.cartItems,orderTotal:appState.cartTotal,deliveryFee:_actualDeliveryFee,addressId:_selectedAddress?.id);
    }else if(result['valid']==true&&result['deliveryBenefit']!=true&&_deliveryBenefitId!=null){
      companion=await _orderService.validatePromoCode(code:'',platformDiscountId:_deliveryBenefitId,existingPlatformDiscountId:selectedPlatformId,storeId:_branchId(appState)??'',items:appState.cartItems,orderTotal:appState.cartTotal,deliveryFee:_actualDeliveryFee,addressId:_selectedAddress?.id);
    }
    if(!mounted||attempt!=_discountAttempt)return;
    if(validationContext!=_discountContext()){setState(()=>_isValidatingDiscount=false);return;}
    if(companion!=null&&companion['valid']!=true)result=companion;
    setState(() {
      _isValidatingDiscount = false;
      if (result['valid'] == true) {
        _validatedDiscountContext = validationContext;
        if(result['deliveryBenefit']==true){
          _deliveryBenefitId=selectedPlatformId;
          _deliveryBenefitSaving=(result['deliveryBenefitSavingAmount'] as num?)?.toDouble()??0;
          if(companion!=null){_discountLines=companion['lines'] as List? ?? [];_promoDiscountAmount=(companion['discount'] as num?)?.toDouble()??0;_discount=_promoDiscountAmount;}
        }else{
          _discountLines=result['lines'] as List? ?? [];
          _appliedPromoCode=code.isEmpty?null:code;
          _platformDiscountId=selectedPlatformId;
          _promoDiscountAmount=(result['discount'] as num?)?.toDouble()??0;
          _discount=_promoDiscountAmount;
          _selectedDiscountId=null;
          _merchantDiscountAmount=0;
          if(companion!=null)_deliveryBenefitSaving=(companion['deliveryBenefitSavingAmount'] as num?)?.toDouble()??0;
        }
      } else if (_appliedPromoCode != null) {
        _promoCodeController.text = _appliedPromoCode!;
      }
    });

    if (result['valid'] == true) {
      _showMessage(result['deliveryBenefit']==true?'تم اختيار ميزة التوصيل؛ ستُراجع الرسوم قبل التأكيد':'تم تطبيق كود الخصم بنجاح');
    } else {
      _showMessage(result['message'] ?? 'كود الخصم غير صالح', isError: true);
    }
  }

  void _clearPromoCode() {
    PendingOffer.clear();
    _discountAttempt++;
    setState(() {
      _isValidatingDiscount = false;
      _appliedPromoCode = null;
      _platformDiscountId=null;
      _deliveryBenefitId=null;
      _deliveryBenefitSaving=0;
      _promoCodeController.clear();
      _promoDiscountAmount = 0.0;
      _discount = _merchantDiscountAmount;
    });
  }

  Future<void> _selectDiscount(StoreDiscount? discount, {Map<String,dynamic>? preview, String? previewContext}) async {
    if(!_applyingPending){PendingOffer.clear();_autoItemsEnabled=false;}
    if (discount == null) {
      _discountAttempt++;
      setState(() {
        _isValidatingDiscount = false;
        _selectedDiscountId = null;
        _merchantDiscountAmount = 0.0;
        _discount = _promoDiscountAmount;
      });
      return;
    }

    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final storeId =
        widget.storeId ??
        (appState.cartItems.isNotEmpty
            ? appState.cartItems.first['store_id']
            : null);
    if (storeId == null) return;

    setState(() {
      _isValidatingDiscount = true;
    });

    if (_quotesEnabled &&
        !_quotedCheckout.pending &&
        _selectedAddress != null) {
      final branch = _branchId(appState);
      if (branch != null) await _ensureQuoteFresh(branch, _selectedAddress!.id);
      if (!mounted) return;
    }
    if (_quotedCheckout.pending ||
        (_quotesEnabled && !_quoteMatches(appState))) {
      setState(() {
        _isValidatingDiscount = false;
      });
      _showMessage(
        _quotedCheckout.pending
            ? 'تابع محاولة تأكيد الطلب السابقة أولًا'
            : 'تعذر التحقق من الخصم؛ تحقق من الاتصال وأعد المحاولة',
        isError: true,
      );
      return;
    }
    final attempt = ++_discountAttempt;
    final validationContext = _discountContext();
    final result = preview != null && previewContext == validationContext ? preview : await _orderService.validateDiscount(
      storeId: storeId.toString(),
      discountId: discount.discountId,
      orderTotal: appState.cartTotal,
      deliveryFee: _actualDeliveryFee,
      addressId:_selectedAddress?.id,
      items: appState.cartItems,
    );

    if (!mounted || attempt != _discountAttempt) return;
    if (validationContext != _discountContext()) {
      setState(() {
        _isValidatingDiscount = false;
      });
      return;
    }
    setState(() {
      _isValidatingDiscount = false;
      if (result['valid'] == true) {
        _validatedDiscountContext = validationContext;
        _discountLines=result['lines'] as List? ?? [];
        _selectedDiscountId = discount.discountId;
        _merchantDiscountAmount =
            (result['discount'] as num?)?.toDouble() ?? 0.0;
        _discount = _merchantDiscountAmount;
        // Only one discount per order: clear any applied promo code
        _appliedPromoCode = null;
      _platformDiscountId=null;
      _deliveryBenefitId=null;
      _deliveryBenefitSaving=0;
        _promoDiscountAmount = 0.0;
        _promoCodeController.clear();
      }
      // A failed switch leaves the previous validated selection intact.
    });

    if (result['valid'] == true) {
      _showMessage('تم تطبيق الخصم بنجاح');
    } else {
      _showMessage(result['message'] ?? 'الخصم غير صالح', isError: true);
    }
  }

  @override
  void didUpdateWidget(covariant CheckoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId) {
      _discountAttempt++;
      _selectedDiscountId = null;
      _platformDiscountId = null;
      _deliveryBenefitId=null;
      _deliveryBenefitSaving=0;
      _discountLines = [];
      _appliedPromoCode = null;
      _discount = 0;
      _merchantDiscountAmount = 0;
      _promoDiscountAmount = 0;
      _validatedDiscountContext = null;
      _isValidatingDiscount = false;
      _loadStoreDiscounts();
    }
  }

  @override
  void dispose() {
    _cartListener?.removeListener(_pendingCartChanged);
    _activeAddressUpdates?.cancel();
    StorefrontPricing.instance.removeListener(_quoteChanged);
    _quotedCheckout.removeListener(_quoteChanged);
    _quotedCheckout.dispose();
    _instructionsController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _guestEmailController.dispose();
    _promoCodeController.dispose();
    super.dispose();
  }

  Future<void> _initializeUserData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Check if user is logged in
      final sessionService = SessionService.instance;

      if (sessionService.isLoggedIn && sessionService.currentUser != null) {
        // Logged in user - determine login method and load their info
        _isGuestUser = false;
        final currentUser = sessionService.currentUser!;

        // Detect login method based on user data
        final userEmail =
            currentUser['email'] ?? currentUser['userEmail'] ?? '';
        final userPhone =
            currentUser['phone'] ?? currentUser['userPhone'] ?? '';

        if (userEmail.isNotEmpty && userPhone.isNotEmpty) {
          // User has both - need to determine primary login method
          // For now, assume email is primary if it exists
          _isLoggedInWithEmail = true;
          _userExistingEmail = userEmail;
          _guestEmailController.text = userEmail;
        } else if (userEmail.isNotEmpty) {
          // Logged in with email
          _isLoggedInWithEmail = true;
          _userExistingEmail = userEmail;
          _guestEmailController.text = userEmail;
        } else if (userPhone.isNotEmpty) {
          // Logged in with phone
          _isLoggedInWithPhone = true;
          _userExistingPhone = userPhone;
          _guestPhoneController.text = userPhone;
        }

        // Set user name if available
        final userName = currentUser['name'] ?? currentUser['userName'] ?? '';
        if (userName.isNotEmpty) {
          _guestNameController.text = userName;
          _guestName = userName;
        }

        // Load user address asynchronously without blocking UI
        _loadUserAddress();
      } else {
        // Guest user - need to collect information manually
        _isGuestUser = true;
      }
    } catch (e) {
      debugPrint('خطأ في تهيئة بيانات المستخدم: $e');
      _isGuestUser = true;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserAddress() async {
    try {
      final addressService = Provider.of<EnhancedAddressService>(
        context,
        listen: false,
      );

      // تحميل العناوين بشكل غير متزامن لعدم حجب واجهة المستخدم
      await addressService.fetchAddresses();

      if (mounted && addressService.detailedAddresses.isNotEmpty) {
        setState(() {
          final activeId =
              DeliveryAddressManager.instance.activeAddress?.addressId;
          final matches = addressService.detailedAddresses.where(
            (a) => a.id == activeId,
          );
          _selectedAddress =
              matches.isNotEmpty
                  ? matches.first
                  : addressService.defaultAddress ??
                      addressService.detailedAddresses.first;
        });
        await _loadQuote();
        await _loadStoreDiscounts();
        await _autoApplyOffer();
      }
    } catch (e) {
      debugPrint('خطأ في تحميل العنوان: $e');
      // If no saved addresses, the user will need to add one
      // لا نحتاج لعرض خطأ للمستخدم هنا، فقط سيضطر لإضافة عنوان جديد
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'إتمام الطلب',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: CheckoutLoadingBody(
        busy: _isLoading || _preparingReview,
        progress: _buildLoadingWidget(),
        child: Consumer<AppStateProvider>(
                builder: (context, appState, child) {
                  if (appState.cartItems.isEmpty) {
                    return const Center(child: Text('السلة فارغة'));
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          physics:
                              const ClampingScrollPhysics(), // تحسين الأداء
                          padding: const EdgeInsets.all(16),
                          child: Form(
                            // إضافة Form widget
                            key: _formKey,
                            child: RepaintBoundary(
                              // تجنب إعادة رسم غير ضرورية
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // قسم معلومات الطلب - مع تحسين الأداء
                                  RepaintBoundary(
                                    child: _buildOrderSummary(appState),
                                  ),
                                  const SizedBox(height: 16),

                                  // قسم معلومات المستخدم - مع تحسين الأداء
                                  RepaintBoundary(
                                    child:
                                        _isGuestUser
                                            ? _buildGuestInfoSection()
                                            : _buildLoggedInUserInfoSection(),
                                  ),
                                  const SizedBox(height: 16),

                                  // قسم العنوان
                                  RepaintBoundary(
                                    child: _buildAddressSection(),
                                  ),
                                  const SizedBox(height: 16),

                                  // قسم طريقة الدفع
                                  RepaintBoundary(
                                    child: _buildPaymentSection(),
                                  ),
                                  const SizedBox(height: 16),

                                  // قسم العروض والخصومات
                                  RepaintBoundary(
                                    child: _buildDiscountsSection(),
                                  ),
                                  const SizedBox(height: 16),

                                  if (ApiConfig.commercialPricingEnabled) ...[
                                    DriverTipSelector(
                                      amountIqd: _driverTipIqd,
                                      enabled:
                                          !_isLoading &&
                                          !_preparingReview &&
                                          !_quotedCheckout.pending,
                                      onChanged:
                                          (amount) => setState(
                                            () => _driverTipIqd = amount,
                                          ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  // قسم تعليمات التوصيل
                                  RepaintBoundary(
                                    child: _buildInstructionsSection(),
                                  ),
                                  const SizedBox(height: 16),

                                  // ملخص السعر
                                  RepaintBoundary(
                                    child: Column(
                                      children: [
                                        if (_quotesEnabled)
                                          _buildQuoteStatus(appState),
                                        _buildPriceSummary(appState),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 100,
                                  ), // مساحة للزر السفلي
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // زر تأكيد الطلب
                      _buildConfirmButton(appState),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'جاري التحميل...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(AppStateProvider appState) {
    final itemCount = appState.cartItems.length;
    final totalQuantity = appState.cartItems.fold<int>(
      0,
      (sum, item) => sum + (item['quantity'] as int? ?? 1),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shopping_bag,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.storeName ?? 'المطعم',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '$itemCount أطباق ($totalQuantity قطعة)',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'عنوان التوصيل',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              if (_selectedAddress != null)
                TextButton(
                  onPressed: _selectAddress,
                  child: const Text(
                    'تغيير',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Show selected address if available
          if (_selectedAddress != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _selectedAddress!.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      if (_selectedAddress!.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'افتراضي',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // عرض العنوان الكامل للضيوف أو الأجزاء المنفصلة للمستخدمين المسجلين
                    _selectedAddress!.fullAddress.isNotEmpty &&
                            (_selectedAddress!.province.isEmpty ||
                                _selectedAddress!.district.isEmpty ||
                                _selectedAddress!.neighborhood.isEmpty)
                        ? _selectedAddress!.fullAddress
                        : '${_selectedAddress!.province} - ${_selectedAddress!.district} - ${_selectedAddress!.neighborhood}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  if (_selectedAddress!.detailedAddress?.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 4),
                    Text(
                      _selectedAddress!.detailedAddress ?? '',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                  if (_selectedAddress!.landmark.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'قرب ${_selectedAddress!.landmark}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            )
          else
            // No address selected - show appropriate action
            _buildNoAddressWidget(),
        ],
      ),
    );
  }

  Widget _buildNoAddressWidget() {
    if (_isGuestUser) {
      // Guest user - needs to add address manually
      return GestureDetector(
        onTap: _addNewAddress,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.add_location_alt,
                color: AppColors.primary,
                size: 32,
              ),
              const SizedBox(height: 8),
              const Text(
                'أضف عنوان التوصيل',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'يرجى إضافة عنوانك لإتمام الطلب',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    } else {
      // Logged in user with no saved addresses
      return GestureDetector(
        onTap: _selectAddress,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.add_location_alt,
                color: AppColors.primary,
                size: 32,
              ),
              const SizedBox(height: 8),
              const Text(
                'اختر أو أضف عنوان',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'اختر من عناوينك المحفوظة أو أضف عنوان جديد',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildPaymentSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.payment,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'طريقة الدفع',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children:
                PaymentMethod.values.map((method) {
                  return RadioListTile<PaymentMethod>(
                    value: method,
                    groupValue: _selectedPaymentMethod,
                    onChanged:
                        method.isEnabled
                            ? (value) {
                              setState(() {
                                _selectedPaymentMethod = value!;
                              });
                            }
                            : null,
                    title: Row(
                      children: [
                        Text(
                          method.arabicName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color:
                                method.isEnabled ? Colors.black87 : Colors.grey,
                          ),
                        ),
                        if (!method.isEnabled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Text(
                              'قريباً',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountsSection() {
    if (_discountLoadError != null)
      return Column(
        children: [
          Text(_discountLoadError!),
          TextButton(
            onPressed: _loadStoreDiscounts,
            child: const Text('إعادة تحميل العروض'),
          ),
        ],
      );
    if (_isLoadingDiscounts) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(onPressed:()async{final selected=await showPlatformBenefitsSheet(context,branchId:_branchId(context.read<AppStateProvider>()));if(selected==true&&mounted){_pendingAttemptContext=null;await _autoApplyOffer();}},icon:const Icon(Icons.card_giftcard),label:const Text('مزايا المنصة')),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_offer,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'العروض والخصومات',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (_isValidatingDiscount) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Promo code entry (platform codes from the central platform)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoCodeController,
                  enabled: _appliedPromoCode == null && !_isValidatingDiscount,
                  decoration: InputDecoration(
                    hintText: 'أدخل كود الخصم',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isValidatingDiscount
                    ? null
                    : (_appliedPromoCode != null || _platformDiscountId != null || _deliveryBenefitId != null ? _clearPromoCode : _applyPromoCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(_appliedPromoCode != null || _platformDiscountId != null || _deliveryBenefitId != null ? 'إزالة' : 'تطبيق'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._availableDiscounts.where((d)=>!['specificItems','specificCategories'].contains(d.applicability)).map((discount) {
            return RadioListTile<String>(
              value: discount.discountId,
              groupValue: _selectedDiscountId,
              onChanged:
                  _isValidatingDiscount
                      ? null
                      : (_) => _selectDiscount(discount),
              title: Text(
                discount.title.isNotEmpty
                    ? discount.title
                    : discount.displayValue,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              subtitle: Text(
                [discount.displayValue, discount.description, discount.termsSummary]
                    .where((text) => text.isNotEmpty).join('\n'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            );
          }),
          if (_selectedDiscountId != null) ...[
            TextButton(
              onPressed:
                  _isValidatingDiscount ? null : () => _selectDiscount(null),
              child: const Text(
                'إزالة الخصم',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ],
          if (!_discountCurrent)
            const Text('أعد اختيار الخصم بعد تغيير السلة أو سعر التوصيل'),
          if (_effectiveDiscount > 0) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'تم تطبيق خصم ${_effectiveDiscount.toStringAsFixed(3)} د.ع',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.note_add,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'تعليمات التوصيل',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructionsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'أي تعليمات خاصة للسائق؟ (اختياري)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (value) {
              _deliveryInstructions = value;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteStatus(AppStateProvider appState) {
    if (!_quotedCheckout.pending &&
        (_quotedCheckout.error == null || _quotedCheckout.valid)) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              _quotedCheckout.pending
                  ? 'توجد محاولة تأكيد سابقة. تابعها لاستعادة نتيجتها قبل بدء طلب آخر.'
                  : (_quotedCheckout.error ?? 'تعذر تحميل سعر التوصيل؛ أعد المحاولة'),
            ),
            if (!_quotedCheckout.pending)
              TextButton(
                onPressed:
                    _quotedCheckout.busy || _isLoading
                        ? null
                        : () => _loadQuote(renew: true),
                child: const Text('إعادة المحاولة'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSummary(AppStateProvider appState) {
    final subtotal = appState.cartTotal;
    final normalDeliveryFee = _quotesEnabled ? (StorefrontPricing.instance.feeIqd(_branchId(appState)??'',appState.cartItems,hasGoodsDiscount:_effectiveDiscount>0) ?? 0) : 10.0;
    final deliveryFee = (normalDeliveryFee - _effectiveDeliveryBenefitSaving).clamp(0.0,normalDeliveryFee);
    final discount = _effectiveDiscount;
    final total = subtotal + deliveryFee + _driverTipIqd - discount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'ملخص الفاتورة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المجموع الفرعي'),
              Text(basketMoney(subtotal)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('رسوم التوصيل'),
              if(_effectiveDeliveryBenefitSaving>0) Text('${deliveryFee.toStringAsFixed(0)} د.ع') else StorefrontValue(branchId:_branchId(appState)??'',field:StorefrontField.fee,items:appState.cartItems,hasGoodsDiscount:discount>0),
            ],
          ),
          if (_driverTipIqd > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('إكرامية السائق'),
                Text(basketMoney(_driverTipIqd)),
              ],
            ),
          ],
          if (discount > 0) ...[
            for(final line in _discountLines)Text('${appState.cartItems.where((i)=>i['id']==line['itemId']).map((i)=>i['name']).firstOrNull??'منتج'}: توفير ${((line['savingsFils'] as num)/1000).toStringAsFixed(3)} د.ع',style:const TextStyle(color:Colors.green)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الخصم', style: TextStyle(color: Colors.green)),
                Text(
                  '-${basketMoney(discount)}',
                  style: const TextStyle(color: Colors.green),
                ),
              ],
            ),
          ],
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ApiConfig.commercialPricingEnabled
                    ? 'المجموع قبل رسوم الخدمة'
                    : 'المجموع الكلي',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _quotesEnabled && StorefrontPricing.instance.feeIqd(_branchId(appState)??'',appState.cartItems,hasGoodsDiscount:_effectiveDiscount>0)==null
                    ? '—'
                    : basketMoney(total),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton(AppStateProvider appState) {
    final subtotal = appState.cartTotal;
    final deliveryFee =
        ((_quotesEnabled ? (_quotedCheckout.quote?.fee ?? 0) : 10.0) - _effectiveDeliveryBenefitSaving).clamp(0.0,double.infinity);
    final discount = _effectiveDiscount;
    final total = subtotal + deliveryFee + _driverTipIqd - discount;
    final bool pending = _quotesEnabled && _quotedCheckout.pending;
    final bool canConfirm =
        !_isValidatingDiscount &&
        (pending || _discountCurrent) &&
        !_isLoading &&
        !_preparingReview &&
        (pending || _selectedAddress != null);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canConfirm ? () => _confirmOrder(appState) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  canConfirm ? AppColors.primary : Colors.grey[400],
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: canConfirm ? 2 : 0,
            ),
            child:
                _isLoading
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : Text(
                      pending
                          ? 'متابعة تأكيد الطلب السابق'
                          : ApiConfig.commercialPricingEnabled
                          ? 'مراجعة إجمالي الطلب'
                          : 'تأكيد الطلب • ${total.toStringAsFixed(3)} د.ع',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  // Guest user information section
  Widget _buildGuestInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'معلوماتك الشخصية',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Name field
          TextFormField(
            controller: _guestNameController,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: 'الاسم الكامل *',
              hintText: 'ادخل اسمك الكامل',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              _guestName = value; // إزالة setState لتحسين الأداء
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'يرجى إدخال الاسم الكامل';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Phone field
          TextFormField(
            controller: _guestPhoneController,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'رقم الهاتف *',
              hintText: '+964XXXXXXXXX',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              _guestPhone = value; // إزالة setState لتحسين الأداء
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'يرجى إدخال رقم الهاتف';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Email field (optional)
          TextFormField(
            controller: _guestEmailController,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'البريد الإلكتروني (اختياري)',
              hintText: 'example@email.com',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) {
              _guestEmail = value; // إزالة setState لتحسين الأداء
            },
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                if (!RegExp(
                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                ).hasMatch(value)) {
                  return 'البريد الإلكتروني غير صحيح';
                }
              }
              return null;
            },
          ),

          const SizedBox(height: 12),

          // Login suggestion
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'لتجربة أفضل',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'سجل دخولك لحفظ معلوماتك وعناوينك',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to login screen
                    if (!mounted) return;
                    Navigator.pushNamed(context, '/login');
                  },
                  child: const Text(
                    'تسجيل دخول',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Logged in user information section
  Widget _buildLoggedInUserInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.verified_user,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'معلومات الاتصال',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'مسجل دخول',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Name field (always shown for logged in users)
          TextField(
            controller: _guestNameController,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: 'الاسم الكامل',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              filled: true,
              fillColor: Colors.grey.withValues(alpha: 0.05),
            ),
            readOnly: true,
            onChanged: (value) {
              setState(() {
                _guestName = value;
              });
            },
          ),
          const SizedBox(height: 12),

          // Show appropriate fields based on login method
          if (_isLoggedInWithEmail) ...[
            // User logged in with email - show email (readonly) and phone (required)
            TextField(
              controller: _guestEmailController,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'البريد الإلكتروني',
                prefixIcon: const Icon(Icons.email_outlined),
                suffixIcon: const Icon(
                  Icons.verified,
                  color: Colors.green,
                  size: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.05),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 12),

            // Phone field (required)
            TextField(
              controller: _guestPhoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف *',
                hintText: '+964XXXXXXXXX',
                prefixIcon: const Icon(Icons.phone_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _guestPhone = value;
                });
              },
            ),
          ] else if (_isLoggedInWithPhone) ...[
            // User logged in with phone - show phone (readonly) and email (optional)
            TextField(
              controller: _guestPhoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف',
                prefixIcon: const Icon(Icons.phone_outlined),
                suffixIcon: const Icon(
                  Icons.verified,
                  color: Colors.green,
                  size: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.05),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 12),

            // Email field (optional)
            TextField(
              controller: _guestEmailController,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'البريد الإلكتروني (اختياري)',
                hintText: 'example@email.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _guestEmail = value;
                });
              },
            ),
          ],

          const SizedBox(height: 12),

          // Info message
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تم التحقق من هويتك',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        _isLoggedInWithEmail
                            ? 'تسجيل الدخول بالبريد الإلكتروني - يرجى إضافة رقم الهاتف'
                            : 'تسجيل الدخول برقم الهاتف - يمكنك إضافة البريد الإلكتروني (اختياري)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectAddress() async {
    if (_isGuestUser) {
      // For guest users, go directly to add new address
      _addNewAddress();
      return;
    }

    final selectedAddress = await Navigator.push<DetailedAddress>(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                AddressSelectionScreen(currentAddress: _selectedAddress),
      ),
    );

    if (selectedAddress != null) {
      setState(() {
        _selectedAddress = selectedAddress;
      });
      if (_quotesEnabled) _quotedCheckout.invalidate();
      await _loadQuote();
      await _loadStoreDiscounts();
      await _autoApplyOffer();
    }
  }

  void _addNewAddress() {
    // Navigate to address form screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('سيتم فتح نموذج إضافة عنوان جديد'),
        backgroundColor: AppColors.primary,
      ),
    );

    // TODO: Navigate to address form screen
    // For now, create a simple address form dialog
    _showAddAddressDialog();
  }

  void _showAddAddressDialog() {
    final addressController = TextEditingController();
    final landmarkController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('أضف عنوان التوصيل'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: addressController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'العنوان الكامل *',
                        hintText:
                            'اكتب عنوانك كما تريد: مثل شارع فلسطين، الكرخ، بغداد أو أي طريقة تفضلها',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: landmarkController,
                      decoration: const InputDecoration(
                        labelText: 'أقرب نقطة دليلية (اختياري)',
                        hintText:
                            'مثل: قرب مطعم الصادق، بجانب الصيدلية، أمام المدرسة',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.place),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ملاحظة: يمكنك كتابة العنوان بأي طريقة تريدها، لا حاجة لتقسيمه إلى أجزاء',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final fullAddress = addressController.text.trim();
                    final landmark = landmarkController.text.trim();

                    if (fullAddress.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('يرجى إدخال العنوان الكامل'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // إنشاء عنوان مؤقت للضيف بصيغة مبسطة
                    final guestAddress = DetailedAddress(
                      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
                      userId: 'guest',
                      name: 'عنوان الضيف',
                      province: '', // لا نحتاج تقسيم العنوان
                      district: '',
                      neighborhood: '',
                      landmark: landmark.isNotEmpty ? landmark : '',
                      fullAddress:
                          fullAddress, // نحفظ العنوان كما أدخله المستخدم
                      addressType: AddressType.other,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );

                    setState(() {
                      _selectedAddress = guestAddress;
                    });

                    Navigator.of(context).pop();

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حفظ العنوان بنجاح'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _confirmOrder(AppStateProvider appState) async {
    if (_isLoading || _preparingReview) return;
    setState(() => _preparingReview = true);
    try {
      if (_quotesEnabled && _quotedCheckout.pending) {
        await _resumeQuotedOrder();
        return;
      }
      final businessStatusFuture = widget.storeId == null
          ? Future<Map<String, dynamic>?>.value(null)
          : BusinessStatusService.getBusinessStatus(widget.storeId!);
      if (_quotesEnabled && _selectedAddress != null) {
        if (!mounted) return;
        final branch = _branchId(appState);
        if (branch != null) {
          setState(() {
            _isLoading = true;
          });
          try {
            await _ensureQuoteFresh(branch, _selectedAddress!.id);
          } finally {
            if (mounted)
              setState(() {
                _isLoading = false;
              });
          }
        }
        if (!mounted) return;
        if (!_quoteMatches(appState)) {
          _showMessage(
            _quotedCheckout.error ?? 'تعذر مراجعة إجمالي الطلب؛ أعد المحاولة',
            isError: true,
          );
          return;
        }
      }
      if (!_discountCurrent) {
        _showMessage(
          'تغير مبلغ التوصيل؛ أعد التحقق من الخصم ثم راجع الإجمالي',
          isError: true,
        );
        return;
      }
      // التحقق من صحة النموذج أولاً
      if (_formKey.currentState?.validate() != true) {
        _showMessage(
          'يرجى تعبئة جميع الحقول المطلوبة بشكل صحيح',
          isError: true,
        );
        return;
      }

      // فحص حالة المطعم أولاً
      if (widget.storeId != null) {
        final businessStatusData = await businessStatusFuture;

        if (businessStatusData != null) {
          final canAcceptOrders =
              businessStatusData['isOpen'] as bool? ?? false;
          final statusMessage = businessStatusData['message'] as String? ?? '';

          if (!canAcceptOrders) {
            _showMessage(
              statusMessage.isNotEmpty
                  ? statusMessage
                  : 'المطعم غير متاح حالياً لاستقبال الطلبات',
              isError: true,
            );
            return;
          }
        }
      }

      // التحقق من العنوان
      if (_selectedAddress == null) {
        _showMessage('يرجى اختيار عنوان التوصيل', isError: true);
        return;
      }

      // التحقق البسيط من العنوان فقط
      if (_selectedAddress!.fullAddress.trim().isEmpty ||
          _selectedAddress!.fullAddress == 'العنوان غير مكتمل' ||
          _selectedAddress!.fullAddress == 'عنوان غير محدد') {
        _showMessage('يرجى إضافة أو اختيار عنوان صحيح للتوصيل', isError: true);
        return;
      }

      // إذا وصلنا هنا، العنوان صحيح ومكتمل
      await _createOrderWithAddress(appState);
    } finally {
      if (mounted) setState(() => _preparingReview = false);
    }
  }

  Future<void> _createOrderWithAddress(AppStateProvider appState) async {
    // التحقق من معلومات المستخدم
    if (_isGuestUser) {
      // التحقق من معلومات الضيف
      if (_guestName.trim().isEmpty) {
        _showMessage('يرجى إدخال اسمك الكامل', isError: true);
        return;
      }
      if (_guestPhone.trim().isEmpty) {
        _showMessage('يرجى إدخال رقم هاتفك', isError: true);
        return;
      }
    } else {
      // التحقق من معلومات المستخدم المسجل
      if (_isLoggedInWithEmail && _guestPhone.trim().isEmpty) {
        _showMessage('يرجى إدخال رقم هاتفك (مطلوب)', isError: true);
        return;
      }
      // للمستخدمين المسجلين برقم الهاتف، البريد الإلكتروني اختياري
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // تحضير بيانات المستخدم
      String? userId;
      String? customerName;
      String? customerPhone;
      String? customerEmail;

      if (_isGuestUser) {
        // مستخدم ضيف - استخدام البيانات المدخلة يدوياً
        userId = null; // null للضيوف
        customerName = _guestName.trim();
        customerPhone = _guestPhone.trim();
        customerEmail =
            _guestEmail.trim().isNotEmpty ? _guestEmail.trim() : null;
      } else {
        // مستخدم مسجل - جمع البيانات بناءً على طريقة تسجيل الدخول
        final sessionService = SessionService.instance;
        final currentUser = sessionService.currentUser;

        userId = sessionService.currentUserId;
        customerName =
            _guestName.trim().isNotEmpty
                ? _guestName.trim()
                : (currentUser?['name'] ??
                    currentUser?['full_name'] ??
                    'مستخدم');

        if (_isLoggedInWithEmail) {
          // مسجل بالإيميل - استخدام الإيميل المحفوظ ورقم الهاتف المدخل
          customerEmail = _userExistingEmail;
          customerPhone = _guestPhone.trim();
        } else if (_isLoggedInWithPhone) {
          // مسجل برقم الهاتف - استخدام رقم الهاتف المحفوظ والإيميل المدخل (إن وجد)
          customerPhone = _userExistingPhone;
          customerEmail =
              _guestEmail.trim().isNotEmpty ? _guestEmail.trim() : null;
        } else {
          // حالة افتراضية
          customerPhone =
              _guestPhone.trim().isNotEmpty
                  ? _guestPhone.trim()
                  : (currentUser?['phone'] ?? _selectedAddress!.phoneNumber);
          customerEmail =
              _guestEmail.trim().isNotEmpty
                  ? _guestEmail.trim()
                  : currentUser?['email'];
        }
      }

      // التحقق من البيانات المطلوبة قبل الإرسال
      if (customerName == null || customerName.trim().isEmpty) {
        _showMessage('خطأ: اسم العميل مطلوب', isError: true);
        return;
      }
      if (customerPhone == null || customerPhone.trim().isEmpty) {
        _showMessage('خطأ: رقم هاتف العميل مطلوب', isError: true);
        return;
      }

      // التحقق من صحة البيانات
      final storeId =
          widget.storeId ??
          (appState.cartItems.isNotEmpty
              ? appState.cartItems.first['store_id']
              : null);
      final storeName =
          widget.storeName ??
          (appState.cartItems.isNotEmpty
              ? appState.cartItems.first['store_name']
              : null);

      // الحصول على عنوان المطعم من بيانات السلة
      String storeAddress = 'العنوان غير محدد';
      if (appState.cartItems.isNotEmpty) {
        final firstItem = appState.cartItems.first;
        storeAddress =
            firstItem['store_address'] as String? ?? 'العنوان غير محدد';

        // طباعة عنوان المطعم للتشخيص
        print('🛒 CheckoutScreen - بيانات السلة:');
        print('  عدد الأصناف: ${appState.cartItems.length}');
        print('  عنوان المطعم من السلة: "$storeAddress"');
      }

      if (storeId == null || storeId.isEmpty) {
        _showMessage('خطأ: معرف المطعم غير موجود', isError: true);
        return;
      }

      if (appState.cartItems.isEmpty) {
        _showMessage('خطأ: السلة فارغة', isError: true);
        return;
      }

      print('CheckoutScreen: Creating order with data:');
      print('- Store ID: $storeId');
      print('- Store Name: $storeName');
      print('- Customer Name: $customerName');
      print('- Customer Phone: $customerPhone');
      print('- Customer Email: $customerEmail');
      print('- User ID: $userId');
      print('- Cart Items Count: ${appState.cartItems.length}');

      // الحصول على صورة المطعم من بيانات السلة
      String? storeImage;
      if (appState.cartItems.isNotEmpty) {
        final firstItem = appState.cartItems.first;
        storeImage = firstItem['store_image'] as String?;
        print('🏪 CheckoutScreen - تفاصيل صورة المطعم:');
        print('  - storeImage من السلة: "$storeImage"');
        print('  - storeImage length: ${storeImage?.length ?? 0}');
        print('  - storeImage isEmpty: ${storeImage?.isEmpty ?? true}');
        print('  - firstItem keys: ${firstItem.keys.toList()}');
        if (firstItem.containsKey('store_image')) {
          print(
            '  - store_image value type: ${firstItem['store_image'].runtimeType}',
          );
        }
      }

      final commercialScope = _discountContext(includeTip: true);
      final result = await _orderService.createOrder(
        storeId: storeId,
        storeName: storeName ?? 'المطعم',
        storeAddress: storeAddress, // عنوان المطعم للسائقين
        storeImage: storeImage, // صورة المطعم للسائقين
        cartItems: appState.cartItems,
        deliveryAddress: _selectedAddress!,
        paymentMethod: _selectedPaymentMethod,
        deliveryInstructions:
            _deliveryInstructions.isEmpty ? null : _deliveryInstructions,
        deliveryFee: _quotesEnabled ? _quotedCheckout.quote!.fee : 10.0,
        driverTipIqd: _driverTipIqd,
        quoteCheckout: _quotesEnabled ? _quotedCheckout : null,
        approveCommercial: (proposal) async {
          if (!mounted || commercialScope != _discountContext(includeTip: true)) return false;
          final scope = commercialScope;
          final accepted = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            builder:
                (_) => CommercialConfirmationSheet(
                  proposal: proposal,
                  storeName: storeName ?? 'المطعم',
                  customerName: customerName ?? '',
                  phone: customerPhone ?? '',
                  address: _selectedAddress!.fullAddress,
                  paymentLabel:
                      _selectedPaymentMethod == PaymentMethod.cash
                          ? 'نقدًا عند الاستلام'
                          : 'طريقة الدفع المختارة',
                  instructions: _deliveryInstructions,
                  items:
                      appState.cartItems
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList(),
                ),
          );
          return mounted && scope == _discountContext(includeTip: true) && accepted == true;
        },
        promoCode: _appliedPromoCode,
        platformDiscountId:_platformDiscountId,
        deliveryBenefitId:_deliveryBenefitId,
        discountId: _selectedDiscountId,
        discount: _effectiveDiscount,
        // إضافة معلومات المستخدم الحقيقية
        userId: userId,
        customerName: customerName,
        customerPhone: customerPhone,
        customerEmail: customerEmail,
      );

      print('CheckoutScreen: Order creation result: $result');

      if (result['success']) {
        PendingOffer.clear();
        final order = result['order'] as OrderModel;

        // إضافة الطلب للقائمة المحلية في OrderService
        _orderService.addOrderToList(order);

        // مسح السلة
        appState.clearCart();

        // الانتقال لشاشة تتبع الطلب
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => OrderTrackingScreen(
                  orderId: order.id,
                  orderNumber: order.orderNumber,
                ),
          ),
        );
      } else if (result['code'] != null) {
        if (!_quotedCheckout.pending && isDefinitiveOfferRejection(result['code'], (result['statusCode'] as int?) ?? 0)) {
          setState(() {
            _discountAttempt++;
            _selectedDiscountId = null;
            _platformDiscountId = null;
      _deliveryBenefitId=null;
      _deliveryBenefitSaving=0;
            _appliedPromoCode = null;
            _promoCodeController.clear();
            _discount = 0;
            _merchantDiscountAmount = 0;
            _promoDiscountAmount = 0;
            _discountLines = [];
            _validatedDiscountContext = null;
            _autoItemsEnabled = false;
            _autoItemId = null;
          });
          PendingOffer.clear();
          unawaited(_loadStoreDiscounts());
          _showMessage('لم يعد العرض صالحاً. أزلنا الخصم؛ اختر عرضاً آخر وراجع الإجمالي قبل التأكيد.', isError: true);
        } else {
          _showMessage(result['message'], isError: true);
        }
      } else if (result['statusCode'] == 409 ||
          result['errorType'] == 'ACTIVE_ORDER_CONFLICT') {
        // سياسة الطلب الواحد النشط — عرض قائمة سفلية لطيفة بدل الشريط الأحمر
        _showActiveOrderSheet(
          result['message'] as String? ??
              'لديك طلب نشط بالفعل. يجب انتظار إتمام الطلب الحالي قبل إنشاء طلب جديد.',
          result['activeOrderDetails'] as Map<String, dynamic>?,
        );
      } else {
        _showMessage(result['message'] ?? 'فشل في إنشاء الطلب', isError: true);
      }
    } on TimeoutException catch (_) {
      _showMessage(
        'انتهت مهلة الاتصال - يرجى المحاولة مرة أخرى',
        isError: true,
      );
    } on FormatException catch (_) {
      _showMessage(
        'خطأ في تنسيق البيانات - يرجى المحاولة مرة أخرى',
        isError: true,
      );
    } catch (e) {
      String errorMessage;
      final eStr = e.toString();
      if (eStr.isEmpty ||
          eStr == '{}' ||
          eStr == '{().toString()}' ||
          eStr == 'null') {
        errorMessage = 'خطأ في إنشاء الطلب - يرجى المحاولة مرة أخرى';
      } else {
        errorMessage = 'خطأ في إنشاء الطلب: $eStr';
      }
      _showMessage(errorMessage, isError: true);
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  Future<void> _resumeQuotedOrder() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await _quotedCheckout.confirm(null);
      if (!mounted) return;
      final data = jsonDecode(response.body);
      if ([200, 201].contains(response.statusCode) &&
          data['success'] == true &&
          data['order'] is Map) {
        final order = OrderModel.fromJson(
          Map<String, dynamic>.from(data['order']),
        );
        _orderService.addOrderToList(order);
        // A restored attempt may belong to a previous cart. Keep today's cart intact.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (_) => OrderTrackingScreen(
                  orderId: order.id,
                  orderNumber: order.orderNumber,
                ),
          ),
        );
      } else {
        _showMessage(
          _quotedCheckout.pending
              ? 'لم تتأكد النتيجة؛ أعد متابعة التأكيد. لن ننشئ محاولة أخرى'
              : 'لم يُنشأ الطلب بهذا العرض؛ حدّث السعر وراجعه ثم أكد مجددًا',
          isError: true,
        );
      }
    } catch (_) {
      if (mounted)
        _showMessage('تعذر تأكيد النتيجة؛ أعد متابعة التأكيد', isError: true);
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// قائمة سفلية لطيفة تُعرض عند محاولة إنشاء طلب جديد بينما يوجد طلب نشط
  void _showActiveOrderSheet(
    String message,
    Map<String, dynamic>? activeOrder,
  ) {
    final orderNumber =
        activeOrder?['orderNumber']?.toString() ??
        activeOrder?['orderId']?.toString();
    final storeName = activeOrder?['storeName']?.toString();
    final orderId = activeOrder?['orderId']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: 20 + MediaQuery.of(sheetContext).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // مقبض السحب
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // أيقونة تنبيه
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.warning,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'لديك طلب نشط بالفعل',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (orderNumber != null || storeName != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (storeName != null)
                              Text(
                                storeName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            if (orderNumber != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'رقم الطلب: $orderNumber',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // زر تتبع الطلب الحالي
              if (orderId != null)
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (context) => OrderTrackingScreen(
                                orderId: orderId,
                                orderNumber: orderNumber ?? orderId,
                              ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'تتبّع طلبي الحالي',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (orderId != null) const SizedBox(height: 10),
              // زر إغلاق
              SizedBox(
                height: 50,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'حسناً',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Keeps the form mounted while asynchronous review preparation blocks edits.
class CheckoutLoadingBody extends StatelessWidget {
  final bool busy;
  final Widget child, progress;
  const CheckoutLoadingBody({super.key, required this.busy, required this.child, required this.progress});
  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: busy,
    child: Stack(fit: StackFit.expand, children: [
      child,
      if (busy) Positioned.fill(child: ColoredBox(
        color: const Color(0xB3FAFAFA), child: progress,
      )),
    ]),
  );
}
