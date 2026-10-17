/// `doctor` on a project's shaders (D15, D19): the hook, the asset line,
/// the bundle's SDK and the plugins' materials.
///
///     dart test test/doctor_shaders_test.dart
///
/// Mutation: compare only the engine revision in `_bundleCheck`, and a
/// bundle compiled by another Dart reads as current.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/cli.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:test/test.dart';

const String _glow =
    'material AcmeGlow {\n  fragment {\n    return vec4(albedo, alpha);\n  }\n}\n';

/// A workspace of the application, a GPU backend and a plugin package with
/// a material, resolved the way `pub get` writes it.
Directory _workspace({String hook = '', String assets = ''}) {
  final root = Directory.systemTemp.createTempSync('f3d_doctor_');
  addTearDown(() => root.deleteSync(recursive: true));
  void package(String name, String pubspec) =>
      File('${root.path}/packages/$name/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: $name\n$pubspec');
  package('app', '''
dependencies:
  flutter3d_impeller: any
  acme: any
$assets''');
  package('flutter3d_impeller', '');
  package('acme', '''
flutter3d_plugins:
  plugin: acme.dart#AcmePlugin
''');
  File('${root.path}/packages/acme/assets_src/glow.f3dmat')
    ..createSync(recursive: true)
    ..writeAsStringSync(_glow);
  if (hook.isNotEmpty) {
    File('${root.path}/packages/app/hook/build.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(hook);
  }
  File('${root.path}/packages/app/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          for (final name in <String>['app', 'flutter3d_impeller', 'acme'])
            <String, Object?>{
              'name': name,
              'rootUri': '../../$name',
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  return Directory('${root.path}/packages/app');
}

void _bundle(Directory app, {required String dart, String engine = 'e1'}) {
  final bytes = EngineBundleStamp(dart: dart, engine: engine, stages: 1)
      .bundle(
        stages: const <ShaderBundleStage>[
          ShaderBundleStage('Pbr', fragment: true),
        ],
        sections: <String, ByteData>{ShaderBundle.impellerSection: ByteData(4)},
      )
      .encode();
  File('${app.path}/${EngineBundleStamp.projectAsset}')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

DoctorCheck _named(List<DoctorCheck> checks, String name) =>
    checks.singleWhere((check) => check.name == name);

const String _hook = '''
import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:hooks/hooks.dart';

void main(List<String> arguments) async {
  await build(arguments, buildAssets);
}
''';

void main() {
  test('a project without the hook is told what it loads instead', () {
    final checks = projectShaderChecks(_workspace(), dart: '3.13.0');
    expect(_named(checks, 'Shader hook').status, DoctorStatus.note);
    expect(_named(checks, 'Shader hook').detail, contains('ships'));
  });

  test('a hook whose output the pubspec does not ship is a problem', () {
    final checks = projectShaderChecks(_workspace(hook: _hook), dart: '3.13.0');
    expect(_named(checks, 'Shader hook').status, DoctorStatus.ok);
    expect(_named(checks, 'Shader assets').status, DoctorStatus.problem);
    expect(_named(checks, 'Shader bundle').detail, 'not built yet');
    expect(_named(checks, 'Plugin materials').detail, contains('glow.f3dmat'));
  });

  test('a bundle from another SDK is a problem, a current one is ok', () {
    final app = _workspace(
      hook: _hook,
      assets: 'flutter:\n  assets:\n    - flutter3d_generated/shaders/\n',
    );
    _bundle(app, dart: '3.12.0');
    var checks = projectShaderChecks(app, dart: '3.13.0', engineRevision: 'e1');
    expect(_named(checks, 'Shader assets').status, DoctorStatus.ok);
    expect(_named(checks, 'Shader bundle').status, DoctorStatus.problem);
    expect(_named(checks, 'Shader bundle').detail, contains('Dart 3.12.0'));

    _bundle(app, dart: '3.13.0');
    checks = projectShaderChecks(app, dart: '3.13.0', engineRevision: 'e2');
    expect(_named(checks, 'Shader bundle').detail, contains('engine e1'));

    checks = projectShaderChecks(app, dart: '3.13.0', engineRevision: 'e1');
    expect(_named(checks, 'Shader bundle').status, DoctorStatus.ok);

    File(
      '${app.path}/${EngineBundleStamp.projectMaterialAsset('AcmeGlow')}',
    ).writeAsStringSync('compiled');
    checks = projectShaderChecks(app, dart: '3.13.0', engineRevision: 'e1');
    expect(checks.where((c) => c.name == 'Plugin materials'), isEmpty);
  });
}
