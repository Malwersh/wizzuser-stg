import 'dart:async';
import 'package:flutter/material.dart';

/// Visual examples only: never inserted into the customer's query.
class RotatingSearchHint extends StatefulWidget {
  final List<String> hints;
  final int intervalSeconds;
  const RotatingSearchHint({
    super.key,
    required this.hints,
    this.intervalSeconds = 5,
  });
  @override
  State<RotatingSearchHint> createState() => _RotatingSearchHintState();
}

class _RotatingSearchHintState extends State<RotatingSearchHint>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _index = 0, _shown = 0, _ticks = 0, _holdTicks = 0;
  bool _deleting = false, _foreground = true;
  List<String> get _hints {
    final values =
        widget.hints.where((s) => s.trim().isNotEmpty).take(8).toList();
    return values.isEmpty ? ['بحث'] : values;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant RotatingSearchHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hints.join('\n') != widget.hints.join('\n')) {
      _index = _shown = _ticks = _holdTicks = 0;
      _deleting = false;
      _schedule();
    } else if (oldWidget.intervalSeconds != widget.intervalSeconds) {
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_foreground ||
        !TickerMode.of(context) ||
        MediaQuery.disableAnimationsOf(context))
      return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _ticks++;
        final length = _hints[_index % _hints.length].characters.length;
        if (_holdTicks > 0) {
          _holdTicks--;
          return;
        }
        if (_deleting) {
          if (_shown > 0) {
            _shown--;
          } else {
            _index = (_index + 1) % _hints.length;
            _deleting = false;
          }
        } else if (_shown < length) {
          _shown++;
          if (_shown == length) {
            _holdTicks = widget.intervalSeconds.clamp(4, 15) * 10;
            _deleting = _hints.length > 1;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full = _hints[_index % _hints.length];
    final reduced = MediaQuery.disableAnimationsOf(context);
    final text = reduced ? full : full.characters.take(_shown).toString();
    return Semantics(
      label: 'البحث عن مطعم أو متجر',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text),
              if (!reduced)
                TextSpan(
                  text: '\u200e│',
                  style: TextStyle(
                    color:
                        _ticks % 10 < 5
                            ? const Color(0xFF647184)
                            : Colors.transparent,
                  ),
                ),
            ],
          ),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Color(0xFF647184)),
        ),
      ),
    );
  }
}
