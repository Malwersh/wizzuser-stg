import 'package:flutter/material.dart';

/// Bundled display typeface for offer numerals; Arabic captions keep the app font.
class OfferValueMark extends StatelessWidget {
  final String value, suffix;
  const OfferValueMark({super.key, required this.value, required this.suffix});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$value $suffix',
    child: ExcludeSemantics(
      child: SizedBox(
        height: 76,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily:
                      RegExp(r'^[0-9.,]+$').hasMatch(value)
                          ? 'ArshilaOffer'
                          : null,
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: const Color(0xFF00296B),
                ),
              ),
              if (suffix.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 5, bottom: 8),
                  child: Text(
                    suffix,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF00296B),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
