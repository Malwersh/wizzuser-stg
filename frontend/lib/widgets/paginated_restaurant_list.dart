// lib/widgets/paginated_restaurant_list.dart
import 'package:flutter/material.dart';
import 'package:foodapp_user/services/optimized_api_service.dart';
import '../services/pagination_service.dart';
import '../models/store_model.dart';
import 'store_card.dart';

class PaginatedRestaurantList extends StatefulWidget {
  final String? searchQuery;
  final String? category;
  final Map<String, dynamic>? filters;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const PaginatedRestaurantList({
    super.key,
    this.searchQuery,
    this.category,
    this.filters,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  State<PaginatedRestaurantList> createState() => _PaginatedRestaurantListState();
}

class _PaginatedRestaurantListState extends State<PaginatedRestaurantList> {
  late PaginationService<StoreModel> _paginationService;
  
  @override
  void initState() {
    super.initState();
    _initializePaginationService();
  }

  void _initializePaginationService() {
    _paginationService = PaginationService<StoreModel>(
      fetchData: (page, limit) => _fetchRestaurants(page, limit),
      itemsPerPage: 20,
    );
  }

  Future<List<StoreModel>> _fetchRestaurants(int page, int limit) async {
    try {
      final response = await OptimizedApiService.getRestaurantsStatic(
        page: page,
        limit: limit,
        search: widget.searchQuery,
        category: widget.category,
        filters: widget.filters,
      );
      if (response['status'] == 'success') {
        final data = response['data'] as Map<String, dynamic>;
        final items = data['items'] as List;
        return items.map((json) => StoreModel.fromJson(json)).toList();
      }
      throw Exception('فشل في تحميل المطاعم');
    } catch (e) {
      throw Exception('خطأ في الشبكة: $e');
    }
  }

  @override
  void didUpdateWidget(PaginatedRestaurantList oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // إذا تغيرت المعاملات، أعد تحميل البيانات
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.category != widget.category ||
        oldWidget.filters != widget.filters) {
      _paginationService.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaginatedListWidget<StoreModel>(
      paginationService: _paginationService,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      padding: widget.padding,
      
      itemBuilder: (context, store, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: StoreCard(
            store: store,
            onTap: () {
              _navigateToStoreDetail(store);
            },
          ),
        );
      },
      
      loadingWidget: const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      ),
      
      errorWidget: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.restaurant_outlined,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                'خطأ في تحميل المطاعم',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'تحقق من اتصال الإنترنت وحاول مرة أخرى',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _paginationService.refresh(),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
      
      emptyWidget: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.search_off,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                'لا توجد مطاعم',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.searchQuery?.isNotEmpty == true
                    ? 'لم نجد مطاعم تطابق "${widget.searchQuery}"'
                    : 'لا توجد مطاعم متاحة حالياً',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToStoreDetail(StoreModel store) {
    Navigator.pushNamed(
      context,
      '/store_detail',
      arguments: store,
    );
  }

  @override
  void dispose() {
    _paginationService.dispose();
    super.dispose();
  }
}

// ويدجت منفصل لعرض المطاعم في شبكة
class PaginatedRestaurantGrid extends StatefulWidget {
  final String? searchQuery;
  final String? category;
  final Map<String, dynamic>? filters;
  final int crossAxisCount;
  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsetsGeometry? padding;

  const PaginatedRestaurantGrid({
    super.key,
    this.searchQuery,
    this.category,
    this.filters,
    this.crossAxisCount = 2,
    this.childAspectRatio = 0.8,
    this.crossAxisSpacing = 16,
    this.mainAxisSpacing = 16,
    this.padding,
  });

  @override
  State<PaginatedRestaurantGrid> createState() => _PaginatedRestaurantGridState();
}

class _PaginatedRestaurantGridState extends State<PaginatedRestaurantGrid> {
  late PaginationService<StoreModel> _paginationService;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    _paginationService = PaginationService<StoreModel>(
      fetchData: (page, limit) => _fetchRestaurants(page, limit),
      itemsPerPage: 20,
    );
  }

  Future<List<StoreModel>> _fetchRestaurants(int page, int limit) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'limit': limit,
    };

    if (widget.searchQuery?.isNotEmpty == true) {
      queryParams['search'] = widget.searchQuery;
    }
    
    if (widget.category?.isNotEmpty == true) {
      queryParams['category'] = widget.category;
    }

    if (widget.filters != null) {
      queryParams.addAll(widget.filters!);
    }

    final response = await OptimizedApiService.getRestaurantsStatic(
      page: page,
      limit: limit,
      search: widget.searchQuery,
      category: widget.category,
      filters: widget.filters,
    );
    
    if (response['status'] == 'success') {
      final data = response['data'] as Map<String, dynamic>;
      final items = data['items'] as List;
      
      return items.map((json) => StoreModel.fromJson(json)).toList();
    }
    
    throw Exception('فشل في تحميل المطاعم');
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _paginationService.loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierBuilder<PaginationService<StoreModel>>(
      notifier: _paginationService,
      builder: (context, service) {
        if (service.error != null && service.items.isEmpty) {
          return const Center(
            child: Text('خطأ في تحميل المطاعم'),
          );
        }

        if (service.items.isEmpty && service.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: () => service.refresh(),
          child: GridView.builder(
            controller: _scrollController,
            padding: widget.padding ?? const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.crossAxisCount,
              childAspectRatio: widget.childAspectRatio,
              crossAxisSpacing: widget.crossAxisSpacing,
              mainAxisSpacing: widget.mainAxisSpacing,
            ),
            itemCount: service.items.length + (service.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= service.items.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final store = service.items[index];
              return StoreCard(
                store: store,
                isCompact: true,
                onTap: () => _navigateToStoreDetail(store),
              );
            },
          ),
        );
      },
    );
  }

  void _navigateToStoreDetail(StoreModel store) {
    // التحقق من أن الـ widget ما زال mounted قبل التنقل
    if (!mounted) return;
    
    Navigator.pushNamed(
      context,
      '/store_detail',
      arguments: store,
    );
  }

  @override
  void didUpdateWidget(PaginatedRestaurantGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.category != widget.category ||
        oldWidget.filters != widget.filters) {
      _paginationService.refresh();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _paginationService.dispose();
    super.dispose();
  }
}

// مساعد لبناء ChangeNotifier
class ChangeNotifierBuilder<T extends ChangeNotifier> extends StatefulWidget {
  final T notifier;
  final Widget Function(BuildContext context, T notifier) builder;

  const ChangeNotifierBuilder({
    super.key,
    required this.notifier,
    required this.builder,
  });

  @override
  State<ChangeNotifierBuilder<T>> createState() => _ChangeNotifierBuilderState<T>();
}

class _ChangeNotifierBuilderState<T extends ChangeNotifier> 
    extends State<ChangeNotifierBuilder<T>> {
  
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onNotifierChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.notifier);
  }
}
