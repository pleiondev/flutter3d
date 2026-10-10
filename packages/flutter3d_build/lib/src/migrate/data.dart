/// `flutter3d migrate --data`: the data files of a project moved to the
/// version this build writes, on disk.
///
/// **The engine reads every old version anyway.** A level from 0.8 opens in
/// 1.0 through its format's `lift` chain, every time it is read. What that
/// leaves is a project whose files are a release behind forever, and a tool
/// that does not carry the chain (a diff, a script, an older checkout of
/// the editor) sees a shape nobody writes any more. This writes each file
/// once in the shape the engine would write it, and says what it did.
///
/// **Which formats.** Every package of the engine that owns a format
/// declares a `FormatSpec`, and [engineFormats] adds those this package can
/// load to one `FormatSpecs`. The formats owned by a package that needs the
/// Flutter SDK cannot be loaded by a command-line tool; they are listed in
/// [formatsOutOfReach] with what reads them instead, so a file of one is
/// named in the report rather than mistaken for another format.
///
/// **What a lift is.** A JSON document goes through its spec's `lift` and
/// comes out in the envelope of the version this build writes, its legacy
/// version key gone and every key it had kept. A format whose reader does
/// part of the lifting itself is lifted by that reader instead
/// ([_readerLifts]). A format the engine keeps at an older version on
/// purpose stays there ([_keptBelow]). A file of a format that is not JSON
/// (a model, a shader bundle, a trace, the material language) carries its
/// version in its own header and is read as it is; the report counts them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_core/flutter3d_core.dart'
    show FrameCapture, f3dFormat, f3dmatFormat, f3dsplatFormat, fmatFormat;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/shader_bundle.dart' show ShaderBundle;
import 'package:flutter3d_hardware/trace.dart' show Trace;
import 'package:flutter3d_matter/flutter3d_matter.dart' show PhysicalMaterial;
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show projectFormat;
import 'package:flutter3d_particles/flutter3d_particles.dart'
    show EffectDocument;
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart'
    show DataPluginDocument;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        Demo,
        InputTape,
        Level,
        LevelVisibility,
        Lightmap,
        ShareBundle,
        Snapshot,
        TelemetryUpload;
import 'package:flutter3d_voxel/flutter3d_voxel.dart' show VoxelWorld;

import '../convert/report.dart' show convertReportFormat;
import '../manifest.dart' show AssetManifest;

/// The formats each package this command loads owns, by package: what
/// `migrate --data` and `doctor` know.
const Map<String, List<FormatSpec>> formatsByPackage =
    <String, List<FormatSpec>>{
      'flutter3d_core': <FormatSpec>[
        f3dFormat,
        fmatFormat,
        f3dmatFormat,
        f3dsplatFormat,
        FrameCapture.format,
      ],
      'flutter3d_hardware': <FormatSpec>[ShaderBundle.format, Trace.format],
      'flutter3d_model_core': <FormatSpec>[projectFormat],
      'flutter3d_sim': <FormatSpec>[
        Level.format,
        LevelVisibility.format,
        Lightmap.format,
        Demo.format,
        Snapshot.format,
        ShareBundle.format,
        InputTape.format,
        TelemetryUpload.format,
      ],
      'flutter3d_particles': <FormatSpec>[EffectDocument.format],
      'flutter3d_plugin_runtime': <FormatSpec>[DataPluginDocument.format],
      'flutter3d_matter': <FormatSpec>[PhysicalMaterial.format],
      'flutter3d_voxel': <FormatSpec>[VoxelWorld.format],
      'flutter3d_build': <FormatSpec>[AssetManifest.spec, convertReportFormat],
    };

/// A format of the engine this command cannot load, and what reads it.
typedef FormatOutOfReach = ({
  String id,
  String package,
  List<String> suffixes,
  String why,
});

/// The formats whose owning package this command cannot load. A test holds
/// this list and [formatsByPackage] to every `FormatSpec` the repository
/// declares.
const List<FormatOutOfReach> formatsOutOfReach = <FormatOutOfReach>[
  (
    id: 'f3d.settings',
    package: 'flutter3d_game',
    suffixes: <String>['.settings.json'],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.actions',
    package: 'flutter3d_game',
    suffixes: <String>['.actions.json'],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.saveSlots',
    package: 'flutter3d_game',
    suffixes: <String>[],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.cloudSaves',
    package: 'flutter3d_game',
    suffixes: <String>[],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.telemetryConsent',
    package: 'flutter3d_game',
    suffixes: <String>[],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.track',
    package: 'flutter3d_game_racing',
    suffixes: <String>['.track.json'],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.ghost',
    package: 'flutter3d_game_racing',
    suffixes: <String>['.ghost.json'],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.ghostTape',
    package: 'flutter3d_game_kit',
    suffixes: <String>['.best.json'],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.match',
    package: 'flutter3d_game_strategy',
    suffixes: <String>['.match.f3drun'],
    why: _flutterOwned,
  ),
  (
    id: 'f3d.conformance',
    package: 'flutter3d_conformance',
    suffixes: <String>['.conformance.json'],
    why:
        'a report of one conformance run, which nothing in a project reads '
        'back',
  ),
];

