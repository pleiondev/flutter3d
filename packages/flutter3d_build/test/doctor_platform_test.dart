/// `doctor` on the keys that turn Flutter GPU on for an application: the two
/// in each Apple `Info.plist` and the one in Android's manifest, which the
/// quickstart tells a project to add. Without them the app opens and draws
/// through the software rasteriser, and nothing fails.
///
/// The fixtures under `test/fixtures/doctor_platform/` are the platform
/// folders only; each test copies one into a resolved workspace.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:test/test.dart';

/// An application depending on [backend], resolved the way `pub get`
/// writes it, with the platform folders of fixture [fixture] copied in.
Directory _app(String fixture, {String backend = 'flutter3d_impeller'}) {
  final root = Directory.systemTemp.createTempSync('f3d_doctor_platform_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final (name, pubspec) in <(String, String)>[
    ('app', 'dependencies:\n  $backend: any\n'),
    (backend, ''),
  ]) {
    File('${root.path}/packages/$name/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: $name\n$pubspec');
  }
  File('${root.path}/packages/app/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final name in <String>['app', backend])
            <String, Object?>{
              'name': name,
              'rootUri': '../../$name',
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  final source = Directory('test/fixtures/doctor_platform/$fixture');
  for (final file in source.listSync(recursive: true).whereType<File>()) {
    final relative = file.path.substring(source.path.length + 1);
    File('${root.path}/packages/app/$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(file.readAsBytesSync());
  }
  return Directory('${root.path}/packages/app');
}

DoctorCheck _named(List<DoctorCheck> checks, String name) =>
    checks.singleWhere((check) => check.name == name);

void main() {
  test('keys that are there are ok, and a platform folder that is not '
      'there gets no line', () {
    // Mutation: report iOS whether or not `ios/` exists, and a project
    // built for two platforms is told about a third.
    final checks = projectPlatformChecks(_app('present'));
    expect(checks.map((c) => c.name), <String>[
      'GPU keys, macOS',
      'GPU key, Android',
    ]);
    for (final check in checks) {
      expect(check.status, DoctorStatus.ok, reason: check.detail);
    }
  });

  test('a key that is missing, false or only in a comment is a problem '
      'whose fix names the key and the file', () {
    // Mutation: search the file's text without taking comments out, and
    // the Android key a comment quotes reads as present; or accept any
    // value after the key, and iOS's `<false/>` reads as on.
    final checks = projectPlatformChecks(_app('missing'));

    final macos = _named(checks, 'GPU keys, macOS');
    expect(macos.status, DoctorStatus.problem);
    expect(macos.detail, contains('FLTEnableFlutterGPU'));
    expect(macos.detail, contains('FLTEnableImpeller'));
    expect(macos.detail, contains('software rasteriser'));
    expect(macos.fix, contains('macos/Runner/Info.plist'));
    expect(macos.fix, contains('<key>FLTEnableFlutterGPU</key><true/>'));

    final ios = _named(checks, 'GPU keys, iOS');
    expect(ios.status, DoctorStatus.problem);
    expect(ios.detail, contains('FLTEnableImpeller is false'));
    expect(ios.detail, isNot(contains('FLTEnableFlutterGPU')));
    expect(ios.fix, contains('ios/Runner/Info.plist'));

    final android = _named(checks, 'GPU key, Android');
    expect(android.status, DoctorStatus.problem);
    expect(android.detail, contains('EnableFlutterGPU'));
    expect(android.fix, contains('android/app/src/main/AndroidManifest.xml'));
    expect(android.fix, contains('<application>'));
  });

  test('a project that draws only in a browser needs no keys', () {
    // Mutation: gate on any GPU backend rather than on Impeller, and a
    // WebGL-only project is told to add keys nothing reads.
    expect(
      projectPlatformChecks(_app('missing', backend: 'flutter3d_webgl')),
      isEmpty,
    );
  });

  test('the doctor reports the keys of the project it runs in', () {
    // Mutation: leave `projectPlatformChecks` out of `runDoctorChecks`.
    final checks = runDoctorChecks(
      probe: (String _, List<String> _) => null,
      locate: (ExternalTool _) => null,
      dartVersion: '3.13.0',
      project: _app('missing'),
    );
    expect(_named(checks, 'GPU key, Android').status, DoctorStatus.problem);
  });
}
