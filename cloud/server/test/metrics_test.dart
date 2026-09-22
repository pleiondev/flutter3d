import 'package:flutter3d_models/src/db/metrics_repository.dart';
import 'package:flutter3d_models/src/http/metrics.dart';
import 'package:test/test.dart';

void main() {
  group('renderPrometheusMetrics', () {
    const snapshot = MetricsSnapshot(
      registeredUsers: 42,
      verifiedUsers: 30,
      models: 120,
      storageBytes: 583920123,
    );

    test('one HELP, one TYPE and one value line per metric, in that order', () {
      final lines = renderPrometheusMetrics(snapshot).trimRight().split('\n');
      expect(lines, hasLength(12)); // four metrics, three lines each

      for (var i = 0; i < lines.length; i += 3) {
        expect(lines[i], startsWith('# HELP '));
        expect(lines[i + 1], startsWith('# TYPE '));
        expect(lines[i + 1], endsWith(' gauge'));
        expect(lines[i + 2], isNot(startsWith('#')));
      }
    });

    test(
      'every value is exactly what the snapshot held, with no _total suffix',
      () {
        final text = renderPrometheusMetrics(snapshot);
        expect(text, contains('flutter3d_models_registered_users 42\n'));
        expect(text, contains('flutter3d_models_verified_users 30\n'));
        expect(text, contains('flutter3d_models_uploaded_models 120\n'));
        expect(text, contains('flutter3d_models_storage_bytes 583920123\n'));
        expect(text, isNot(contains('_total')));
      },
    );

    test('ends with exactly one trailing newline', () {
      final text = renderPrometheusMetrics(snapshot);
      expect(text, endsWith('583920123\n'));
      expect(text, isNot(endsWith('\n\n')));
    });

    test('a service with nothing in it yet still renders four zeroes', () {
      const empty = MetricsSnapshot(
        registeredUsers: 0,
        verifiedUsers: 0,
        models: 0,
        storageBytes: 0,
      );
      final text = renderPrometheusMetrics(empty);
      expect(text, contains('flutter3d_models_registered_users 0\n'));
      expect(text, contains('flutter3d_models_storage_bytes 0\n'));
    });
  });
}
