import 'package:flutter/material.dart';
import '../models/home_slide.dart';
import '../services/home_slideshow_service.dart';
import '../services/pending_offer.dart';
import '../services/session_service.dart';
import '../services/delivery_address_manager.dart';
class OfferDetailScreen extends StatefulWidget {
 final HomeSlide slide; final Future<void> Function(String merchantId) openMerchant;
 const OfferDetailScreen({super.key,required this.slide,required this.openMerchant});
 @override State<OfferDetailScreen> createState()=>_OfferDetailScreenState();
}
class _OfferDetailScreenState extends State<OfferDetailScreen> {
 final _service=HomeSlideshowService();Map<String,dynamic>? data;String? merchant,error,scope;bool busy=false;int request=0;
 String contextKey()=> '${SessionService.instance.currentUserId}|${DeliveryAddressManager.instance.activeAddress?.regionId}';
 @override void initState(){super.initState();load();}
 Future<void> load({String? merchantId}) async {final n=++request,context=contextKey();setState((){busy=true;error=null;});try{final result=await _service.details(widget.slide.id,merchantId:merchantId);if(!mounted||n!=request)return;if(context!=contextKey())throw StateError('تغير الحساب أو العنوان، يرجى تحديث العرض');setState((){data=result;merchant=merchantId;scope=context;});}catch(e){if(mounted&&n==request)setState(()=>error='تعذر تحميل العرض. قد يكون انتهى أو لا ينطبق على حسابك أو عنوانك.');}finally{if(mounted&&n==request)setState(()=>busy=false);}}
 @override Widget build(BuildContext context){final offer=data?['offer'] as Map?;final merchants=data?['merchants'] as List? ?? [];final products=data?['products'] as List? ?? [];
 return Scaffold(appBar:AppBar(title:const Text('تفاصيل العرض')),body:busy?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Text(error!,textAlign:TextAlign.center),TextButton(onPressed:()=>load(merchantId:merchant),child:const Text('إعادة المحاولة'))])):offer==null?const SizedBox.shrink():ListView(padding:const EdgeInsets.all(20),children:[
 ClipRRect(borderRadius:BorderRadius.circular(16),child:Image.network(widget.slide.imageUrl,height:180,fit:BoxFit.cover,errorBuilder:(_,_,_)=>const SizedBox.shrink())),const SizedBox(height:16),
 Text(offer['title']??widget.slide.title,style:Theme.of(context).textTheme.headlineSmall),Text(offer['description']??''),const SizedBox(height:12),
 Text(offer['type']=='percentage'?'خصم ${offer['value']}%':offer['type']=='freeDelivery'?'توصيل مجاني':'خصم ${offer['value']} د.ع'),
 for(final condition in offer['conditions'] as List? ?? [])Text(condition.toString()),
 Text('الحد الأدنى للطلب: ${offer['minimumOrder']} د.ع'),if(offer['maximumSavings']!=null)Text('أقصى خصم: ${offer['maximumSavings']} د.ع'),
 Text('ينتهي: ${DateTime.parse(offer['endAt']).toLocal()}'),if(offer['firstOrderOnly']==true)const Text('لأول طلب فقط'),if(offer['perCustomerLimit']!=null)Text('عدد الاستخدامات لكل عميل: ${offer['perCustomerLimit']}'),
 if(offer['applicability']=='specificItems'||offer['applicability']=='specificCategories')const Text('الخصم على المنتجات المشمولة فقط. باقي المنتجات بسعرها المعتاد.'),
 const Text('يتم التحقق من الأهلية وحساب الخصم النهائي عند إتمام الطلب. لا يجمع مع عرض آخر.'),const Divider(height:32),
 const Text('اختر المتجر لعرض المنتجات المشمولة'),for(final m in merchants)ListTile(title:Text(m['name']),selected:merchant==m['id'],trailing:const Icon(Icons.chevron_right),onTap:()=>load(merchantId:m['id'])),
 if(merchants.isEmpty)const Text('لا توجد متاجر متاحة لهذا العنوان حالياً.'),
 if(merchant!=null)...[const Divider(),const Text('المنتجات المشمولة'),if(products.isEmpty)const Text('لا توجد منتجات متاحة لهذا العرض حالياً.'),for(final p in products)ListTile(title:Text(p['name']),subtitle:Text('${p['price']} د.ع قبل الخصم'))],
 const SizedBox(height:80)]),bottomNavigationBar:merchant!=null&&offer!=null&&!busy&&error==null?SafeArea(child:Padding(padding:const EdgeInsets.all(16),child:FilledButton(onPressed:products.isEmpty?null:()async{
 if(scope!=contextKey()||!DateTime.parse(offer['endAt']).isAfter(DateTime.now())){await load(merchantId:merchant);return;}
 PendingOffer.select(PendingOffer(widget.slide.id,merchant!,Map<String,dynamic>.from(offer),DateTime.parse(offer['endAt'])));
 await widget.openMerchant(merchant!);
 },child:const Text('استخدم العرض وتسوق')))):null);
 }
}
