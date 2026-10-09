// lib/services/pagination_service.dart
import 'package:flutter/material.dart';

class PaginationService<T> extends ChangeNotifier {
  final Future<List<T>> Function(int page, int limit) fetchData;
  final int itemsPerPage;
  
  List<T> _items = [];
  int _currentPage = 0; // Start with 0-based pagination
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  
  PaginationService({
    required this.fetchData,
    this.itemsPerPage = 20,
  });

  List<T> get items => _items;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get error => _error;
  int get currentPage => _currentPage;
  int get totalItems => _items.length;

  Future<void> loadFirstPage() async {
    _currentPage = 0; // Start with page 0
    _items.clear();
    _hasMore = true;
    _error = null;
    await _loadPage();
  }

  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    _currentPage++;
    await _loadPage();
  }

  Future<void> refresh() async {
    await loadFirstPage();
  }

  Future<void> _loadPage() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newItems = await fetchData(_currentPage, itemsPerPage);
      
      if (newItems.isEmpty) {
        _hasMore = false;
      } else {
        if (_currentPage == 0) {
          _items = newItems;
        } else {
          _items.addAll(newItems);
        }
        _hasMore = newItems.length == itemsPerPage;
      }
    } catch (e) {
      _error = e.toString();
      if (_currentPage > 0) _currentPage--; // Don't go below 0
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _items.clear();
    _currentPage = 0; // Reset to page 0
    _isLoading = false;
    _hasMore = true;
    _error = null;
    notifyListeners();
  }
}

class PaginatedListWidget<T> extends StatefulWidget {
  final PaginationService<T> paginationService;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget? loadingWidget;
  final Widget? errorWidget;
  final Widget? emptyWidget;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;

  const PaginatedListWidget({
    super.key,
    required this.paginationService,
    required this.itemBuilder,
    this.loadingWidget,
    this.errorWidget,
    this.emptyWidget,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
  });

  @override
  State<PaginatedListWidget<T>> createState() => _PaginatedListWidgetState<T>();
}

class _PaginatedListWidgetState<T> extends State<PaginatedListWidget<T>> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    // تحميل الصفحة الأولى إذا لم تكن محملة
    if (widget.paginationService.items.isEmpty && !widget.paginationService.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.paginationService.loadFirstPage();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      widget.paginationService.loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierBuilder<PaginationService<T>>(
      notifier: widget.paginationService,
      builder: (context, service) {
        if (service.error != null && service.items.isEmpty) {
          return widget.errorWidget ?? 
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('حدث خطأ: ${service.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => service.refresh(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
        }

        if (service.items.isEmpty) {
          if (service.isLoading) {
            return widget.loadingWidget ?? 
              const Center(child: CircularProgressIndicator());
          } else {
            return widget.emptyWidget ?? 
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('لا توجد عناصر لعرضها'),
                  ],
                ),
              );
          }
        }

        return RefreshIndicator(
          onRefresh: () => service.refresh(),
          child: ListView.builder(
            controller: _scrollController,
            shrinkWrap: widget.shrinkWrap,
            physics: widget.physics,
            padding: widget.padding,
            itemCount: service.items.length + (service.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= service.items.length) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              return widget.itemBuilder(context, service.items[index], index);
            },
          ),
        );
      },
    );
  }
}

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
