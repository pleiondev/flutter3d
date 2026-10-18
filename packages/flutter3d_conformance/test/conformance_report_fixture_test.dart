/// The conformance report an older suite wrote, read by this one.
///
///     dart test test/conformance_report_fixture_test.dart
///
/// `test/fixtures/v<N>/glow.conformance.json` is minted once at each
/// version and never re-minted: a catalogue or a CI job holding a report
/// of version 1 reads it with every later 1.x.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

void main() {
  test('the version 1 report opens, its badge and outcomes in place', () {
    final report = conformanceReportFormat.open(
      jsonDecode(
            File('test/fixtures/v1/glow.conformance.json').readAsStringSync(),
          )
          as Map<String, Object?>,
      refuse: DocumentFormatException.new,
    );
    // Mutation: rename `badge` or `outcomes` in `conformanceReport`, and the
    // report a catalogue holds no longer says what it did.
    expect(report['plugin'], 'glow');
    expect(report['badge'], 'conformant@1.0');
    expect(report['outcomes'], hasLength(5));
    expect(
      conformanceReport('glow', const <PluginCheckOutcome>[]).keys,
      containsAll(<String>['plugin', 'suite', 'badge', 'outcomes']),
    );
  });
}
