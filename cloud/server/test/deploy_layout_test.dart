/// The deploy script, the unit and the service, held to one idea of where the
/// tutorial lives.
///
///     dart test test/deploy_layout_test.dart
///
/// Three files in three languages have to agree, and none of them can see the
/// others: `tool/deploy.sh` copies the Markdown somewhere, the systemd unit
/// tells the service where that was, and the service reads it from there.
/// When they did not agree the result was not an error. The tutorial's routes
/// read a path relative to the working directory, the deploy copied no Markdown
/// at all, and an absent directory is an empty tutorial by design, so the
/// server would have answered 200 with an index that listed nothing.
library;

import 'dart:io';

import 'package:flutter3d_models/src/config.dart';
import 'package:flutter3d_models/src/content/learn_content.dart';
import 'package:test/test.dart';

const _minimum = <String, String>{
  'MODELS_BASE_URL': 'https://models.example',
  'MODELS_DATABASE_URL': 'postgres://nobody@127.0.0.1/none',
  'MODELS_BLOB_DIR': '/tmp/none',
  'MODELS_SECRET': 'a-secret',
};

String _line(String file, Pattern match) => File(file)
    .readAsLinesSync()
    .firstWhere((line) => line.contains(match), orElse: () => '');

void main() {
  group('where the service looks', () {
    test('is the checkout\'s own directory when nothing says otherwise', () {
      final config = Config.fromEnvironment(_minimum);
      expect(config.learnDirectory, 'content/learn/modeler');
      expect(learnDirectoryProblem(config.learnDirectory), isNull);
    });

    test('is wherever MODELS_LEARN_DIR says', () {
      final config = Config.fromEnvironment(<String, String>{
        ..._minimum,
        'MODELS_LEARN_DIR': '/opt/flutter3d-models/learn',
      });
      expect(config.learnDirectory, '/opt/flutter3d-models/learn');
    });
  });

  group('a place with no tutorial in it', () {
    test('is named in a sentence, with the directory that was tried', () {
      final problem = learnDirectoryProblem('content/nothing-here');
      expect(problem, contains('nothing-here'));
      expect(problem, contains('MODELS_LEARN_DIR'));
    });

    test('and so is one that exists and holds no case', () {
      final empty = Directory.systemTemp.createTempSync('learn-empty');
      addTearDown(() => empty.deleteSync(recursive: true));
      expect(learnDirectoryProblem(empty.path), contains('no .md file'));
    });
  });

  group('the deploy', () {
    // Read as text, the way `tool/structure.dart` reads the repository: the
    // claim is about what three files say, and running a deploy to find out is
    // not something a test does.
    final unit = _line(
      '../deploy/flutter3d-models.service',
      'Environment=MODELS_LEARN_DIR=',
    );
    final served = unit.split('MODELS_LEARN_DIR=').last.trim();

    test('tells the service where the tutorial is, by an absolute path', () {
      expect(unit, isNotEmpty, reason: 'the unit sets no MODELS_LEARN_DIR');
      expect(served, startsWith('/'));
    });

    test('and copies the Markdown to that same place', () {
      final script = File('../tool/deploy.sh').readAsStringSync();
      final target = RegExp(
        r'target="\$\{MODELS_PATH:-([^}]+)\}"',
      ).firstMatch(script)?.group(1);
      expect(target, isNotNull);

      final copied = RegExp(
        r'rsync [^\n]*server/content/learn/modeler/" "\$host:\$target/([a-z/]+)"',
      ).firstMatch(script)?.group(1);
      expect(
        copied,
        isNotNull,
        reason: 'nothing copies content/learn/modeler to the server',
      );
      expect('$target/${copied!.replaceAll(RegExp(r'/$'), '')}', served);
    });

    test('from the directory the service reads in a checkout', () {
      // The source of the copy and the default of the setting are the same
      // path written in two places. One moving without the other is a server
      // with last month's tutorial on it.
      final script = File('../tool/deploy.sh').readAsStringSync();
      expect(
        script,
        contains('server/${Config.fromEnvironment(_minimum).learnDirectory}/'),
      );
    });
  });
}
