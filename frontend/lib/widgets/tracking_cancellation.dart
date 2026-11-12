import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Presentation only. The cancellation service decides whether cancellation is
/// immediate or requires review, including when the order changes meanwhile.
class TrackingCancellationCard extends StatelessWidget {
  final bool pending;
  final VoidCallback onCancel;
  const TrackingCancellationCard({
    super.key,
    required this.pending,
    required this.onCancel,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xffe5eaf2)),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: pending ? null : onCancel,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      pending
                          ? const Color(0xffedf2fa)
                          : const Color(0xfffff0ef),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  pending ? Icons.hourglass_top_rounded : Icons.close_rounded,
                  size: 22,
                  color:
                      pending
                          ? AppColors.secondaryDark
                          : const Color(0xffbe413b),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending
                          ? 'طلب الإلغاء قيد المراجعة'
                          : 'تحتاج إلى إلغاء طلبك؟',
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      pending
                          ? 'طلبك مستمر حتى تأكيد الإلغاء. سنُطلعك على النتيجة.'
                          : 'راجع شروط الإلغاء قبل المتابعة.',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: Color(0xff65728a),
                      ),
                    ),
                  ],
                ),
              ),
              if (!pending) ...[
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    textDirection: TextDirection.ltr,
                    color: AppColors.secondaryDark,
                    size: 22,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class TrackingCancellationSheet extends StatefulWidget {
  const TrackingCancellationSheet({super.key});
  @override
  State<TrackingCancellationSheet> createState() =>
      _TrackingCancellationSheetState();
}

class _TrackingCancellationSheetState extends State<TrackingCancellationSheet> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'قبل إلغاء الطلب',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.secondaryDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _condition(
              Icons.check_circle_outline_rounded,
              'قبل التحضير وإسناد سائق',
              'يمكن الإلغاء دون رسوم، حتى لو تأكد الطلب تلقائيًا.',
            ),
            const SizedBox(height: 12),
            _condition(
              Icons.schedule_rounded,
              'بعد بدء التحضير أو إسناد سائق',
              'يُرسل طلب الإلغاء للمراجعة، ويستمر طلبك حتى تأكيد الإلغاء.',
            ),
            const SizedBox(height: 22),
            const Text(
              'سبب الإلغاء',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.secondaryDark,
              ),
              decoration: InputDecoration(
                hintText: 'أخبرنا بالسبب (اختياري)',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xff748096),
                ),
                filled: true,
                fillColor: const Color(0xfff4f6fa),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xffe3e8f1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xffe3e8f1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.secondaryDark),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondaryDark,
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              onPressed: () => Navigator.pop(context, _reason.text.trim()),
              child: const Text('تأكيد طلب الإلغاء'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'الاحتفاظ بالطلب',
                style: TextStyle(color: AppColors.secondaryDark),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _condition(IconData icon, String title, String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xfff4f6fa),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: AppColors.secondaryDark),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Color(0xff53627b),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
