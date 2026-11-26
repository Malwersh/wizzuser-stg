import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:foodapp_user/services/service_fee_preview_320.dart';

void main() {
  Map<String, dynamic> preview(DateTime at, {String branch = 'b'}) => {
    'kind': 'SERVICE_FEE_PREVIEW',
    'schemaVersion': 1,
    'branchId': branch,
    'baseServiceFee': {
      'moneySchemaVersion': 1,
      'currency': 'IQD',
      'scale': 1000,
      'minorAmount': 500000,
    },
    'expiresAt': at.add(const Duration(seconds: 120)).toIso8601String(),
    'informationalOnly': true,
    'requiresFinalConfirmation': true,
  };
  test(
    'base fee preloads without address/basket; concurrent loads share one request and expiry is respected',
    () async {
      var now = DateTime.utc(2026, 10, 27), calls = 0;
      final gate = Completer<void>();
      final service = ServiceFeePreview320(
        now: () => now,
        client: MockClient((r) async {
          calls++;
          expect(jsonDecode(r.body), {
            'action': 'service_fee_preview',
            'branchId': 'b',
          });
          await gate.future;
          return http.Response(jsonEncode({'preview': preview(now)}), 200);
        }),
      );
      final a = service.ensure('b'), b = service.ensure('b');
      expect(service.baseIqd('b'), isNull);
      gate.complete();
      await Future.wait([a, b]);
      expect(calls, 1);
      expect(service.baseIqd('b'), 500);
      await service.ensure('b');
      expect(calls, 1);
      expect(service.baseIqd('other'), isNull);
      now = now.add(const Duration(seconds: 121));
      expect(service.baseIqd('b'), isNull);
      service.dispose();
    },
  );
  test(
    'foreign branch, failed server and malformed money never become an assumed fee',
    () async {
      final now = DateTime.utc(2026, 10, 27);
      for (final mode in ['foreign', 'failed', 'money']) {
        final service = ServiceFeePreview320(
          now: () => now,
          client: MockClient((_) async {
            final p = preview(now, branch: mode == 'foreign' ? 'other' : 'b');
            if (mode == 'money') p['baseServiceFee']['currency'] = 'USD';
            return http.Response(
              jsonEncode({'preview': p}),
              mode == 'failed' ? 503 : 200,
            );
          }),
        );
        await service.ensure('b');
        expect(service.baseIqd('b'), isNull);
        service.dispose();
      }
    },
  );
}
