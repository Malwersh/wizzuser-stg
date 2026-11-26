import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_colors.dart';

Future<bool> showDeliveryLocationNotice(
  BuildContext context, {
  required String title,
  required String message,
  bool allowContinue = false,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xffeaf0f8),
                    child: Icon(
                      Icons.location_on_outlined,
                      color: AppColors.secondaryDark,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, allowContinue),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.secondaryDark,
                        minimumSize: const Size.fromHeight(48),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        allowContinue
                            ? 'نعم، التوصيل لهذا العنوان'
                            : 'حسنًا، سأصحح الموقع',
                      ),
                    ),
                  ),
                  if (allowContinue)
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('العودة لتعديل العنوان'),
                    ),
                ],
              ),
            ),
          ),
    ) ??
    false;

/// Advisory only: ordering for another person/address is allowed. Never asks for
/// a new permission or blocks checkout when the device position is unavailable.
Future<Position?> _knownPosition() async {
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.always &&
      permission != LocationPermission.whileInUse)
    return null;
  return Geolocator.getLastKnownPosition();
}

Future<bool> confirmDeliveryDistance(
  BuildContext context,
  double lat,
  double lng, {
  Future<Position?> Function()? readPosition,
}) async {
  Position? current;
  try {
    current = await (readPosition ?? _knownPosition)();
  } catch (_) {
    return true;
  }
  if (!context.mounted ||
      current == null ||
      current.timestamp.isBefore(
        DateTime.now().subtract(const Duration(minutes: 10)),
      ) ||
      current.accuracy > 200)
    return true;
  final distance = Geolocator.distanceBetween(
    current.latitude,
    current.longitude,
    lat,
    lng,
  );
  if (distance <= 2000 + current.accuracy) return true;
  return showDeliveryLocationNotice(
    context,
    title: 'عنوان التوصيل بعيد عن موقعك',
    message: 'هل تطلب لشخص آخر أو لعنوان مختلف؟ تأكد من العنوان قبل المتابعة.',
    allowContinue: true,
  );
}

InputDecoration deliveryFieldDecoration(String hint, {Widget? icon}) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: icon,
      filled: true,
      fillColor: const Color(0xfff7f8fb),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xffe2e7ef)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xffe2e7ef)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: AppColors.secondaryDark,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xffc62828)),
      ),
    );
