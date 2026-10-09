import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:test/test.dart';

void main() {
  test('versions compare by number, not by text', () {
    expect(compareVersions('3.9.0', '3.12.0'), lessThan(0));
    expect(compareVersions('3.47.0', '3.44.0'), greaterThan(0));
    expect(compareVersions('3.13.0 (stable)', '3.13.0'), 0);
    expect(compareVersions('3.48.0-1.0.pre', '3.48.0'), 0);
  });

  test('the floors are the ones SUPPORT.md promises', () {
    final support = File('../../SUPPORT.md').readAsStringSync();
    final section = support.substring(
      support.indexOf('## The Flutter and Dart SDKs'),
    );
    expect(section, contains('Dart `>=$dartFloor <4.0.0`'));
    expect(section, contains("flutter: '>=$flutterFloor'"));
    expect(section, contains('Flutter $flutterTested'));
    expect(section, contains('Dart $dartTested'));
  });

  test('an old Flutter is a problem, a missing one is not, and the tools '
      'say how to get them', () {
    String? oldFlutter(String executable, List<String> arguments) =>
        '{"frameworkVersion": "3.40.0", "channel": "stable", '
        '"dartSdkVersion": "3.11.0", "flutterRoot": "/nowhere"}';
    final checks = runDoctorChecks(
      probe: oldFlutter,
      locate: (ExternalTool _) => null,
      dartVersion: '3.13.0',
    );
    DoctorCheck named(String name) =>
        checks.firstWhere((DoctorCheck c) => c.name == name);
    expect(named('Dart').status, DoctorStatus.ok);
    expect(named('Flutter').status, DoctorStatus.problem);
    expect(named('Flutter').fix, contains(flutterTested));
    expect(named('FBX2glTF').status, DoctorStatus.missing);
    expect(named('FBX2glTF').fix, contains('FBX2glTF/releases'));
    expect(named('Blender').status, DoctorStatus.missing);

    final none = runDoctorChecks(
      probe: (String _, List<String> _) => null,
      locate: (ExternalTool _) => '/usr/bin/tool',
      dartVersion: '3.13.0',
    );
    expect(
      none.firstWhere((DoctorCheck c) => c.name == 'Flutter').status,
      DoctorStatus.missing,
    );
    expect(
      none.where((DoctorCheck c) => c.status == DoctorStatus.problem),
      isEmpty,
    );
  });
}
