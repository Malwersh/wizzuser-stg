import 'package:flutter/material.dart';
import '../services/active_region_catalog.dart';

class ActiveRegionTree extends StatefulWidget {
  final ValueChanged<ActiveRegion> onSelected;
  final ActiveRegionCatalog? catalog;
  const ActiveRegionTree({super.key, required this.onSelected, this.catalog});
  @override
  State<ActiveRegionTree> createState() => _ActiveRegionTreeState();
}

class _ActiveRegionTreeState extends State<ActiveRegionTree> {
  late Future<List<ActiveRegion>> _regions;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _regions = (widget.catalog ?? ActiveRegionCatalog()).load();
  }

  static const navy = Color(0xFF0D2D60);
  Widget _node(ActiveRegion region, List<ActiveRegion> all) {
    final children = all.where((r) => r.parentId == region.id).toList();
    if (region.level == 3) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.location_on_outlined, color: navy, size: 21),
        title: Text(
          region.name,
          style: const TextStyle(color: navy, fontSize: 14),
        ),
        trailing: const Icon(Icons.chevron_left, size: 20, color: navy),
        onTap: () => widget.onSelected(region),
      );
    }
    return ExpansionTile(
      key: PageStorageKey('region-${region.id}'),
      initiallyExpanded: region.level == 0,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsetsDirectional.only(start: 12),
      iconColor: navy,
      collapsedIconColor: navy,
      title: Text(
        region.level == 0 ? 'العراق' : region.name,
        style: TextStyle(
          color: navy,
          fontSize: 14,
          fontWeight: region.level == 0 ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      children: children.map((r) => _node(r, all)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ActiveRegion>>(
    future: _regions,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        );
      if (snapshot.hasError)
        return Column(
          children: [
            const Text('تعذر تحميل المناطق المفتوحة.'),
            TextButton(
              onPressed: () => setState(_load),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        );
      final regions = snapshot.data ?? [];
      if (regions.isEmpty)
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('لا توجد مناطق مفتوحة للتوصيل حاليًا.'),
        );
      return Column(
        children:
            regions
                .where((r) => r.level == 0)
                .map((r) => _node(r, regions))
                .toList(),
      );
    },
  );
}
