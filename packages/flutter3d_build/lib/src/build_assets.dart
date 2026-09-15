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

import 'package:crypto/crypto.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:hooks/hooks.dart';

import 'convert.dart';
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
  });

  final String hash;
  final int formatVersion;
  final int pipelineVersion;

  factory _CacheEntry.fromJson(Map<String, Object?> json) => _CacheEntry(
    hash: json['hash']! as String,
    formatVersion: json['formatVersion']! as int,
    pipelineVersion: json['pipelineVersion']! as int,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'hash': hash,
    'formatVersion': formatVersion,
    'pipelineVersion': pipelineVersion,
  };

  bool matches(_CacheEntry other) =>
      hash == other.hash &&
      formatVersion == other.formatVersion &&
      pipelineVersion == other.pipelineVersion;
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
Future<AssetBuildReport> runAssetBuild(
  Directory projectRoot, {
  IOSink? log,
}) async {
  final layout = AssetLayout(projectRoot: projectRoot);
  final plan = layout.plan();
  final cachePath = _cachePath(layout);
  final previous = _readCache(cachePath);
  final next = <String, _CacheEntry>{};

  final converted = <String>[];
  final skipped = <String>[];
  final sink = log ?? stdout;

  for (final job in plan) {
    final bytes = File(job.source).readAsBytesSync();
    final entry = _CacheEntry(
      hash: sha256.convert(bytes).toString(),
      formatVersion: kF3dVersion,
      pipelineVersion: kAssetPipelineVersion,
    );
    next[job.source] = entry;

    final unchanged = previous[job.source]?.matches(entry) ?? false;
    if (unchanged && File(job.destination).existsSync()) {
      skipped.add(job.source);
      continue;
    }

    final ok = await convertOne(job.source, job.destination, sink, sink);
    if (ok) converted.add(job.source);
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

  final report = await runAssetBuild(projectRoot);
  for (final source in report.dependencies) {
    output.dependencies.add(Uri.file(source));
  }
}
