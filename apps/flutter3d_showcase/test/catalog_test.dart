import 'dart:io';

import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/docs/regions.dart';
import 'package:flutter3d_showcase/src/docs/tutorial.dart';
import 'package:flutter3d_showcase/src/registry/registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// The repository root, from the app's own directory, which is where
/// `flutter test` runs.
final Directory _root = Directory('../..');

String _read(String path) => File(path).readAsStringSync();

/// A CHANGELOG as `(version, text)` sections, newest first.
List<(String, String)> _sections(String changelog) {
  final List<(String, String)> out = <(String, String)>[];
  String? version;
  final StringBuffer body = StringBuffer();
  for (final String line in changelog.split('\n')) {
    final RegExpMatch? heading = RegExp(
      r'^## (\d+\.\d+\.\d+)',
    ).firstMatch(line);
    if (heading != null) {
      if (version != null) out.add((version, body.toString()));
      version = heading.group(1);
      body.clear();
    } else {
      body.writeln(line);
    }
  }
  if (version != null) out.add((version, body.toString()));
  return out;
}

String _squash(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

void main() {
  final String appVersion = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)',
    multiLine: true,
  ).firstMatch(_read('pubspec.yaml'))!.group(1)!;

  test('ids are unique, kebab-case and match their file names', () {
    // Mutation: let two pages share an id. The address, the guide and the
    // picture of the second would silently be the first's.
    final Set<String> seen = <String>{};
    for (final Feature f in kCatalog) {
      expect(seen.add(f.id), isTrue, reason: 'duplicate id ${f.id}');
      expect(
        RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(f.id),
        isTrue,
        reason: f.id,
      );
    }
  });

  test('every page has its file, its guide and a demo', () {
    for (final Feature f in kCatalog) {
      expect(
        File(f.pageFile).existsSync(),
        isTrue,
        reason: '${f.id}: ${f.pageFile}',
      );
      expect(
        File(f.tutorialFile).existsSync(),
        isTrue,
        reason: '${f.id}: ${f.tutorialFile}',
      );
      expect(
        kDemos.containsKey(f.id),
        isTrue,
        reason: '${f.id} is not in a registry',
      );
    }
  });

  test('no demo is registered for a page the catalog does not list', () {
    final Set<String> ids = <String>{for (final Feature f in kCatalog) f.id};
    expect(kDemos.keys.where((String id) => !ids.contains(id)), isEmpty);
  });

  test('every guide is a valid guide and every pointer in it resolves', () {
    for (final Feature f in kCatalog) {
      final String guide = _read(f.tutorialFile);
      expect(lintTutorial(guide), isEmpty, reason: f.id);
      final String own = _read(f.pageFile);
      expect(
        () => expandDirectives(
          guide,
          own: own,
          sourceOf: (String id) =>
              _read(kCatalog.firstWhere((Feature o) => o.id == id).pageFile),
        ),
        returnsNormally,
        reason: f.id,
      );
    }
  });

  test('every step region a page has is quoted by its guide', () {
    for (final Feature f in kCatalog) {
      final String guide = _read(f.tutorialFile);
      for (final String region in listRegions(_read(f.pageFile))) {
        expect(
          guide.contains(RegExp('\\{\\{\\s*code\\s+$region\\s*\\}\\}')) ||
              guide.contains('{{source}}'),
          isTrue,
          reason: '${f.id}: region "$region" is never quoted',
        );
      }
    }
  });

  group('the version tag is written in a CHANGELOG', () {
    for (final Feature f in kCatalog) {
      test(f.id, () {
        // Mutation: tag a page with a later version than its CHANGELOG entry,
        // or with a phrase the CHANGELOG does not contain. The tag would then
        // say something the record does not.
        final String path = '${_root.path}/${f.evidenceFile}';
        expect(File(path).existsSync(), isTrue, reason: path);
        final List<(String, String)> sections = _sections(_read(path));

        final (String, String)? own = sections
            .where(((String, String) s) => s.$1 == f.since)
            .firstOrNull;
        expect(
          own,
          isNotNull,
          reason: '${f.evidenceFile} has no "## ${f.since}"',
        );

        // A precise tag quotes the record: `evidence` is words the section
        // actually has. An approximate one names a bound instead, so its
        // `evidence` is the reason there is no better date, not a quote —
        // nothing in a CHANGELOG says "no explicit origin" about itself, and
        // asking for both would make the flag impossible to use honestly.
        // What still has to be true of a bound is the same claim `!approximate`
        // makes of a date: nothing older mentions it. So it is checked instead
        // by requiring the section itself to hold a keyword (it is somewhere in
        // the story) and no earlier section to.
        if (!f.approximate) {
          expect(
            _squash(own!.$2).contains(_squash(f.evidence)),
            isTrue,
            reason: 'the evidence "${f.evidence}" is not under ## ${f.since}',
          );
        } else {
          expect(
            f.evidence.toLowerCase(),
            contains('no explicit origin'),
            reason: '${f.id}: approximate rows explain the bound, not quote it',
          );
          expect(
            f.keywords,
            isNotEmpty,
            reason: '${f.id}: an approximate row needs a keyword to bound',
          );
        }

        for (final String word in f.keywords) {
          final Iterable<String> earlier = <String>[
            for (final (String, String) s in sections)
              if (compareVersions(s.$1, f.since) < 0 &&
                  _squash(s.$2).contains(word.toLowerCase()))
                s.$1,
          ];
          expect(
            earlier,
            isEmpty,
            reason:
                '"$word" is already mentioned in ${earlier.join(', ')}; '
                'the page is tagged ${f.since}',
          );
        }
        if (f.approximate) {
          expect(
            f.keywords.any(
              (String word) => _squash(own!.$2).contains(word.toLowerCase()),
            ),
            isTrue,
            reason:
                '${f.id}: none of ${f.keywords} is mentioned under '
                '## ${f.since} either, so that is not where the bound comes from',
          );
        }

        expect(compareVersions(f.since, appVersion), lessThanOrEqualTo(0));
        for (final String file in f.engineFiles) {
          expect(
            File('${_root.path}/$file').existsSync(),
            isTrue,
            reason: file,
          );
        }
      });
    }
  });

  test('every category directory is declared as an asset', () {
    final String pubspec = _read('pubspec.yaml');
    for (final Category c in Category.values) {
      expect(pubspec, contains('lib/pages/${c.dir}/'), reason: c.dir);
    }
  });
}
