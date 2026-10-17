import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:flutter3d_build/src/project_model.dart' show viewerModelGlb;
import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_project_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('a new project: the app, assets_src, and the build hook wired', () {
    final target = '${scratch.path}/marble_run';
    final answer = createProject(target, 'marble_run');
    expect(answer.did, isTrue, reason: answer.says);
    expect(
      File('$target/lib/main.dart').readAsStringSync(),
      contains('Scene3D'),
    );
    expect(Directory('$target/assets_src').existsSync(), isTrue);
    expect(File('$target/hook/build.dart').existsSync(), isTrue);
    final pubspec = File('$target/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('name: marble_run'));
    expect(pubspec, contains('flutter3d_build'));
  });

  test('a viewer: Flutter3dView with an orbit, and a model in assets_src', () {
    final target = '${scratch.path}/trophy_view';
    final answer = createProject(
      target,
      'trophy_view',
      kind: ProjectKind.viewer,
    );
    expect(answer.did, isTrue, reason: answer.says);
    final main = File('$target/lib/main.dart').readAsStringSync();
    expect(main, contains('Flutter3dView('));
    expect(main, contains('OrbitController('));
    expect(main, contains("'assets_src/model.glb'"));
    final model = File('$target/assets_src/model.glb').readAsBytesSync();
    // A GLB: the magic, then version 2.
    expect(String.fromCharCodes(model.take(4)), 'glTF');
    expect(model[4], 2);
    expect(File('$target/test/widget_test.dart').existsSync(), isTrue);
    expect(File('$target/hook/build.dart').existsSync(), isTrue);
  });

  test('the viewer model decodes into three named parts', () async {
    final document = await GltfLoader().load(viewerModelGlb());
    expect(
      document.nodes.map((ModelNode n) => n.name),
      containsAll(<String>['base', 'ring', 'gem']),
    );
    expect(document.surfaces, hasLength(3));
  });

  test('an arcade: a Flame game owning a 3D world through the bridge', () {
    final target = '${scratch.path}/orb_catch';
    final answer = createProject(target, 'orb_catch', kind: ProjectKind.arcade);
    expect(answer.did, isTrue, reason: answer.says);
    final main = File('$target/lib/main.dart').readAsStringSync();
    expect(main, contains('Flutter3dFlameWidget('));
    expect(main, contains('with HasFlutter3d'));
    final pubspec = File('$target/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('flame_flutter3d:'));
    expect(pubspec, contains('flame:'));
    expect(File('$target/test/widget_test.dart').existsSync(), isTrue);
  });

  test('a kind is named on the command line, and an unknown one refused', () {
    expect(ProjectKind.named('viewer'), ProjectKind.viewer);
    expect(ProjectKind.named('arcade'), ProjectKind.arcade);
    expect(ProjectKind.named('scene'), ProjectKind.scene);
    expect(
      () => ProjectKind.named('rpg'),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}',
          'message',
          contains('scene, viewer, arcade'),
        ),
      ),
    );
  });

  test('create project --kind writes that kind, and a bad kind is a usage '
      'error', () async {
    final target = '${scratch.path}/kinds';
    expect(
      await runFlutter3d(<String>['create', 'project', target, '--kind=rpg']),
      CliExit.usage,
    );
    expect(Directory(target).existsSync(), isFalse);
    expect(
      await runFlutter3d(<String>[
        'create',
        'project',
        target,
        '--kind',
        'viewer',
      ]),
      CliExit.ok,
    );
    expect(File('$target/assets_src/model.glb').existsSync(), isTrue);
  });

  test('a directory with something in it is left alone', () {
    File('${scratch.path}/keep.txt').writeAsStringSync('mine');
    final answer = createProject(scratch.path, 'game');
    expect(answer.did, isFalse);
    expect(answer.says, contains('not empty'));
  });

  test('a name that is not a package name is refused before anything is '
      'written', () {
    expect(isPackageName('Marble-Run'), isFalse);
    expect(isPackageName('marble_run'), isTrue);
    final answer = createProject('${scratch.path}/x', 'Marble-Run');
    expect(answer.did, isFalse);
    expect(Directory('${scratch.path}/x').existsSync(), isFalse);
  });
}
