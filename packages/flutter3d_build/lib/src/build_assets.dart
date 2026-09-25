/// `ap-05`: the hook itself — `buildAssets(input, output)`, the function a
/// project's own `hook/build.dart` calls (written there by `ap-10`).
///
/// **Planning and executing stay two different questions.** [AssetLayout]
/// (`ap-04`) already answers "what to convert and where" with no Flutter
/// object in sight; this file answers "did it change, and does converting
/// it again matter" — a content hash, not a modification time, because a
/// file touched but not changed (a checkout, a rebase, an editor that
/// rewrites on every save) must not look like a source that moved.
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:hooks/hooks.dart';

import 'convert.dart';
import 'device_classes.dart';
import 'layout.dart';
import 'pipeline_version.dart';

/// What one call to [runAssetBuild] did, for a hook's own log line and for
/// a test to assert against without parsing stdout.
final class AssetBuildReport {
  const AssetBuildReport({
    required this.converted,
    required this.skipped,
    required this.dependencies,
  });

  /// Source paths this run actually decoded and wrote — cache miss, new
  /// file, or a stamp that moved.
  final List<String> converted;

  /// Source paths this run left alone because the cache already agreed.
  final List<String> skipped;

  /// Every planned source, converted or not — what a hook declares to
  /// [HookOutputBuilder.dependencies] so the *next* invocation is asked for
  /// at all when one of them changes.
  final List<String> dependencies;
}

/// The cache entry for one source file — content hash plus both version
/// stamps, so either one moving is treated exactly like the content moving.
final class _CacheEntry {
  const _CacheEntry({
    required this.hash,
    required this.formatVersion,
    required this.pipelineVersion,
    required this.textures,
    required this.lods,
  });

  final String hash;
  final int formatVersion;
  final int pipelineVersion;

  /// Which compression family the cached output was written with — `gfx-69n`.
  ///
  /// The source bytes and the pipeline version say nothing about it, so a build
  /// that changed family would otherwise find every file "unchanged" and ship
  /// the previous family's textures. Defaulted when absent so a cache written
  /// before this field is read rather than thrown away — it then mismatches
  /// once, which is the right amount of rebuilding.
  final String textures;

  /// Which level-of-detail ratios the manifest asked for — `C5` — and
  /// whether an impostor ends them — `C4`. A rule that gains or changes either
  /// changes nothing about the source's bytes, so without this the old file
  /// would stand.
  final String lods;

  factory _CacheEntry.fromJson(Map<String, Object?> json) => _CacheEntry(
    hash: json['hash']! as String,
    formatVersion: json['formatVersion']! as int,
    pipelineVersion: json['pipelineVersion']! as int,
    textures: json['textures'] as String? ?? '(unrecorded)',
    lods: json['lods'] as String? ?? '',
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'hash': hash,
    'formatVersion': formatVersion,
    'pipelineVersion': pipelineVersion,
    'textures': textures,
    'lods': lods,
  };

  bool matches(_CacheEntry other) =>
      hash == other.hash &&
      formatVersion == other.formatVersion &&
      pipelineVersion == other.pipelineVersion &&
      textures == other.textures &&
      lods == other.lods;
}

/// One file a planned source becomes: the single `.f3d`, or one class's.
final class _Target {
  const _Target({
    required this.key,
    required this.destination,
    required this.lods,
    required this.impostor,
    required this.stamp,
    this.impostorCell = 64,
    this.maxTextureSide,
  });

  /// The cache key: the source path, plus `#class` for a class's file.
  final String key;
  final String destination;
  final List<double> lods;
  final bool impostor;
  final int impostorCell;
  final int? maxTextureSide;

  /// The class budget's own stamp, appended to the cache entry's `lods`;
  /// empty for the single file, whose entry is spelled as it always was.
  final String stamp;
}

String _cachePath(AssetLayout layout) =>
    '${layout.generatedDir.path}/.flutter3d_cache.json';

Map<String, _CacheEntry> _readCache(String path) {
  final file = File(path);
  if (!file.existsSync()) return const <String, _CacheEntry>{};
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return <String, _CacheEntry>{
      for (final entry in json.entries)
        entry.key: _CacheEntry.fromJson(entry.value! as Map<String, Object?>),
    };
  } on FormatException {
    // A cache nobody can read is a cache that has nothing in it — the
    // conservative failure, since it converts everything rather than
    // trusting a stamp it cannot make sense of.
    return const <String, _CacheEntry>{};
  }
}

