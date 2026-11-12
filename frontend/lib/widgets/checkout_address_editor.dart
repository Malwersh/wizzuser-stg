import 'delivery_location_notice.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/browsing_location.dart';
import '../models/address_model.dart';
import '../services/iraqi_delivery_details.dart';
import '../services/region_resolver_service.dart';
import '../services/address_service.dart';
import '../services/session_service.dart';
import 'location_picker_screen.dart';

class CheckoutAddressEditorController {
  Object? _owner;
  Future<bool> Function()? _submit;
  bool get attached => _submit != null;
  Future<bool> submit() async => await _submit?.call() ?? false;
  void _attach(Object owner, Future<bool> Function() submit) {
    _owner = owner;
    _submit = submit;
  }

  void _detach(Object owner) {
    if (identical(owner, _owner)) {
      _owner = null;
      _submit = null;
    }
  }
}

class CheckoutAddressEditor extends StatefulWidget {
  final BrowsingLocation selection;
  final VoidCallback? onChooseSaved;
  final DetailedAddress? initialAddress;
  final FutureOr<void> Function(DetailedAddress) onConfirmed;
  final CheckoutAddressEditorController? controller;
  final bool showSubmitButton;
  final ValueChanged<LatLng>? onPointConfirmed;
  final Future<LatLng> Function()? currentPosition;
  final RegionResolverService? resolver;
  final bool Function()? loggedIn;
  final Future<DetailedAddress?> Function(AddressCreateRequest)? persist;
  const CheckoutAddressEditor({
    super.key,
    required this.selection,
    this.onChooseSaved,
    required this.onConfirmed,
    this.onPointConfirmed,
    this.controller,
    this.showSubmitButton = true,
    this.initialAddress,
    this.currentPosition,
    this.resolver,
    this.loggedIn,
    this.persist,
  });
  @override
  State<CheckoutAddressEditor> createState() => _CheckoutAddressEditorState();
}

