import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/browsing_location.dart';
import '../models/address_model.dart';
import 'iraqi_delivery_details.dart';
import 'active_region_catalog.dart';
import 'session_service.dart';

class BrowsingLocationService extends ChangeNotifier {
  static final instance = BrowsingLocationService(listenToSession: true);
  final String Function() owner;
  final ActiveRegionCatalog catalog;
  BrowsingLocation? _selection;
  DetailedAddress? _confirmedAddress;
  DetailedAddress? get confirmedAddress =>
      selection != null &&
              _confirmedAddress?.userId == owner() &&
              _confirmedAddress?.regionId == selection!.regionId
          ? _confirmedAddress
          : null;
  void confirmAddress(DetailedAddress address) {
    if (selection == null ||
        address.id.isEmpty ||
        address.userId != owner() ||
        address.regionId != selection!.regionId ||
        address.latitude == null ||
        address.longitude == null ||
        !IraqiDeliveryDetails.meaningful(address.neighborhood) ||
        !IraqiDeliveryDetails.meaningful(address.landmark))
      throw StateError('Wrong delivery address scope');
    _confirmedAddress = address;
  }

  String? _scope;
  int _generation = 0;
  StreamSubscription? _session;
  BrowsingLocationService({
    String Function()? owner,
    ActiveRegionCatalog? catalog,
    bool listenToSession = false,
  }) : owner =
           owner ?? (() => SessionService.instance.currentUserId ?? 'guest'),
       catalog = catalog ?? ActiveRegionCatalog() {
    if (listenToSession)
      _session = SessionService.instance.sessionStateStream.listen((_) {
        if (_scope != this.owner()) {
          _selection = null;
          _confirmedAddress = null;
          _scope = null;
          notifyListeners();
          unawaited(restore());
        }
      });
  }
  @override
  void dispose() {
    _session?.cancel();
    super.dispose();
  }

  BrowsingLocation? get selection => _scope == owner() ? _selection : null;
  Future<void> restore() async {
    final scope = owner(), generation = ++_generation;
    if (_scope == scope && _selection != null) return;
    _scope = scope;
    _selection = null;
    _confirmedAddress = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('browsing_location_316_$scope');
      if (raw == null) return;
      final saved = BrowsingLocation.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw)),
      );
      final regions = await catalog.load();
      final matches = regions.where(
        (r) => r.id == saved.regionId && r.level == 3,
      );
      if (generation != _generation || scope != owner() || matches.isEmpty)
        return;
      _selection = BrowsingLocation(
        regionId: saved.regionId,
        regionName: matches.first.name,
        source: saved.source,
        latitude: saved.latitude,
        longitude: saved.longitude,
        addressText: saved.addressText,
        savedAddressId: saved.savedAddressId,
      );
      notifyListeners();
    } catch (_) {
      /* Do not restore an unavailable or unknown region. */
    }
  }

  Future<void> clear()async{
    final scope=owner();++_generation;_scope=scope;_selection=null;_confirmedAddress=null;
    final prefs=await SharedPreferences.getInstance();await prefs.remove('browsing_location_316_$scope');
    if(scope==owner())notifyListeners();
  }
  Future<void> select(BrowsingLocation selected) async {
    // Area choices originate from the current active catalog; point choices from the resolver.
    BrowsingLocation.fromJson(selected.toJson());
    final scope = owner();
    final generation = ++_generation;
    _scope = scope;
    _selection = selected;
    _confirmedAddress = null;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || scope != owner()) return;
    await prefs.setString(
      'browsing_location_316_$scope',
      jsonEncode(selected.toJson()),
    );
    if (scope == owner()) notifyListeners();
  }
}
