import '../models/address_model.dart';

/// Normalize supported API envelopes without accepting an address with no identity.
class AddressWriteResult {
  static DetailedAddress parse(
    Map<String, dynamic> response, {
    required String ownerId,
  }) {
    dynamic row = response;
    for (var depth = 0; depth < 4; depth++) {
      if (row is! Map) throw const FormatException('Invalid address response');
      if (row['success'] == false)
        throw const FormatException('Address was not saved');
      if (row['id'] is String && (row['id'] as String).isNotEmpty) {
        final address = DetailedAddress.fromJson(
          Map<String, dynamic>.from(row),
        );
        if (address.userId != ownerId ||
            address.latitude == null ||
            address.longitude == null ||
            !address.latitude!.isFinite ||
            !address.longitude!.isFinite)
          throw const FormatException('Invalid saved address identity');
        return address;
      }
      row = row['data'];
    }
    throw const FormatException('Missing saved address identity');
  }
}
