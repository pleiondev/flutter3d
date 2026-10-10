/// `ProjectRoot`: every path a file tool takes, held inside one directory.
///
///     dart test test/kit/project_root_test.dart
///
/// Each payload here is one a prompt could put in an agent's arguments. Each
/// test was written by breaking what it covers; the mutation is named.
library;

import 'dart:io';

import 'package:flutter3d_mcp/kit.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory project;
  late ProjectRoot root;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('project_root');
    project = Directory('${sandbox.path}/game')..createSync();
    Directory('${project.path}/levels').createSync();
    File('${sandbox.path}/secret.txt').writeAsStringSync('not yours');
    root = ProjectRoot(project.path);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Matcher refusedNaming(String requested) => throwsA(
    isA<PathOutsideRootException>()
        .having(
          (PathOutsideRootException e) => e.requested,
          'requested',
          requested,
        )
        .having(
          (PathOutsideRootException e) => e.message,
          'message',
          contains(root.path),
        ),
  );

  test('a relative path is read from the root, and folds its own dots', () {
    // Mutation: resolve against the working directory. A server started
    // from somewhere else writes the level somewhere else.
    expect(root.resolve('levels/a.json'), '${root.path}/levels/a.json');
    // Mutation: compare the text before folding `..`. A path that wanders
    // and comes back would be refused for nothing.
    expect(root.resolve('levels/../b.json'), '${root.path}/b.json');
    expect(root.resolve('./levels/./c.json'), '${root.path}/levels/c.json');
    // An absolute path inside is the same file.
    expect(
      root.resolve('${root.path}/levels/a.json'),
      '${root.path}/levels/a.json',
    );
  });

  test('a path that leaves by .. is refused', () {
    // Mutation: return the joined path without the inside check — the
    // payload reads the file beside the project.
    expect(() => root.resolve('../secret.txt'), refusedNaming('../secret.txt'));
    expect(
      () => root.resolve('levels/../../secret.txt'),
      refusedNaming('levels/../../secret.txt'),
    );
    expect(
      () => root.resolve('../../../../../../etc/passwd'),
      refusedNaming('../../../../../../etc/passwd'),
    );
  });

  test('an absolute path elsewhere is refused', () {
    // Mutation: take an absolute path as it is (the review's
    // `usd_input.dart` shape, here for the MCP tools).
    expect(() => root.resolve('/etc/passwd'), refusedNaming('/etc/passwd'));
    expect(
      () => root.resolve('${sandbox.path}/secret.txt'),
      refusedNaming('${sandbox.path}/secret.txt'),
    );
  });

  test('a sibling whose name starts with the root\'s is not inside it', () {
    // Mutation: test inside-ness with `startsWith` on the text. `game2`
    // starts with `game` and is somebody else's directory.
    Directory('${sandbox.path}/game2').createSync();
    expect(
      () => root.resolve('${sandbox.path}/game2/x.json'),
      refusedNaming('${sandbox.path}/game2/x.json'),
    );
  });

  test('a link inside that leads out is refused, a file through it too', () {
    Link('${project.path}/escape').createSync(sandbox.path);
    Link('${project.path}/levels/key').createSync('${sandbox.path}/secret.txt');
    // Mutation: skip resolving links. Both read `secret.txt`, and a write
    // through `escape/` lands beside the project.
    expect(
      () => root.resolve('escape/secret.txt'),
      refusedNaming('escape/secret.txt'),
    );
    expect(
      () => root.resolve('escape/new.json'),
      refusedNaming('escape/new.json'),
    );
    expect(() => root.resolve('levels/key'), refusedNaming('levels/key'));
  });

  test('a link that points nowhere is refused', () {
    Link('${project.path}/later').createSync('${sandbox.path}/not_yet');
    // Mutation: treat a dangling link as a file not written yet. The write
    // follows it out, to wherever it is pointed.
    expect(() => root.resolve('later'), refusedNaming('later'));
  });

  test('a link that stays inside is followed', () {
    Link('${project.path}/current').createSync('${project.path}/levels');
    expect(root.resolve('current/a.json'), '${root.path}/levels/a.json');
    // Mutation: judge the text before resolving links. A path that reaches
    // the root through a link of its own (`/var` for `/private/var` on
    // macOS, here `alias`) would be refused for a file that is inside.
    Link('${sandbox.path}/alias').createSync(project.path);
    expect(
      root.resolve('${sandbox.path}/alias/levels/a.json'),
      '${root.path}/levels/a.json',
    );
  });

  test('an empty path and one with a NUL are refused', () {
    // Mutation: drop the check. `''` resolves to the root itself, which a
    // write would try to replace; a NUL truncates the path in the OS call.
    expect(() => root.resolve(''), refusedNaming(''));
    expect(
      () => root.resolve('levels/a.json\u0000../../x'),
      refusedNaming('levels/a.json\u0000../../x'),
    );
  });

  test('tryResolve answers with the sentence instead of throwing', () {
    final ok = root.tryResolve('levels/a.json');
    expect(ok.path, '${root.path}/levels/a.json');
    expect(ok.refused, isNull);
    final no = root.tryResolve('/etc/passwd');
    expect(no.path, isNull);
    expect(no.refused, contains('"/etc/passwd" is refused'));
  });

  test('a document belongs to the nearest project above it, or its own '
      'directory', () {
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: game\n');
    // Mutation: take the document's own directory always. A level in
    // `assets/levels` could not save into `test/tapes` beside it.
    expect(ProjectRoot.around('${project.path}/levels/a.json').path, root.path);
    final loose = Directory('${sandbox.path}/loose')..createSync();
    expect(
      ProjectRoot.around('${loose.path}/a.json').path,
      ProjectRoot(loose.path).path,
    );
    expect(
      ProjectRoot.around(null).path,
      ProjectRoot(Directory.current.path).path,
    );
  });
}
