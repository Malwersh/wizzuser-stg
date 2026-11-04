import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/services/address_write_result.dart';
import 'package:foodapp_user/models/delivery_address.dart';

void main() {
  Map<String, dynamic> row() => {
    'id': 'addr-real',
    'user_id': 'owner',
    'name': 'المنزل',
    'full_address': 'النجف، عنواني',
    'latitude': 31.9,
    'longitude': 44.4,
    'created_at': '2026-10-25T00:00:00Z',
    'updated_at': '2026-10-25T00:00:00Z',
  };
  test(
    'nested successful create preserves the server id, ownership and coordinates',
    () {
      final a = AddressWriteResult.parse({
        'success': true,
        'data': {'success': true, 'data': row()},
      }, ownerId: 'owner');
      final selected = DeliveryAddress.fromSavedAddress(a);
      expect(selected.addressId, 'addr-real');
      expect(selected.userId, 'owner');
      expect(selected.source, AddressSource.saved);
      expect(selected.latitude, 31.9);
    },
  );
  test('direct and single wrapped update payloads retain real identity', () {
    for (final data in [
      row(),
      {'success': true, 'data': row()},
    ]) {
      expect(AddressWriteResult.parse(data, ownerId: 'owner').id, 'addr-real');
    }
  });
  test(
    'empty, failed and wrong-owner responses are never treated as saved addresses',
    () {
      for (final data in <Map<String, dynamic>>[
        {},
        {'success': true, 'data': {}},
        {'success': false, 'data': row()},
        {...row(), 'id': ''},
        {...row(), 'user_id': 'another'},
        {...row(), 'latitude': null},
      ]) {
        expect(
          () => AddressWriteResult.parse(data, ownerId: 'owner'),
          throwsFormatException,
        );
      }
    },
  );
}
