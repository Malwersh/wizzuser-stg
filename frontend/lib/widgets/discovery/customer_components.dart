import 'package:flutter/material.dart';
import '../../models/dish.dart';
import '../../utils/currency_format.dart';

const discoveryInk = Color(0xFF00296B);
const discoveryCanvas = Color(0xFFF5F6F8);
const discoveryGold = Color(0xFFFDC500);

class DiscoverySectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onViewAll;
  const DiscoverySectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.onViewAll,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: discoveryInk,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF647184),
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onViewAll != null)
          IconButton(
            tooltip: 'عرض الكل',
            onPressed: onViewAll,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: discoveryInk,
              side: const BorderSide(color: Color(0xFFE3E7EE)),
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
      ],
    ),
  );
}

class MealChoiceGroup extends StatelessWidget {
  final OptionGroup group;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const MealChoiceGroup({
    super.key,
    required this.group,
    required this.selected,
    required this.onChanged,
  });
  bool get complete =>
      (!group.required || selected.isNotEmpty) &&
      selected.length <= group.maxSelections;
  @override
  Widget build(BuildContext context) {
    final single = group.maxSelections == 1;
    final instruction =
        single
            ? (group.required
                ? 'اختر خيارًا واحدًا'
                : 'اختر خيارًا واحدًا أو تابع بدونه')
            : (group.required
                ? 'اختر خيارًا واحدًا على الأقل، حتى ${group.maxSelections}'
                : 'اختر حتى ${group.maxSelections}');
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: discoveryInk,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                      complete
                          ? const Color(0xFFEDF5EE)
                          : const Color(0xFFF0F3F8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  group.required ? (complete ? 'مكتمل' : 'مطلوب') : 'اختياري',
                  style: TextStyle(
                    fontSize: 12,
                    color: complete ? const Color(0xFF24623A) : discoveryInk,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 12),
            child: Text(
              instruction,
              style: const TextStyle(color: Color(0xFF647184), fontSize: 13),
            ),
          ),
          ...group.options.map((option) {
            final chosen = selected.contains(option.id);
            final enabled =
                option.isAvailable &&
                (chosen || single || selected.length < group.maxSelections);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                selected: chosen,
                enabled: enabled,
                button: true,
                label: option.name,
                child: Material(
                  color: chosen ? const Color(0xFFEEF3FA) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: ValueKey('choice-${group.id}-${option.id}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap:
                        !enabled
                            ? null
                            : () {
                              final next = Set<String>.from(selected);
                              if (single) {
                                next.clear();
                                if (!chosen || group.required)
                                  next.add(option.id);
                              } else {
                                chosen
                                    ? next.remove(option.id)
                                    : next.add(option.id);
                              }
                              onChanged(next);
                            },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              chosen ? discoveryInk : const Color(0xFFE3E7EE),
                          width: chosen ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            single
                                ? (chosen
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off)
                                : (chosen
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded),
                            color: enabled ? discoveryInk : Colors.grey,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              option.name,
                              style: TextStyle(
                                color:
                                    option.isAvailable
                                        ? discoveryInk
                                        : Colors.grey,
                                fontSize: 15,
                                fontWeight:
                                    chosen ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            !option.isAvailable
                                ? 'غير متوفر'
                                : option.extraPrice > 0
                                ? '+ ${formatIqd(option.extraPrice)}'
                                : 'بدون زيادة',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  option.isAvailable
                                      ? const Color(0xFF59687B)
                                      : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class CustomerOrderActionBar extends StatelessWidget {
  final int quantity;
  final double total;
  final bool busy;
  final String? hint;
  final VoidCallback? onAdd;
  final ValueChanged<int> onQuantity;
  const CustomerOrderActionBar({
    super.key,
    required this.quantity,
    required this.total,
    required this.onQuantity,
    required this.onAdd,
    this.busy = false,
    this.hint,
  });
  @override
  Widget build(BuildContext context) {
    final stepper = Container(
      decoration: BoxDecoration(
        color: discoveryCanvas,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'تقليل الكمية',
            onPressed:
                busy || quantity <= 1 ? null : () => onQuantity(quantity - 1),
            icon: const Icon(Icons.remove, size: 20),
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              color: discoveryInk,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            tooltip: 'زيادة الكمية',
            onPressed:
                busy || quantity >= 1000
                    ? null
                    : () => onQuantity(quantity + 1),
            icon: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
    );
    final action = FilledButton(
      key: const ValueKey('add-meal-to-cart'),
      onPressed: busy ? null : onAdd,
      style: FilledButton.styleFrom(
        backgroundColor: discoveryGold,
        foregroundColor: discoveryInk,
        disabledBackgroundColor: const Color(0xFFE7EAF0),
        disabledForegroundColor: const Color(0xFF66758A),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      child:
          busy
              ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: discoveryInk,
                ),
              )
              : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'أضف إلى السلة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    formatIqd(total),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE4E8EF))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    hint!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF59687B),
                      fontSize: 12,
                    ),
                  ),
                ),
              LayoutBuilder(
                builder:
                    (context, c) =>
                        c.maxWidth < 320 ||
                                MediaQuery.textScalerOf(context).scale(1) > 1.3
                            ? Column(
                              children: [
                                stepper,
                                const SizedBox(height: 8),
                                SizedBox(width: double.infinity, child: action),
                              ],
                            )
                            : Row(
                              children: [
                                stepper,
                                const SizedBox(width: 12),
                                Expanded(child: action),
                              ],
                            ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
