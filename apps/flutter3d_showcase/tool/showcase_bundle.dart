/// Writes what the documentation site needs to show the showcase's guides.
///
///     cd apps/flutter3d_showcase
///     dart run tool/showcase_bundle.dart --out ../../site/.generated/showcase
///
/// **The site never reads a page file itself.** It reads what this writes, and
/// this writes it with the same functions the app uses (`regions.dart`,
/// `tutorial.dart`), so a guide on the site quotes exactly the lines the Step by
/// step tab does, and a guide that points at a region that is not there stops
/// here, before a page is built, and not on a reader's screen.
///
/// The output, all of it deterministic (no dates), so a rebuild that changed
/// nothing changes no file:
///
///     manifest.json      the catalog, and per page its steps and regions
///     learn/<id>.md      the guide with every {{code …}} line expanded into a
///                        fenced dart block; {{demo}} and {{shot}} are left for
///                        the site to turn into a link and a picture
///     src/<id>.dart      the page's file with the region markers taken out
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/docs/regions.dart';
import 'package:flutter3d_showcase/src/docs/tutorial.dart';

const String _usage = '''
Usage: dart run tool/showcase_bundle.dart --out <directory>

  --out <dir>   where to write manifest.json, learn/ and src/ (created, and
                emptied of what an earlier run wrote there).
  -h, --help    this text.
''';

String _read(String path) => File(path).readAsStringSync();

/// The version in `pubspec.yaml`, without the build number.
String _appVersion() => RegExp(
  r'^version:\s*(\d+\.\d+\.\d+)',
  multiLine: true,
).firstMatch(_read('pubspec.yaml'))!.group(1)!;

Future<void> main(List<String> arguments) async {
  String? out;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      case '--out':
        out = arguments[++i];
      default:
        stderr.write('Unknown option ${arguments[i]}\n$_usage');
        exitCode = 64;
        return;
    }
  }
  if (out == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  if (!File('pubspec.yaml').existsSync() ||
      !_read('pubspec.yaml').contains('name: flutter3d_showcase')) {
    stderr.writeln('Run this from apps/flutter3d_showcase.');
    exitCode = 78;
    return;
  }

  final Directory target = Directory(out);
  if (target.existsSync()) target.deleteSync(recursive: true);
  Directory('${target.path}/learn').createSync(recursive: true);
  Directory('${target.path}/src').createSync(recursive: true);

  String sourceOf(String id) {
    final Feature? feature = featureNamed(id);
    if (feature == null) throw RegionError('no page called "$id"');
    return _read(feature.pageFile);
  }

  final List<String> failures = <String>[];
  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];

  for (final Feature feature in kCatalog) {
    try {
      final String guide = _read(feature.tutorialFile);
      final List<String> problems = lintTutorial(guide);
      if (problems.isNotEmpty) {
        failures.add('${feature.id}: ${problems.join('; ')}');
        continue;
      }
      final String page = _read(feature.pageFile);
      final List<Region> regions = parseRegions(page);

      File('${target.path}/learn/${feature.id}.md').writeAsStringSync(
        expandDirectives(guide, own: page, sourceOf: sourceOf),
      );
      final String shown = stripMarkers(page);
      File('${target.path}/src/${feature.id}.dart').writeAsStringSync(shown);

      entries.add(<String, Object?>{
        ...feature.toJson(),
        'steps': stepsOf(guide),
        'regions': <Map<String, Object?>>[
          for (final Region region in regions)
            <String, Object?>{
              'name': region.name,
              'title': region.title,
              // One-based, in the file as `src/<id>.dart` has it.
              'line': (strippedLineOf(page, region.name) ?? 0) + 1,
            },
        ],
        'lines': '\n'.allMatches(shown.trimRight()).length + 1,
        'github': 'apps/flutter3d_showcase/${feature.pageFile}',
      });
    } on RegionError catch (error) {
      failures.add('${feature.id}: $error');
    } on FileSystemException catch (error) {
      failures.add('${feature.id}: ${error.path} is missing');
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('The showcase bundle was not written:');
    for (final String failure in failures) {
      stderr.writeln('  $failure');
    }
    exitCode = 1;
    return;
  }

  final Map<String, Object?> manifest = <String, Object?>{
    'app': 'flutter3d_showcase',
    'version': _appVersion(),
    'categories': <Map<String, Object?>>[
      for (final Category category in Category.values)
        <String, Object?>{'dir': category.dir, 'title': category.title},
    ],
    'features': entries,
  };
  File('${target.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  stdout.writeln(
    'Wrote ${entries.length} pages to ${target.path} '
    '(version ${manifest['version']}).',
  );
}
