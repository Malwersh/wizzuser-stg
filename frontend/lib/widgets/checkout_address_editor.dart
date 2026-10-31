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

class CheckoutAddressEditor extends StatefulWidget {
  final BrowsingLocation selection;
  final DetailedAddress? initialAddress;
  final ValueChanged<DetailedAddress> onConfirmed;
  final ValueChanged<LatLng>? onPointConfirmed;
  final Future<LatLng> Function()? currentPosition;
  final RegionResolverService? resolver;
  final bool Function()? loggedIn;
  final Future<DetailedAddress?> Function(AddressCreateRequest)? persist;
  const CheckoutAddressEditor({
    super.key,
    required this.selection,
    required this.onConfirmed,
    this.onPointConfirmed,
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

  Future<void> _useCurrent() async {
    final generation = ++_locationGeneration;
    setState(() {
      _locating = true;
      _validPoint = false;
      _error = null;
    });
    try {
      final point = await (widget.currentPosition ?? _gps)();
      if (mounted && generation == _locationGeneration) await _validate(point);
    } catch (_) {
      if (mounted && generation == _locationGeneration)
        setState(() {
          _locating = false;
          _error = 'تعذر تحديد موقعك. حدد نقطة التوصيل على الخريطة.';
        });
    }
  }

  Future<void> _validate(LatLng point) async {
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
        if (!_validPoint)
          _error =
              'موقعك ليس داخل ${widget.selection.regionName}. صحح نقطة التوصيل على الخريطة أو غيّر المنطقة.';
      });
      if (_validPoint) widget.onPointConfirmed?.call(point);
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
            ),
      ),
    );
    if (!mounted || result == null) return;
    await _validate(result['position'] as LatLng);
  }

  Future<void> _confirm() async {
    if (!_form.currentState!.validate() ||
        !_validPoint ||
        _point == null ||
        _saving)
      return;
    if (!(widget.loggedIn?.call() ?? SessionService.instance.isLoggedIn)) {
      setState(() => _error = 'سجل الدخول لإتمام الطلب وحفظ تفاصيل التوصيل.');
      return;
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
      if (!mounted) return;
      if (address == null) {
        setState(
          () =>
              _error =
                  service?.error?.contains('10 عناوين') == true
                      ? 'عناوينك المحفوظة ممتلئة. يمكنك إلغاء خيار الحفظ والمتابعة بهذا العنوان للطلب.'
                      : service?.error ?? 'تعذر اعتماد العنوان. أعد المحاولة.',
        );
        return;
      }
      if (address.regionId != widget.selection.regionId) {
        setState(
          () =>
              _error =
                  'تغيّرت منطقة الموقع. صحح النقطة أو اختر المنطقة مجددًا.',
        );
        return;
      }
      widget.onConfirmed(address);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'تعذر اعتماد العنوان. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
        if (widget.selection.addressText?.isNotEmpty == true &&
            widget.selection.addressText!.trim() !=
                widget.selection.regionName.trim())
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.selection.addressText!,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('delivery-neighborhood'),
          controller: _hood,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'اسم الحي أو المحلة *',
            counterText: '',
          ),
          validator: IraqiDeliveryDetails.validateNeighborhood,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('delivery-landmark'),
          controller: _landmark,
          maxLength: 250,
          decoration: const InputDecoration(
            labelText: 'أقرب نقطة دالة *',
            hintText: 'مثل: مقابل المدرسة، بجانب الجامع',
            counterText: '',
          ),
          validator: IraqiDeliveryDetails.validateLandmark,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              _validPoint ? Icons.check_circle_outline : Icons.my_location,
              color: AppColors.secondaryDark,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _locating
                    ? 'جارٍ تحديد نقطة التوصيل…'
                    : _validPoint
                    ? 'نقطة التوصيل داخل المنطقة المختارة'
                    : 'حدد نقطة التوصيل لحساب المسافة',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (_locating)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton.icon(
              onPressed: _saving || _locating ? null : _useCurrent,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('موقعي الحالي'),
            ),
            TextButton.icon(
              onPressed: _saving ? null : _map,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('تصحيح بالخريطة'),
            ),
          ],
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
