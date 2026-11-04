import 'package:flutter/material.dart';

/// Large-photo restaurant listing. All metadata is supplied by live store sources.
class RestaurantFeedTile extends StatelessWidget {
  final String name;
  final Widget photo, favorite, metadata, delivery;
  final Widget? status;
  final double imageAspectRatio;
  final VoidCallback? onTap;
  const RestaurantFeedTile({
    super.key,
    required this.name,
    required this.photo,
    required this.favorite,
    required this.metadata,
    required this.delivery,
    this.status,
    this.imageAspectRatio = 1.55,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
    child: Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(aspectRatio: imageAspectRatio, child: photo),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF00296B),
                    ),
                  ),
                ),
                if (status != null) status!,
                favorite,
              ],
            ),
            metadata,
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [delivery],
            ),
          ],
        ),
      ),
    ),
  );
}
