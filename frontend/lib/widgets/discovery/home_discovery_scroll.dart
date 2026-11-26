import 'package:flutter/material.dart';

/// Address stays outside the scroll; the first filter strip pins immediately below it.
class HomeDiscoveryScroll extends StatefulWidget {
  final Widget header, filters, content;
  final Widget? promotion;
  final Color? promotionBackground;
  final Widget Function(bool promotionVisible)? headerBuilder;
  final ScrollController controller;
  const HomeDiscoveryScroll({
    super.key,
    required this.header,
    required this.filters,
    required this.content,
    required this.controller,
    this.promotion,
    this.promotionBackground,
    this.headerBuilder,
  });
  @override
  State<HomeDiscoveryScroll> createState() => _HomeDiscoveryScrollState();
}

class _HomeDiscoveryScrollState extends State<HomeDiscoveryScroll> {
  final _promotionKey = GlobalKey();
  bool _visible = true;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final height = _promotionKey.currentContext?.size?.height ?? 0;
    final visible = height > 0 && notification.metrics.pixels < height - 1;
    if (visible != _visible) setState(() => _visible = visible);
    return false;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      widget.headerBuilder?.call(widget.promotion != null && _visible) ??
          widget.header,
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, child) {
              final offset =
                  widget.controller.hasClients ? widget.controller.offset : 0.0;
              return Stack(
                children: [
                  if (widget.promotion != null && offset < 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: -offset + 1,
                      child: ColoredBox(
                        key: const Key('promotion-overscroll-background'),
                        color: widget.promotionBackground ?? Colors.white,
                      ),
                    ),
                  child!,
                ],
              );
            },
            child: CustomScrollView(
              controller: widget.controller,
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    key: _promotionKey,
                    child: widget.promotion ?? const SizedBox.shrink(),
                  ),
                ),
                PinnedHeaderSliver(
                  child: Material(color: Colors.white, child: widget.filters),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 110),
                    child: widget.content,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
