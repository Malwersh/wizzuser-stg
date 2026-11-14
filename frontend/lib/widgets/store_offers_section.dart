import 'package:flutter/material.dart';
import '../models/store_offer_slot.dart';
import '../constants/app_colors.dart';
import 'offer_value_mark.dart';

class StoreOffersSection extends StatelessWidget {
  final String title, description;
  final StoreOfferSlot config;
  final List<StoreOffer> offers;
  final void Function(StoreOffer) onDetails, onBrowse;
  const StoreOffersSection({
    super.key,
    required this.title,
    required this.description,
    required this.config,
    required this.offers,
    required this.onDetails,
    required this.onBrowse,
  });
  @override
  Widget build(BuildContext context) {
    final rows = config.select(offers, DateTime.now());
    if (rows.isEmpty) return const SizedBox.shrink();
    Widget card(StoreOffer o, {bool prominent = false}) {
      final fallback = _OfferCard(
        offer: o,
        prominent: prominent,
        showImage: config.presentation != 'image' && config.showImage,
        showSource: config.showSource,
        onDetails: () => onDetails(o),
        onBrowse: () => onBrowse(o),
      );
      if (config.presentation != 'image' || o.imageUrl.isEmpty) {
        return AspectRatio(aspectRatio: 1, child: fallback);
      }
      return Semantics(
        button: true,
        label: '${o.headline}، عرض التفاصيل والشروط',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: GestureDetector(
            onTap: () => onDetails(o),
            child: AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: const Color(0xFFF5F7FA),
                child: Image.network(
                  o.imageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => fallback,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget carousel(List<StoreOffer> list) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            list
                .map(
                  (o) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: SizedBox(width: 232, child: card(o)),
                  ),
                )
                .toList(),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF00296B),
            ),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                description,
                style: const TextStyle(color: Color(0xFF647184), fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          if (config.presentation != 'image' &&
              (rows.length == 1 || config.style == 'spotlight'))
            card(rows.first, prominent: true),
          if (config.style == 'list' &&
              (rows.length > 1 || config.presentation == 'image'))
            ...rows.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: card(o),
              ),
            )
          else if (rows.length > 1 || config.presentation == 'image') ...[
            if (config.style == 'spotlight' && config.presentation != 'image')
              const SizedBox(height: 12),
            carousel(
              config.style == 'spotlight' && config.presentation != 'image'
                  ? rows.skip(1).toList()
                  : rows,
            ),
          ],
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final StoreOffer offer;
  final bool prominent, showImage, showSource;
  final VoidCallback onDetails, onBrowse;
  const _OfferCard({
    required this.offer,
    required this.prominent,
    required this.showImage,
    required this.showSource,
    required this.onDetails,
    required this.onBrowse,
  });
  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF00296B);
    final textOnly = !showImage || offer.imageUrl.isEmpty;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!textOnly) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              offer.imageUrl,
              height: 108,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Icon(
              offer.kind == 'delivery'
                  ? Icons.delivery_dining_outlined
                  : Icons.local_offer_outlined,
              size: 22,
              color: navy,
            ),
            if (showSource) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  offer.sourceLabel,
                  style: const TextStyle(fontSize: 11, color: navy),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          offer.headline,
          style: TextStyle(
            fontSize: prominent ? 21 : 17,
            fontWeight: FontWeight.w700,
            color: navy,
            height: 1.4,
          ),
        ),
        if (offer.brief.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            offer.brief,
            style: const TextStyle(fontSize: 12, height: 1.6, color: navy),
          ),
        ],
      ],
    );
    final actions = Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (offer.kind == 'items')
          TextButton.icon(
            onPressed: onBrowse,
            style: TextButton.styleFrom(
              foregroundColor: navy,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            icon: const Icon(Icons.restaurant_menu, size: 17),
            label: const Text(
              'شاهد الأصناف',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        TextButton(
          onPressed: onDetails,
          style: TextButton.styleFrom(
            foregroundColor: navy,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          child: Text(
            offer.kind == 'items' ? 'التفاصيل' : 'تفاصيل العرض',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
    if (textOnly) {
      final hero = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OfferValueMark(value: offer.displayValue, suffix: offer.displayUnit),
          const SizedBox(height: 2),
          Text(
            offer.displayCaption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: navy,
            ),
          ),
          if (offer.brief.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              offer.brief,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.5, color: navy),
            ),
          ],
        ],
      );
      return Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onDetails,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFFFFD642), AppColors.primary],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: LayoutBuilder(
              builder:
                  (context, constraints) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.local_offer_outlined,
                              size: 17,
                              color: navy,
                            ),
                          ),
                          if (showSource) ...[
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                offer.sourceLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: navy,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (constraints.hasBoundedHeight)
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(child: hero),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: hero,
                        ),
                      Divider(height: 1, color: navy.withValues(alpha: 0.16)),
                      Center(child: actions),
                    ],
                  ),
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder:
                (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (constraints.hasBoundedHeight)
                      Expanded(child: SingleChildScrollView(child: content))
                    else
                      content,
                    const SizedBox(height: 8),
                    actions,
                  ],
                ),
          ),
        ),
      ),
    );
  }
}
