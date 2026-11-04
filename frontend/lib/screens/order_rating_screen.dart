import 'package:flutter/material.dart';
import '../services/order_rating_service.dart';
import '../services/session_service.dart';

class OrderRatingScreen extends StatefulWidget {
  final String orderId;
  final OrderRatingService? service;
  const OrderRatingScreen({super.key, required this.orderId, this.service});
  @override
  State<OrderRatingScreen> createState() => _OrderRatingScreenState();
}

class _OrderRatingScreenState extends State<OrderRatingScreen> {
  late final OrderRatingService _service;
  final _comment = TextEditingController();
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true, _saving = false, _saved = false;
  int _merchant = 0, _driver = 0, _epoch = 0;
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OrderRatingService();
    SessionService.instance.addListener(_identityChanged);
    _load();
  }

  void _identityChanged() {
    if (!_service.sameOwner && mounted) {
      _epoch++;
      _comment.clear();
      setState(() {
        _data = null;
        _loading = false;
        _saving = false;
        _error = 'UNAUTHORIZED';
      });
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load(widget.orderId);
      if (!mounted || epoch != _epoch) return;
      final review = data['review'] as Map<String, dynamic>?;
      setState(() {
        _data = data;
        _saved = review != null;
        if (review != null) {
          _merchant = (review['merchantStars'] as num).toInt();
          _driver = (review['driverStars'] as num?)?.toInt() ?? 0;
          _comment.text = review['comment'] as String? ?? '';
        }
      });
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = e is RatingException ? e.code : 'RATINGS_UNAVAILABLE',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_saving ||
        _saved ||
        _merchant == 0 ||
        (_data?['driverEligible'] == true && _driver == 0)) {
      return;
    }
    final epoch = _epoch;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.submit(
        widget.orderId,
        merchantStars: _merchant,
        driverStars: _data?['driverEligible'] == true ? _driver : null,
        comment: _comment.text,
      );
      if (mounted && epoch == _epoch) setState(() => _saved = true);
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = e is RatingException ? e.code : 'RATINGS_UNAVAILABLE',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _saving = false);
    }
  }

  String _message(String code) => switch (code) {
    'UNAUTHORIZED' ||
    'ORDER_FORBIDDEN' => 'سجّل الدخول بحساب صاحب الطلب لعرض التقييم.',
    'ORDER_NOT_DELIVERED' => 'يمكن تقييم الطلب بعد اكتمال التوصيل فقط.',
    'ALREADY_RATED' =>
      'تم تقييم هذا الطلب مسبقًا. حدّث الصفحة لعرض التقييم المحفوظ.',
    'RATING_CONFLICT' => 'لم نتأكد من الحفظ. حدّث الصفحة قبل المحاولة مجددًا.',
    _ =>
      'تعذر تأكيد حفظ التقييم. احتفظنا باختياراتك؛ حدّث الصفحة للتحقق أو حاول مجددًا.',
  };
  Widget _stars(
    String title,
    String name,
    int value,
    ValueChanged<int> change,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE4E4E7)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 6),
        Text(name),
        const SizedBox(height: 12),
        Wrap(
          children: List.generate(
            5,
            (i) => IconButton(
              tooltip: '${i + 1} من 5 — $title',
              onPressed:
                  _saved || _saving
                      ? null
                      : () => setState(() => change(i + 1)),
              icon: Icon(
                i < value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 34,
                color:
                    i < value
                        ? const Color(0xFFD99B13)
                        : const Color(0xFF71717A),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('تقييم الطلب'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _saving ? null : _load,
            tooltip: 'تحديث التقييم',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          _message(_error!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_data != null) ...[
                      Text(
                        _saved ? 'شكرًا، تم حفظ تقييمك' : 'شلون كانت تجربتك؟',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'قيّم المطعم والسائق بشكل منفصل. يُحفظ تقييم واحد لكل طلب.',
                      ),
                      const SizedBox(height: 24),
                      _stars(
                        'المطعم',
                        _data!['merchantName'] as String,
                        _merchant,
                        (v) => _merchant = v,
                      ),
                      if (_data!['driverEligible'] == true)
                        _stars(
                          'السائق',
                          _data!['driverName'] as String,
                          _driver,
                          (v) => _driver = v,
                        ),
                      TextField(
                        controller: _comment,
                        enabled: !_saved && !_saving,
                        maxLength: 500,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظاتك — اختياري',
                          hintText: 'شنو نكدر نحسّن بتجربتك؟',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (!_saved)
                        FilledButton(
                          onPressed:
                              _saving ||
                                      _merchant == 0 ||
                                      (_data!['driverEligible'] == true &&
                                          _driver == 0)
                                  ? null
                                  : _submit,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child:
                                _saving
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text('إرسال التقييم'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
    ),
  );
  @override
  void dispose() {
    _epoch++;
    SessionService.instance.removeListener(_identityChanged);
    _comment.dispose();
    _service.dispose();
    super.dispose();
  }
}
