import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/home_slide.dart';
import '../models/delivery_address.dart';
import '../services/home_slideshow_service.dart';
import '../services/delivery_address_manager.dart';
import '../services/session_service.dart';

class HomeSlideshow extends StatefulWidget {
  final ValueChanged<HomeSlide> onTap;
  const HomeSlideshow({super.key, required this.onTap});
  @override
  State<HomeSlideshow> createState() => _HomeSlideshowState();
}
class _HomeSlideshowState extends State<HomeSlideshow> with WidgetsBindingObserver {
  final _controller = PageController();
  final _service = HomeSlideshowService();
  final _session = SessionService();
  StreamSubscription<DeliveryAddress?>? _addresses;
  Timer? _rotation, _refresh;
  List<HomeSlide> _slides = [];
  int _page = 0, _request = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_contextChanged);
    _addresses = DeliveryAddressManager.instance.addressStream.listen((_) => _contextChanged());
    _load();
    _rotation = Timer.periodic(const Duration(seconds: 3), (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed || !_controller.hasClients) return;
      _recordView();
      final count = _slides.length;
      if(count > 1) _controller.animateToPage((_page + 1) % count, duration: const Duration(milliseconds:300), curve: Curves.easeInOut);
    });
    _refresh = Timer.periodic(const Duration(seconds:60), (_) {
      if(WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _load();
    });
  }
  void _recordView(){
    if(!mounted||_page>=_slides.length||WidgetsBinding.instance.lifecycleState!=AppLifecycleState.resumed||ModalRoute.of(context)?.isCurrent!=true)return;
    final box=context.findRenderObject();if(box is! RenderBox||!box.hasSize)return;
    final top=box.localToGlobal(Offset.zero).dy,screen=MediaQuery.sizeOf(context).height;
    if(top<screen&&top+box.size.height>0)_service.track(_slides[_page].id,'view');
  }
  void _contextChanged() {
    // Remove content for the previous account/address while eligibility reloads.
    if(mounted) setState(() => _slides = []);
    _load();
  }
  Future<void> _load() async {
    final request = ++_request;
    try {
      final feed = await _service.load(regionId:DeliveryAddressManager.instance.activeAddress?.regionId);
      if(!mounted || request != _request) return;
      setState(() { _slides = feed.slides.where((s) => s.endAt.isAfter(DateTime.now())).toList(); _page = 0; });
      if(_controller.hasClients) _controller.jumpToPage(0);
      WidgetsBinding.instance.addPostFrameCallback((_)=>_recordView());
    } catch (_) {
      if(!mounted || request != _request) return;
      setState(() => _slides = _slides.where((s) => s.endAt.isAfter(DateTime.now())).toList());
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if(state == AppLifecycleState.resumed) _load(); }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); _session.removeListener(_contextChanged);
    _addresses?.cancel(); _rotation?.cancel(); _refresh?.cancel(); _controller.dispose(); super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if(_slides.isEmpty) return const SizedBox.shrink();
    final count = _slides.length;
    return Container(height:180, margin:const EdgeInsets.symmetric(horizontal:16), child:PageView.builder(
      controller:_controller, itemCount:count, onPageChanged:(i) { _page=i;_recordView(); },
      itemBuilder:(context,index) {
        final slide = _slides[index];
        return Semantics(label:slide.title,button:true,child:ClipRRect(borderRadius:BorderRadius.circular(12),child:Material(child:InkWell(
          onTap:() { _service.track(slide.id,'tap');widget.onTap(slide); },
          child:CachedNetworkImage(imageUrl:slide.imageUrl,cacheKey:'home-slide-${slide.id}-${slide.imageVersion}',fit:BoxFit.cover,
            placeholder:(_,_)=>const ColoredBox(color:Color(0xffedf1f5)),
            errorWidget:(_,_,_)=>Center(child:Text(slide.title))),
        ))));
      },
    ));
  }
}