const String _flutterOwned =
    'its package needs the Flutter SDK, which a command-line tool cannot '
    'load; the game reads every version of it as it is';

/// Every format [formatsByPackage] names, in one registry.
FormatSpecs engineFormats() =>
    FormatSpecs(formatsByPackage.values.expand((List<FormatSpec> l) => l));

/// A reader that lifts what its format's chain does not: the level reader
/// turns overrides written by name (before version 3) into id paths once
/// the prefabs they walk are read, so a level is lifted by reading it and
/// writing it back. The level's digest is over what the reader reads, so
/// the runs recorded against it still match.
final Map<String, Map<String, Object?> Function(Map<String, Object?>)>
_readerLifts = <String, Map<String, Object?> Function(Map<String, Object?>)>{
  Level.format.id: (Map<String, Object?> document) => Level.fromJson(
    document,
    understands: <String>{
      if (document['requires'] case final List<Object?> requires)
        for (final name in requires) '$name',
    },
  ).toJson(),
};

/// Formats the engine still writes below their newest version on purpose:
/// the version under which a file stays, and why.
///
/// A run and a tape are written at the lowest version that says what they
/// hold, so a build from before a bump still plays every one it can play
/// correctly. Lifting one would only make those builds refuse it.
const Map<String, (int, String)> _keptBelow = <String, (int, String)>{
  'f3d.run': (
    5,
    'a run is written at the lowest version that holds what it records '
        '(5 only for change stamps or external inputs), so an older build '
        'still plays it; this build reads it and would write the same '
        'version',
  ),
  'f3d.inputTape': (
    2,
    'a version-1 tape is still what the engine writes for a tape with no '
        'axes, and one with button pairs is lifted by the game\'s '
        '`ActionSet.upgradeTape` when it is replayed, which knows the axes '
        'this command does not',
  ),
};

/// What happened to one data file.
typedef DataFileResult = ({
  /// The file, relative to the project, with `/` between directories.
  String path,
  String format,
  int from,
  int to,

  /// Why it was lifted the way it was, when it was not by the chain alone.
  String? note,
});

/// What `migrate --data` did and left.
final class DataMigration {
  /// Files lifted, or that would be on a dry run.
  final List<DataFileResult> lifted = <DataFileResult>[];

  /// Files already at the version this build writes, by format.
  final Map<String, int> current = <String, int>{};

  /// Files left as they are, each with why: a format out of reach, a file
  /// that is not JSON, a version newer than this build, a document of
  /// another format under this suffix.
  final List<({String path, String why})> notCarried =
      <({String path, String why})>[];

  /// Files of a format that is not JSON, by format: read as they are.
  final Map<String, int> unenveloped = <String, int>{};

  /// Backups written beside the files, relative to the project.
  final List<String> backups = <String>[];

  /// The report, a line per file lifted and per file not carried over.
  String describe({required bool dryRun}) {
    final out = StringBuffer()
      ..writeln(
        lifted.isEmpty
            ? 'Every data file is at the version this build writes.'
            : '${lifted.length} data '
                  '${lifted.length == 1 ? 'file' : 'files'} '
                  '${dryRun ? 'would be' : ''}${dryRun ? ' ' : ''}'
                  'lifted:',
      );
    for (final f in lifted) {
      out.writeln(
        '  ${f.path}: ${f.format} v${f.from} → v${f.to}'
        '${f.note == null ? '' : ' (${f.note})'}',
      );
    }
    if (current.isNotEmpty) {
      out.writeln(
        'Already current: ${(current.keys.toList()..sort()).map((String k) => '${current[k]} × $k').join(', ')}.',
      );
    }
    if (unenveloped.isNotEmpty) {
      out.writeln(
        'Read as they are, their version in their own header: '
        '${(unenveloped.keys.toList()..sort()).map((String k) => '${unenveloped[k]} × $k').join(', ')}.',
      );
    }
    if (notCarried.isNotEmpty) {
      out.writeln('Not carried over (${notCarried.length}):');
      for (final n in notCarried) {
        out.writeln('  ${n.path}: ${n.why}');
      }
    }
    if (backups.isNotEmpty) {
      out.writeln('Backups: ${backups.join(', ')}');
    }
    return out.toString().trimRight();
  }
}

