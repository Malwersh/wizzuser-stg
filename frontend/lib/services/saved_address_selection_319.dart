import '../models/address_model.dart';
import '../models/browsing_location.dart';
import '../models/delivery_address.dart';
import 'session_service.dart';
import 'browsing_location_service.dart';
import 'delivery_address_manager.dart';

class SavedAddressSelection319 {
  static Future<void> activate(DetailedAddress address) async {
    final owner = SessionService.instance.currentUserId;
    if (owner == null ||
        address.userId != owner ||
        address.id.isEmpty ||
        address.latitude == null ||
        address.longitude == null)
      throw StateError('Invalid owned destination');
    final manager = DeliveryAddressManager.instance;
    await manager.setActiveAddress(DeliveryAddress.fromSavedAddress(address));
    if (SessionService.instance.currentUserId != owner)
      throw StateError('Session changed');
    final point = manager.activeAddress;
    if (point?.regionId == null) throw StateError('Destination unavailable');
    await BrowsingLocationService.instance.select(
      BrowsingLocation(
        regionId: point!.regionId!,
        regionName: point.regionNameAr ?? address.regionNameAr ?? point.city,
        source: 'saved',
        latitude: point.latitude,
        longitude: point.longitude,
        addressText: address.fullAddress,
        savedAddressId: address.id,
      ),
    );
  }
}
