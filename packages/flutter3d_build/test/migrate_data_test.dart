/// `flutter3d migrate --data`: a project built from the oldest fixture of
/// every format comes out as the files this build writes.
///
///     dart test test/migrate_data_test.dart
///
/// The fixtures at each version are different documents (each newer one
/// shows what its version added), so the oldest lifted is compared byte for
/// byte with `test/fixtures/migrate_data/after/`, what the lift of each is;
/// the newest is compared byte for byte with itself, since a file at the
/// version this build writes is not touched. Set
/// `FLUTTER3D_UPDATE_MIGRATE_DATA=1` to rewrite the expected files after a
/// format gains a version, and read the diff.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/src/migrate/data.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;
import 'package:test/test.dart';

import '../../../tool/structure/detectors.dart' show formatSpecsIn;

final Directory _repository = Directory('../..').absolute;
final Directory _expected = Directory('test/fixtures/migrate_data/after');

/// Where [spec]'s fixture at [version] is, in [package]; null when there is
/// none.
File? _fixture(String package, FormatSpec spec, int version) {
  final pattern = spec.fixture;
  if (pattern == null) return null;
  final file = File(
    '${_repository.path}/packages/$package/'
    '${pattern.replaceAll('<N>', '$version')}',
  );
  return file.existsSync() ? file : null;
}

/// The name a fixture is saved under in the project: its own when it ends
/// in a suffix of its format, else its stem with the format's first suffix.
String _nameFor(FormatSpec spec, File fixture) {
  final name = fixture.uri.pathSegments.last;
  final lower = name.toLowerCase();
  if (spec.suffixes.any((String s) => lower.endsWith(s.toLowerCase()))) {
    return name;
  }
  final stem = name.contains('.') ? name.substring(0, name.indexOf('.')) : name;
  return '$stem${spec.suffixes.first}';
}

/// A project holding, for every format this command knows, its fixture at
/// the oldest version ([newest] false) or the newest: `data/<package>/…`.
/// Returns each file's path in the project with the format and version.
Map<String, (FormatSpec, int)> _project(
  Directory into, {
  required bool newest,
}) {
  final placed = <String, (FormatSpec, int)>{};
  for (final MapEntry(key: package, value: specs) in formatsByPackage.entries) {
    for (final spec in specs) {
      final versions = <int>[
        for (var v = spec.since; v <= spec.version; v++) v,
      ];
      for (final v in newest ? versions.reversed : versions) {
        final fixture = _fixture(package, spec, v);
        if (fixture == null) continue;
        final path = 'data/$package/${_nameFor(spec, fixture)}';
        File('${into.path}/$path')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(fixture.readAsBytesSync());
        placed[path] = (spec, v);
        break;
      }
    }
  }
  return placed;
}