/// The directories a walk of a project never enters: what a build or a tool
/// writes, and version control.
bool _skipped(String segment) =>
    segment.startsWith('.') ||
    segment == 'build' ||
    segment == 'node_modules' ||
    segment == 'Pods';

/// A test's fixture minted at one version on purpose: `test/fixtures/v3/`.
final RegExp _versionFixture = RegExp(r'(^|/)test/fixtures/v\d+/');

/// The files of [project] a registered or out-of-reach format claims by
/// suffix, sorted, with their paths relative to [project].
List<(String, File)> dataFilesIn(Directory project, FormatSpecs formats) {
  final root = project.absolute.path;
  final found = <(String, File)>[];
  void walk(Directory dir) {
    final entries = dir.listSync(followLinks: false)
      ..sort(
        (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
      );
    for (final entity in entries) {
      final name = entity.uri.pathSegments.lastWhere(
        (String s) => s.isNotEmpty,
      );
      if (entity is Directory) {
        if (!_skipped(name)) walk(entity);
      } else if (entity is File) {
        final relative = entity.absolute.path
            .substring(root.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        if (_versionFixture.hasMatch(relative)) continue;
        if (formats.forPath(relative) != null ||
            _outOfReachFor(relative) != null) {
          found.add((relative, entity));
        }
      }
    }
  }

  walk(project.absolute);
  return found;
}

/// The length of the longest of [suffixes] [path] ends in; 0 for none.
int _longestSuffix(List<String> suffixes, String path) => suffixes
    .where((String s) => path.toLowerCase().endsWith(s.toLowerCase()))
    .fold(
      0,
      (int longest, String s) => s.length > longest ? s.length : longest,
    );

/// The out-of-reach format a file at [path] is saved as, when its suffix is
/// one of theirs, with the length of that suffix.
(FormatOutOfReach, int)? _outOfReachFor(String path) => formatsOutOfReach
    .map((FormatOutOfReach f) => (f, _longestSuffix(f.suffixes, path)))
    .where(((FormatOutOfReach, int) match) => match.$2 > 0)
    .firstOrNull;

/// [document], a [spec] document written at [from], in the shape this build
/// writes: lifted, in the envelope of [FormatSpec.version], its legacy
/// version key gone and the rest of its keys after the envelope in the
/// order they came.
Map<String, Object?> currentDocument(
  FormatSpec spec,
  Map<String, Object?> document, {
  required int from,
}) {
  if (_readerLifts[spec.id] case final lift?) return lift(document);
  final lifted = spec.lift(<String, Object?>{...document}, from: from);
  return <String, Object?>{
    ...spec.envelope(
      requires: <String>[
        if (document['requires'] case final List<Object?> requires)
          for (final name in requires) '$name',
      ],
      generator: switch (document['generator']) {
        final String generator => generator,
        _ => FormatSpec.defaultGenerator,
      },
    ),
    for (final MapEntry(:key, :value) in lifted.entries)
      if (!FormatSpec.envelopeKeys.contains(key) &&
          key != spec.legacyVersionKey)
        key: value,
  };
}

/// How a lifted document is written: two spaces, a newline at the end.
String encodeDocument(Map<String, Object?> document) =>
    '${const JsonEncoder.withIndent('  ').convert(document)}\n';

/// Each data file of [project] lifted to the version this build writes, in
/// place unless [dryRun]; with [backup], the file as it was is kept beside
/// it as `<name>.v<N>.bak` first.
///
/// [formats] is [engineFormats] unless a test hands another registry.
DataMigration migrateData(
  Directory project, {
  FormatSpecs? formats,
  bool dryRun = false,
  bool backup = false,
}) {
  final registry = formats ?? engineFormats();
  final result = DataMigration();
  for (final (path, file) in dataFilesIn(project, registry)) {
    final spec = registry.forPath(path);
    final away = _outOfReachFor(path);
    // The longer suffix decides, as it would between two registered ones:
    // a strategy match ends in `.f3drun` too.
    if (away case (
      final format,
      final length,
    ) when length > _longestSuffix(spec?.suffixes ?? const <String>[], path)) {
      result.notCarried.add((path: path, why: '${format.id}: ${format.why}'));
      continue;
    }
    if (spec == null) continue;
    if (!spec.enveloped) {
      result.unenveloped[spec.id] = (result.unenveloped[spec.id] ?? 0) + 1;
      continue;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      // A YAML manifest is no JSON, and is at its only version; a broken
      // JSON file is the reader's to refuse, not this command's to guess.
      if (!path.endsWith('.json') && spec.version == spec.since) {
        result.current[spec.id] = (result.current[spec.id] ?? 0) + 1;
      } else {
        result.notCarried.add((
          path: path,
          why: '${spec.id}: not a JSON document',
        ));
      }
      continue;
    } on FileSystemException catch (error) {
      result.notCarried.add((path: path, why: error.message));
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      result.notCarried.add((path: path, why: '${spec.id}: not a JSON object'));
      continue;
    }
    if (decoded['format'] case final Object said
        when said is! String || !spec.claims(decoded)) {
      result.notCarried.add((
        path: path,
        why: 'a "$said" document under a ${spec.id} suffix: left alone',
      ));
      continue;
    }
    final from = spec.versionOf(decoded);
    if (from > spec.version) {
      result.notCarried.add((
        path: path,
        why:
            '${spec.id} v$from is newer than this build writes '
            '(v${spec.version}): left alone',
      ));
      continue;
    }
    if (from < spec.since || from < 1) {
      result.notCarried.add((
        path: path,
        why:
            '${spec.id} v$from is older than this build reads '
            '(v${spec.since} and up)',
      ));
      continue;
    }
    if (_keptBelow[spec.id] case (final below, final why) when from < below) {
      result.notCarried.add((path: path, why: '${spec.id} v$from kept: $why'));
      continue;
    }
    // At the version this build writes, the file is what it reads; a
    // document from before the envelope at its format's only version is
    // left as it is too, since nothing in it is behind.
    if (from == spec.version) {
      result.current[spec.id] = (result.current[spec.id] ?? 0) + 1;
      continue;
    }
    final Map<String, Object?> lifted;
    try {
      lifted = currentDocument(spec, decoded, from: from);
    } on Flutter3dFormatException catch (error) {
      result.notCarried.add((
        path: path,
        why: '${spec.id} v$from: ${error.message}',
      ));
      continue;
    }
    result.lifted.add((
      path: path,
      format: spec.id,
      from: from,
      to: spec.version,
      note: _readerLifts.containsKey(spec.id)
          ? 'read and written by the ${spec.id} reader'
          : null,
    ));
    if (dryRun) continue;
    if (backup) {
      final kept = '${file.path}.v$from.bak';
      file.copySync(kept);
      result.backups.add('$path.v$from.bak');
    }
    file.writeAsStringSync(encodeDocument(lifted));
  }
  return result;
}

/// The markers the generated table of data formats sits between in the
/// migration guide.
const String dataGuideStart = '<!-- data-formats:start -->';
const String dataGuideEnd = '<!-- data-formats:end -->';

/// The Markdown between [dataGuideStart] and [dataGuideEnd]: every format
/// of the engine, the versions this build reads, and what `migrate --data`
/// does with a file of it.
String generateDataGuide() {
  String suffixes(List<String> list) =>
      list.isEmpty ? '—' : list.map((String s) => '`$s`').join(', ');
  String how(FormatSpec spec) => switch (spec) {
    _ when !spec.enveloped => 'read as it is: its version is in its own header',
    _ when _keptBelow.containsKey(spec.id) =>
      'kept below v${_keptBelow[spec.id]!.$1}, at the lowest version that '
          'holds it',
    _ when spec.version == spec.since => 'nothing to lift',
    _ when _readerLifts.containsKey(spec.id) =>
      'lifted to v${spec.version} by its reader',
    _ => 'lifted to v${spec.version} through its chain',
  };
  final rows = <String>[
    for (final MapEntry(key: package, value: specs) in formatsByPackage.entries)
      for (final spec in specs)
        '| `${spec.id}` | ${suffixes(spec.suffixes)} | `$package` | '
            '${spec.since == spec.version ? 'v${spec.version}' : 'v${spec.since}–v${spec.version}'} | '
            '${how(spec)} |',
    for (final away in formatsOutOfReach)
      '| `${away.id}` | ${suffixes(away.suffixes)} | `${away.package}` | '
          'every version | left as it is: '
          '${away.why == _flutterOwned ? 'its package needs Flutter, and the game reads every version' : away.why} |',
  ];
  return <String>[
    dataGuideStart,
    '',
    '*Generated from the `FormatSpec`s `migrate --data` loads — '
        '${formatsByPackage.values.fold(0, (int n, List<FormatSpec> l) => n + l.length)} '
        'formats, and ${formatsOutOfReach.length} it leaves to the package '
        'that reads them.*',
    '',
    '| Format | Files | Package | This build reads | `migrate --data` |',
    '|---|---|---|---|---|',
    ...rows,
    '',
    dataGuideEnd,
  ].join('\n');
}

/// The data files of [project] below the version this build writes, as
/// `doctor` reports them: `path (format vN, current vM)`.
List<String> dataFilesBehind(
  Directory project, {
  FormatSpecs? formats,
}) => <String>[
  for (final f in migrateData(project, formats: formats, dryRun: true).lifted)
    '${f.path} (${f.format} v${f.from}, current v${f.to})',
];