void _writeCache(String path, Map<String, _CacheEntry> cache) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(
    jsonEncode(<String, Object?>{
      for (final entry in cache.entries) entry.key: entry.value.toJson(),
    }),
  );
}

/// Runs the whole pipeline once against [projectRoot]: plans with
/// [AssetLayout], converts what the cache says changed, skips what it
/// says did not, and reports both.
///
/// Kept apart from [buildAssets] so a test can call it against a plain
/// [Directory] rather than a [BuildInput] — the object a real `hook/
/// build.dart` invocation hands over, and the one thing here neither
/// `AssetLayout` nor a unit test needs to construct.
///
/// [deviceClasses] are the classes this build carries (`N7`), of those the
/// manifest's `classes:` names; null carries every one it names. A manifest
/// that names none writes the single `.f3d` whatever this says.
Future<AssetBuildReport> runAssetBuild(
  Directory projectRoot, {
  IOSink? log,
  TextureFamily textures = TextureFamily.auto,
  List<DeviceClass>? deviceClasses,
}) async {
  final layout = AssetLayout(projectRoot: projectRoot);
  final plan = layout.plan();
  final cachePath = _cachePath(layout);
  final previous = _readCache(cachePath);
  final next = <String, _CacheEntry>{};

  final converted = <String>[];
  final skipped = <String>[];
  final sink = log ?? stdout;

  final classes = layout.manifest.classes;
  final building = <DeviceClassBudget>[
    for (final budget in classes)
      if (deviceClasses == null || deviceClasses.contains(budget.deviceClass))
        budget,
  ];

  for (final job in plan) {
    final bytes = File(job.source).readAsBytesSync();
    final hash = sha256.convert(bytes).toString();
    final ruleLods = job.rule?.lods ?? const <double>[];
    final ruleImpostor = job.rule?.impostor ?? false;

    // **What a build carries is exactly what it wrote.** The generated
    // directory is bundled whole, so a file a previous build left for another
    // class — a phone's model after a web build, or the single `.f3d` from
    // before the project named classes — would ship with this one.
    if (classes.isNotEmpty) {
      for (final stale in <String>[
        job.destination,
        for (final c in DeviceClass.values)
          if (!building.any((b) => b.deviceClass == c))
            deviceClassDestination(job.destination, c),
      ]) {
        final file = File(stale);
        if (file.existsSync()) file.deleteSync();
      }
    }

    // One target per class, or the one file a project without classes has
    // always had — with the cache key and stamp it always had, so turning
    // this feature off is not a rebuild.
    final targets = classes.isEmpty
        ? <_Target>[
            _Target(
              key: job.source,
              destination: job.destination,
              lods: ruleLods,
              impostor: ruleImpostor,
              stamp: '',
            ),
          ]
        : <_Target>[
            for (final budget in building)
              _Target(
                key: '${job.source}#${budget.deviceClass.name}',
                destination: deviceClassDestination(
                  job.destination,
                  budget.deviceClass,
                ),
                lods: budget.lods ?? ruleLods,
                impostor: budget.impostor ?? ruleImpostor,
                impostorCell: budget.impostorCell,
                maxTextureSide: budget.textures.maxSide,
                stamp: ' ${budget.stamp}',
              ),
          ];

    var anyConverted = false;
    var allSkipped = true;
    for (final target in targets) {
      final entry = _CacheEntry(
        hash: hash,
        formatVersion: kF3dVersion,
        pipelineVersion: kAssetPipelineVersion,
        textures: textures.name,
        lods:
            '${target.lods.join(',')}${target.impostor ? ' impostor' : ''}'
            '${target.stamp}',
      );
      next[target.key] = entry;

      final unchanged = previous[target.key]?.matches(entry) ?? false;
      if (unchanged && File(target.destination).existsSync()) continue;
      allSkipped = false;

      final ok = await convertOne(
        job.source,
        target.destination,
        sink,
        sink,
        textures: textures,
        lods: target.lods,
        impostor: target.impostor,
        impostorCell: target.impostorCell,
        maxTextureSide: target.maxTextureSide,
      );
      if (ok) anyConverted = true;
    }
    if (anyConverted) converted.add(job.source);
    if (allSkipped) skipped.add(job.source);
  }

  _writeCache(cachePath, next);
  sink.writeln(
    'flutter3d_build: ${converted.length} converted, ${skipped.length} '
    'unchanged',
  );

  return AssetBuildReport(
    converted: converted,
    skipped: skipped,
    dependencies: <String>[for (final job in plan) job.source],
  );
}

