import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/home_slide.dart';
import 'session_service.dart';
import 'delivery_address_manager.dart';
import 'package:uuid/uuid.dart';

class HomeSlideshowFeed {
  final bool configured;
  final List<HomeSlide> slides;
  const HomeSlideshowFeed(this.configured, this.slides);
}
class HomeSlideshowService {
  static const baseUrl = String.fromEnvironment('SLIDESHOW_API_URL',
    defaultValue: 'https://7oum9md7v6.execute-api.us-east-1.amazonaws.com/staging/staff/public/home-slideshow');
  static final _sessionId=const Uuid().v4();
  Future<HomeSlideshowFeed> load({String? regionId}) async {
    final session = SessionService();
    final token = session.isLoggedIn ? await session.getToken() : null;
    if (session.isLoggedIn && token == null) throw StateError('Session unavailable');
    final response = await http.get(Uri.parse(baseUrl).replace(queryParameters: {
      if (regionId != null && regionId.isNotEmpty) 'regionId': regionId,
      if(session.isLoggedIn && session.currentUserId!=null) 'userId':session.currentUserId!,
    }), headers: {if(token != null) 'Authorization':'Bearer $token'}).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('Slideshow unavailable');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final slides = (data['slides'] as List).map((row) => HomeSlide.fromJson(Map<String,dynamic>.from(row))).toList();
    return HomeSlideshowFeed((data['version'] as num) > 0, slides);
  }
  Future<Map<String,dynamic>> details(String slideId,{String? merchantId}) async {
    return _request('home-offer',query:{'slideId':slideId,if(merchantId!=null)'merchantId':merchantId});
  }
  Future<void> track(String slideId,String type) async {try{await _request('slideshow-events',body:{'slideId':slideId,'type':type,'sessionId':_sessionId});}catch(_) {}}
  Future<Map<String,dynamic>> _request(String route,{Map<String,String> query=const {},Map<String,dynamic>? body}) async {
    final session=SessionService();final token=session.isLoggedIn?await session.getToken():null;
    if(session.isLoggedIn&&token==null)throw StateError('Session unavailable');
    final region=DeliveryAddressManager.instance.activeAddress?.regionId;
    final uri=Uri.parse(baseUrl).replace(path:Uri.parse(baseUrl).path.replaceFirst('home-slideshow',route),queryParameters:{...query,if(region!=null)'regionId':region,if(session.isLoggedIn&&session.currentUserId!=null)'userId':session.currentUserId!});
    final headers={'Content-Type':'application/json',if(token!=null)'Authorization':'Bearer $token'};
    final response=await (body==null?http.get(uri,headers:headers):http.post(uri,headers:headers,body:jsonEncode(body))).timeout(const Duration(seconds:20));
    if(response.statusCode!=200)throw StateError('العرض غير متاح حالياً لهذا الحساب أو العنوان');
    return Map<String,dynamic>.from(jsonDecode(response.body));
  }
}