class _CheckoutAddressEditorState extends State<CheckoutAddressEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _hood, _landmark;
  LatLng? _point;
  bool _locating = false,
      _validPoint = false,
      _saving = false,
      _saveToBook = false;
  String? _error, _requestSignature, _requestKey;
  int _locationGeneration = 0;
  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this, _confirm);
    _hood = TextEditingController(
      text:
          widget.initialAddress?.neighborhood == '-'
              ? ''
              : widget.initialAddress?.neighborhood ?? '',
    );
    _landmark = TextEditingController(
      text:
          IraqiDeliveryDetails.meaningful(widget.initialAddress?.landmark)
              ? widget.initialAddress!.landmark
              : '',
    );
    final a = widget.initialAddress, s = widget.selection;
    if (a?.latitude != null && a?.longitude != null) {
      _validate(LatLng(a!.latitude!, a.longitude!));
    } else if (s.hasPoint) {
      _validate(LatLng(s.latitude!, s.longitude!));
    } else {
      _useCurrent();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _hood.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<LatLng> _gps() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw Exception();
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied)
      p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever)
      throw Exception();
    final point = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 12));
    return LatLng(point.latitude, point.longitude);
  }

  Future<void> _useCurrent({bool notify = false}) async {
    final generation = ++_locationGeneration;
    setState(() {
      _locating = true;
      _validPoint = false;
      _error = null;
    });
    try {
      final point = await (widget.currentPosition ?? _gps)();
      if (mounted && generation == _locationGeneration)
        await _validate(point, notify: notify);
    } catch (_) {
      if (mounted && generation == _locationGeneration)
        setState(() {
          _locating = false;
          _error = 'تعذر تحديد موقعك. حدد نقطة التوصيل على الخريطة.';
        });
    }
  }

  Future<void> _validate(LatLng point, {bool notify = false}) async {
    final generation = ++_locationGeneration;
    setState(() {
      _point = point;
      _validPoint = false;
      _locating = true;
      _error = null;
    });
    try {
      final result = await (widget.resolver ?? RegionResolverService())
          .resolvePoint(
            lat: point.latitude,
            lng: point.longitude,
            throwOnFailure: true,
          );
      if (!mounted || generation != _locationGeneration) return;
      setState(() {
        _locating = false;
        _validPoint =
            result != null &&
            result.effective.isDeliveryAvailable &&
            result.region.id == widget.selection.regionId;
        _error =
            _validPoint
                ? null
                : 'موقعك ليس داخل ${widget.selection.regionName}. صحح نقطة التوصيل على الخريطة أو غيّر المنطقة.';
      });
      if (_validPoint) widget.onPointConfirmed?.call(point);
      if (!_validPoint && notify) {
        await showDeliveryLocationNotice(
          context,
          title: 'الموقع خارج نطاق التوصيل',
          message: _error!,
        );
      }
    } catch (_) {
      if (mounted && generation == _locationGeneration)
        setState(() {
          _locating = false;
          _error = 'تعذر التحقق من الموقع. أعد المحاولة.';
        });
    }
  }

  Future<void> _map() async {
    ++_locationGeneration;
    setState(() => _locating = false);
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder:
            (_) => LocationPickerScreen(
              initialPosition:
                  _point ??
                  (widget.selection.hasPoint
                      ? LatLng(
                        widget.selection.latitude!,
                        widget.selection.longitude!,
                      )
                      : null),
              initialAddress: widget.selection.regionName,
              requiredRegionId: widget.selection.regionId,
              requirePinSelection: true,
              showCoverageNotice: true,
            ),
      ),
    );
    if (!mounted || result == null) return;
    await _validate(result['position'] as LatLng, notify: true);
  }

  Future<bool> _confirm() async {
    if (_saving || !_form.currentState!.validate()) return false;
    if (!_validPoint || _point == null) {
      setState(
        () =>
            _error ??=
                _locating
                    ? 'جارٍ التحقق من الموقع. انتظر قليلًا ثم تابع.'
                    : 'حدد نقطة التوصيل على الخريطة أولًا.',
      );
      if (!_locating) {
        await showDeliveryLocationNotice(
          context,
          title: 'راجع موقع التوصيل',
          message: _error!,
        );
      }
      return false;
    }
    if (!(widget.loggedIn?.call() ?? SessionService.instance.isLoggedIn)) {
      setState(() => _error = 'سجل الدخول لإتمام الطلب وحفظ تفاصيل التوصيل.');
      return false;
    }
    final point = _point!,
        hood = _hood.text.trim(),
        landmark = _landmark.text.trim();
    final signature = '$point|$hood|$landmark|$_saveToBook';
    if (signature != _requestSignature) {
      _requestSignature = signature;
      final random = Random.secure();
      _requestKey =
          List.generate(
            24,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final text = [
        widget.selection.addressText ?? widget.selection.regionName,
        hood,
        'قرب $landmark',
      ].join('، ');
      final service =
          widget.persist == null
              ? context.read<EnhancedAddressService>()
              : null;
      final address = await (widget.persist ?? service!.createAddress)(
        AddressCreateRequest(
          name: 'عنوان التوصيل',
          province: widget.selection.regionName,
          district: '-',
          neighborhood: hood,
          landmark: landmark,
          detailedAddress: text,
          latitude: point.latitude,
          longitude: point.longitude,
          regionId: widget.selection.regionId,
          regionNameAr: widget.selection.regionName,
          idempotencyKey: _requestKey,
          saveToAddressBook: _saveToBook,
        ),
      );
      if (!mounted) return false;
      if (address == null) {
        setState(
          () =>
              _error =
                  service?.error?.contains('10 عناوين') == true
                      ? 'عناوينك المحفوظة ممتلئة. يمكنك إلغاء خيار الحفظ والمتابعة بهذا العنوان للطلب.'
                      : service?.error ?? 'تعذر اعتماد العنوان. أعد المحاولة.',
        );
        return false;
      }
      if (address.regionId != widget.selection.regionId) {
        setState(
          () =>
              _error =
                  'تغيّرت منطقة الموقع. صحح النقطة أو اختر المنطقة مجددًا.',
        );
        return false;
      }
      await widget.onConfirmed(address);
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر حفظ العنوان. أعد المحاولة.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _fieldTitle(String title) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryDark,
          ),
        ),
      ),
      const Text(
        'مطلوب',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    ],
  );

  Widget _locationAction(String label, IconData icon, VoidCallback? action) =>
      TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondaryDark,
          backgroundColor: const Color(0xffeaf0f8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.selection.regionName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryDark,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _locationAction(
                'موقعي الحالي',
                Icons.my_location_rounded,
                _saving || _locating ? null : () => _useCurrent(notify: true),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.onChooseSaved != null) ...[
              Expanded(
                child: _locationAction(
                  'عناويني',
                  Icons.bookmark_border_rounded,
                  _saving ? null : widget.onChooseSaved,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _locationAction(
                'تعديل بالخريطة',
                Icons.map_outlined,
                _saving ? null : _map,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _fieldTitle('اسم الحي أو المحلة'),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('delivery-neighborhood'),
          controller: _hood,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          decoration: deliveryFieldDecoration('مثال: حي الجمعية'),
          validator: IraqiDeliveryDetails.validateNeighborhood,
        ),
        const SizedBox(height: 12),
        _fieldTitle('أقرب نقطة دالة'),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('delivery-landmark'),
          controller: _landmark,
          maxLength: 250,
          textInputAction: TextInputAction.done,
          decoration: deliveryFieldDecoration(
            'مثال: مقابل المدرسة أو بجانب الجامع',
          ),
          validator: IraqiDeliveryDetails.validateLandmark,
        ),
        const SizedBox(height: 12),
        if (_locating)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'جارٍ تحديد موقع التوصيل…',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        CheckboxListTile(
          value: _saveToBook,
          onChanged:
              _saving ? null : (v) => setState(() => _saveToBook = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'حفظ هذا العنوان في «عناويني»',
            style: TextStyle(fontSize: 13),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _error!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
        if (widget.showSubmitButton)
          FilledButton(
            key: const ValueKey('confirm-delivery-details'),
            onPressed: _validPoint && !_saving && !_locating ? _confirm : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEDF2FA),
              foregroundColor: AppColors.secondaryDark,
              minimumSize: const Size.fromHeight(44),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _saving ? 'جارٍ اعتماد العنوان…' : 'اعتماد عنوان التوصيل',
            ),
          ),
      ],
    ),
  );
}
