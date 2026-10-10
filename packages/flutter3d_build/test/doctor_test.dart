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

  test('in a project, the data files below the current version are a '
      'note that names them and the command that lifts them', () {
    // Mutation: drop the project check from `runDoctorChecks`, or make it a
    // problem (the engine reads the files; nothing is broken).
    final project = Directory.systemTemp.createTempSync('doctor_data');
    addTearDown(() => project.deleteSync(recursive: true));
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: game\n');
    final level = File('${project.path}/assets/start.level.json')
      ..parent.createSync()
      ..writeAsStringSync('{"version": 1, "name": "start"}\n');
    List<DoctorCheck> run() => runDoctorChecks(
      probe: (String _, List<String> _) => null,
      locate: (ExternalTool _) => null,
      dartVersion: '3.13.0',
      project: project,
    );
    final behind = run().firstWhere((DoctorCheck c) => c.name == 'Data files');
    expect(behind.status, DoctorStatus.note);
    expect(behind.detail, contains('assets/start.level.json (f3d.level v1'));
    expect(behind.fix, contains('flutter3d migrate --data'));

    level.writeAsStringSync(
      '{"format": "f3d.level", "version": 4, "name": "start"}\n',
    );
    expect(
      run().firstWhere((DoctorCheck c) => c.name == 'Data files').status,
      DoctorStatus.ok,
    );
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