Map<String, List<int>> _bytes(Directory project, Iterable<String> paths) =>
    <String, List<int>>{
      for (final p in paths) p: File('${project.path}/$p').readAsBytesSync(),
    };

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('migrate_data'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('every format the repository declares is lifted here or named as '
      'out of reach', () {
    // Mutation: add a `FormatSpec` to any package without listing it in
    // `formatsByPackage` or `formatsOutOfReach`, and this names its id.
    final declared = <String>{
      for (final dir in Directory(
        '${_repository.path}/packages',
      ).listSync().whereType<Directory>())
        if (Directory('${dir.path}/lib').existsSync())
          for (final file
              in Directory('${dir.path}/lib')
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((File f) => f.path.endsWith('.dart')))
            for (final spec in formatSpecsIn(file.readAsStringSync()))
              // The foundation's own doc comment shows how one is written.
              if (!file.path.endsWith(
                'flutter3d_foundation/lib/src/formats.dart',
              ))
                spec.id,
    };
    final known = <String>{
      for (final spec in engineFormats().all) spec.id,
      for (final away in formatsOutOfReach) away.id,
    };
    expect(declared, isNotEmpty);
    expect(known.difference(declared), isEmpty, reason: 'listed, not declared');
    expect(declared.difference(known), isEmpty, reason: 'declared, not listed');
  });

  test('the oldest fixture of every format comes out as the expected file, '
      'byte for byte', () {
    // Mutation: drop the envelope from `currentDocument`, or skip the level
    // reader's lift, and the files differ from the expected ones.
    final placed = _project(scratch, newest: false);
    final before = _bytes(scratch, placed.keys);
    final report = migrateData(scratch);
    final update = Platform.environment['FLUTTER3D_UPDATE_MIGRATE_DATA'] == '1';
    final lifted = <String>{for (final f in report.lifted) f.path};
    for (final path in placed.keys) {
      final after = File('${scratch.path}/$path');
      // A file that is not lifted is its fixture still.
      if (!lifted.contains(path)) {
        expect(after.readAsBytesSync(), before[path], reason: path);
        continue;
      }
      final expected = File(
        '${_expected.path}/${path.substring('data/'.length)}',
      );
      if (update) {
        expected
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(after.readAsBytesSync());
        continue;
      }
      expect(
        after.readAsBytesSync(),
        expected.readAsBytesSync(),
        reason: '$path against ${expected.path}',
      );
    }
    // Each JSON file below its format's version is reported: `vN → vM`, or
    // with why it stays.
    final text = report.describe(dryRun: false);
    final kept = <String>{for (final n in report.notCarried) n.path};
    for (final MapEntry(key: path, value: (spec, version)) in placed.entries) {
      if (!spec.enveloped || version == spec.version) continue;
      expect(
        kept.contains(path) ||
            text.contains('$path: ${spec.id} v$version → v${spec.version}'),
        isTrue,
        reason: '$path is not in the report:\n$text',
      );
    }
    expect(kept, <String>{'data/flutter3d_sim/input.tape.json'});
  });

  test('a lifted document reads as the old one did', () {
    // Mutation: lift with `spec.lift` from the wrong version, or let the
    // envelope drop a key the document had, and the two differ.
    final placed = _project(scratch, newest: false);
    final before = _bytes(scratch, placed.keys);
    final report = migrateData(scratch);
    expect(report.lifted, isNotEmpty);
    for (final lifted in report.lifted) {
      final path = lifted.path;
      final (spec, _) = placed[path]!;
      final old = _parse(utf8.decode(before[path]!));
      final now = _parse(File('${scratch.path}/$path').readAsStringSync());
      if (spec.id == Level.format.id) {
        // What a run recorded against the level is checked against.
        expect(
          Level.fromJson(now).digestHex,
          Level.fromJson(old).digestHex,
          reason: path,
        );
        continue;
      }
      Map<String, Object?> body(Map<String, Object?> d) => <String, Object?>{
        for (final MapEntry(:key, :value)
            in spec.open(d, refuse: DocumentFormatException.new).entries)
          if (!FormatSpec.envelopeKeys.contains(key) &&
              key != spec.legacyVersionKey)
            key: value,
      };
      expect(body(now), body(old), reason: path);
      expect(spec.versionOf(now), spec.version, reason: path);
      expect(now['format'], spec.id, reason: path);
    }
  });

  test('the newest fixture of every format is left byte for byte, and a '
      'second run changes nothing', () {
    // Mutation: rewrite a file already at its format's version, and its
    // bytes move.
    final placed = _project(scratch, newest: true);
    final before = _bytes(scratch, placed.keys);
    final report = migrateData(scratch);
    expect(report.lifted, isEmpty);
    expect(_bytes(scratch, placed.keys), before);

    final old = Directory('${scratch.path}/old')..createSync();
    final lifted = _project(old, newest: false).keys;
    expect(migrateData(old).lifted, isNotEmpty);
    final once = _bytes(old, lifted);
    expect(migrateData(old).lifted, isEmpty);
    expect(_bytes(old, lifted), once);
  });

  test('a dry run writes nothing, and a backup keeps the file as it was', () {
    // Mutation: write in a dry run, or back up after writing.
    final placed = _project(scratch, newest: false);
    final before = _bytes(scratch, placed.keys);
    final dry = migrateData(scratch, dryRun: true);
    expect(_bytes(scratch, placed.keys), before);
    expect(dry.lifted, isNotEmpty);
    expect(dry.describe(dryRun: true), contains('would be lifted'));

    final real = migrateData(scratch, backup: true);
    expect(real.backups, hasLength(real.lifted.length));
    for (final f in real.lifted) {
      expect(
        File('${scratch.path}/${f.path}.v${f.from}.bak').readAsBytesSync(),
        before[f.path],
      );
    }
  });

  test('what it cannot carry is named, and left alone', () {
    // Mutation: drop the out-of-reach check, and a strategy match is lifted
    // as a run.
    final files = <String, String>{
      'runs/skirmish.match.f3drun': '{"version": 1, "orders": []}\n',
      'levels/next.level.json': '{"format": "f3d.level", "version": 99}\n',
      'levels/odd.level.json': '{"format": "f3d.save", "version": 1}\n',
      'levels/broken.level.json': '{"format": \n',
      'tapes/old.tape.json': '{"seed": 3, "frames": []}\n',
    };
    for (final MapEntry(key: path, value: text) in files.entries) {
      File('${scratch.path}/$path')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    final report = migrateData(scratch);
    expect(report.lifted, isEmpty);
    final why = <String, String>{
      for (final n in report.notCarried) n.path: n.why,
    };
    expect(why['runs/skirmish.match.f3drun'], startsWith('f3d.match:'));
    expect(why['levels/next.level.json'], contains('newer than this build'));
    expect(why['levels/odd.level.json'], contains('"f3d.save" document'));
    expect(why['levels/broken.level.json'], contains('not a JSON document'));
    expect(why['tapes/old.tape.json'], contains('ActionSet.upgradeTape'));
    for (final MapEntry(key: path, value: text) in files.entries) {
      expect(File('${scratch.path}/$path').readAsStringSync(), text);
    }
  });

  test('a test fixture minted at one version on purpose is not touched', () {
    final fixture = File('${scratch.path}/test/fixtures/v1/first.level.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"version": 1, "name": "kept"}\n');
    expect(migrateData(scratch).lifted, isEmpty);
    expect(fixture.readAsStringSync(), '{"version": 1, "name": "kept"}\n');
  });

  test('doctor names the files behind', () {
    File('${scratch.path}/assets/first.level.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"version": 1, "name": "behind"}\n');
    expect(dataFilesBehind(scratch), <String>[
      'assets/first.level.json (f3d.level v1, current v${Level.formatVersion})',
    ]);
  });
}

/// A JSON object read from [text].
Map<String, Object?> _parse(String text) =>
    (jsonDecode(text) as Map<Object?, Object?>).cast<String, Object?>();
