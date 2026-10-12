/// The host half of `integration_test/pacing_test.dart` — `N3`.
///
/// Writes what the run reported to `FLUTTER3D_PACING_OUT` (by default
/// `build/pacing.json`), where `tool/pacing.sh` turns it into the report.
library;

import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (Map<String, dynamic>? data) async {
    final out =
        Platform.environment['FLUTTER3D_PACING_OUT'] ?? 'build/pacing.json';
    File(out)
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  },
);
