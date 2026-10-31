import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp_user/models/address_model.dart';
import 'package:foodapp_user/models/delivery_address.dart';
void main(){
 DetailedAddress saved()=>DetailedAddress(id:'addr-new',userId:'customer',name:'العمل',province:'النجف',district:'المناذرة',neighborhood:'حي',landmark:'جامع',fullAddress:'عنوان جديد',latitude:31.9,longitude:44.4,addressType:'work',isDefault:false,createdAt:DateTime.utc(2026,10,19),updatedAt:DateTime.utc(2026,10,19));
 test('selecting a saved address preserves its owned identity and coordinates through region resolution',(){final a=DeliveryAddress.fromSavedAddress(saved());expect(a.addressId,'addr-new');expect(a.userId,'customer');expect(a.source,AddressSource.saved);final resolved=a.copyWith(regionId:'region');expect(resolved.addressId,'addr-new');expect(resolved.userId,'customer');expect(resolved.latitude,31.9);expect(resolved.formattedAddress,'عنوان جديد');expect(DeliveryAddress.fromJson(resolved.toJson()).addressId,'addr-new');});
}