/// The compression family the platform being built for guarantees —
/// `gfx-69n`, and `ap-09`'s own table.
///
/// **Not a guess about a device.** A block format is guaranteed by the
/// platform: every desktop GPU samples BC, and ETC2 is required by OpenGL ES
/// 3.0 and by Metal on every iOS device this engine runs on. Getting it wrong
/// is not a worse picture — `uploadTexture` refuses a format the device does
/// not sample and says so by name, and the material draws untextured — which
/// is exactly why this reads the target rather than picking a default.
///
/// **The web gets nothing**, and that is the one target where a guess would be
/// a guess: a browser is whatever machine it is running on, and `ap-09`'s
/// answer there is to ship both sets and choose at load time from the
/// context's extensions. Until that exists, a web build carries what it
/// carried.
///
/// Null is a build that names no target, and takes [TextureFamily.auto]:
/// `HookConfig.code` throws without a code configuration, `buildCodeAssets` is
/// the guard that says so, and a build that cannot see its target must not
/// invent one.
///
/// **A function over an `OS` rather than over a `BuildInput`**, because the
/// input cannot be built with a code configuration outside `code_assets`
/// itself — `CodeAssetBuildInputBuilder`, which holds `setupCode`, is not among
/// the symbols that library exports. This table is the part that can be got
/// wrong, so this is the part that is tested; the guard beside it is one read
/// of a documented flag.
TextureFamily familyForTargetOS(OS? targetOS) => switch (targetOS) {
  OS.macOS || OS.windows || OS.linux => TextureFamily.bc,
  OS.android || OS.iOS => TextureFamily.etc2,
  _ => TextureFamily.auto,
};

TextureFamily _familyForTarget(BuildInput input) => familyForTargetOS(
  input.config.buildCodeAssets ? input.config.code.targetOS : null,
);

/// `hook/build.dart`'s own body — what `ap-10` writes into a consumer's
/// project is a `main` that hands `arguments` and this function straight to
/// `package:hooks`' own `build()`.
///
/// ```dart
/// import 'package:flutter3d_build/flutter3d_build.dart';
/// import 'package:hooks/hooks.dart';
///
/// void main(List<String> arguments) async {
///   await build(arguments, buildAssets);
/// }
/// ```
Future<void> buildAssets(BuildInput input, BuildOutputBuilder output) async {
  // `packageRoot` is a directory `Uri` — its own path ends in `/`, and
  // `Directory.fromUri(...).path` keeps that trailing slash rather than
  // dropping it the way a hand-typed directory path never would. Every path
  // this hook builds from it (the cache file, a logged conversion line, a
  // declared dependency) would otherwise carry a doubled slash — harmless
  // to the OS, but not to a string comparison, and not to the cache's own
  // keys staying the same string across two different callers of this same
  // function. Found by a real end-to-end test, not by reading the API.
  final root = Directory.fromUri(input.packageRoot).path;
  final projectRoot = Directory(
    root.endsWith('/') ? root.substring(0, root.length - 1) : root,
  );

  // **Which family — `gfx-69n`.** A project's own word first: `textures: bc`
  // (or `etc2`, or `none`) under this package's key in its
  // `hook_user_defines`, which is also how `--textures` finally reaches the
  // application path. Failing that, the platform being built for.
  final requested = input.userDefines['textures'];
  final textures = requested is String
      ? TextureFamily.parse(requested) ?? _familyForTarget(input)
      : _familyForTarget(input);

  // **Which device classes — `N7`.** Only matters to a manifest that names
  // some. A project's own `deviceClasses: [web]` user define first, for a
  // build the target cannot tell apart; failing that, the target: a native
  // build carries the phone and desktop files, a web build the web's alone.
  final deviceClasses =
      parseDeviceClasses(input.userDefines['deviceClasses']) ??
      deviceClassesForTargetOS(
        input.config.buildCodeAssets ? input.config.code.targetOS : null,
      );

  final report = await runAssetBuild(
    projectRoot,
    textures: textures,
    deviceClasses: deviceClasses,
  );
  for (final source in report.dependencies) {
    output.dependencies.add(Uri.file(source));
  }
}
