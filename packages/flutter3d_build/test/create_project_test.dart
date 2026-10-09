import 'dart:io';

import 'package:flutter3d_build/cli.dart';
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
