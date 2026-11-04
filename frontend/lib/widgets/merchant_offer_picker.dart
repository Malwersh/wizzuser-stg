import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/store_discount.dart';
import 'basket_line_card.dart' show basketMoney;

/// Keeps checkout compact even when a restaurant has many offers.
class MerchantOfferPicker extends StatefulWidget {
  const MerchantOfferPicker({super.key, required this.offers, this.selectedId});
  final List<StoreDiscount> offers;
  final String? selectedId;
  @override
  State<MerchantOfferPicker> createState() => _MerchantOfferPickerState();
}

class _MerchantOfferPickerState extends State<MerchantOfferPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final filtered =
        widget.offers
            .where(
              (d) => '${d.title} ${d.description} ${d.displayValue}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.sizeOf(context).height * .85,
        decoration: const BoxDecoration(
          color: Color(0xFFF4F6FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'عروض المطعم',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryDark,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '${widget.offers.length} عروض • اختر عرضًا واحدًا، ثم نتحقق من شروطه',
                    style: const TextStyle(color: Color(0xFF566579)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن عرض',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.secondary,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child:
                    filtered.isEmpty
                        ? const Center(child: Text('لا توجد عروض تطابق البحث'))
                        : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: filtered.length,
                          separatorBuilder:
                              (_, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final offer = filtered[index];
                            final selected =
                                offer.discountId == widget.selectedId;
                            return Material(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(
                                  color:
                                      selected
                                          ? AppColors.secondary
                                          : const Color(0xFFE1E7EF),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => Navigator.pop(context, offer),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFF5CC),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.local_offer_outlined,
                                              color: AppColors.secondaryDark,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  offer.displayValue,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        AppColors.secondaryDark,
                                                  ),
                                                ),
                                                Text(
                                                  offer.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (selected)
                                            const Icon(
                                              Icons.check_circle,
                                              color: AppColors.secondary,
                                            ),
                                        ],
                                      ),
                                      if (offer.description.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 10,
                                          ),
                                          child: Text(
                                            offer.description,
                                            style: const TextStyle(
                                              color: Color(0xFF566579),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      Text(
                                        offer.minimumOrderAmount > 0
                                            ? 'الحد الأدنى للأصناف: ${basketMoney(offer.minimumOrderAmount)}'
                                            : 'بدون حد أدنى للأصناف',
                                        style: const TextStyle(
                                          color: Color(0xFF566579),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        selected
                                            ? 'العرض المختار'
                                            : 'اختيار العرض والتحقق من شروطه',
                                        style: const TextStyle(
                                          color: AppColors.secondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
