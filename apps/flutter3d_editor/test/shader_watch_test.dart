/// The editor's shader watch, off the file system.
///
///     flutter test test/shader_watch_test.dart
///
/// What it holds: a bundle whose file has not moved is not read; one that has
/// is refreshed and the renderer told; a refusal is reported, keeps the
/// library, and is not retried until the file moves again — which is what
/// stops a broken bundle being re-read twice a second while somebody fixes
/// the shader.
library;

import 'dart:typed_data';

import 'package:flutter3d_editor/src/shader_watch.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

ByteData _bundle(String name) => ShaderBundle(
  name: name,
  sdk: '',
  stages: const <ShaderBundleStage>[
    ShaderBundleStage('Lambert', fragment: true),
  ],
).encode();

void main() {
  late FakeBackend device;
  late FakeLoadedShaderLibrary library;
  late DateTime? modified;
  late ByteData onDisk;
  final refreshed = <int>[];
  final refused = <ShaderBundleRefused>[];

  ShaderWatch watch() => ShaderWatch(
    library: library,
    modifiedAt: () => modified,
    readBytes: () async => onDisk,
    onRefreshed: () => refreshed.add(library.refreshes),
    onRefused: refused.add,
  );

  setUp(() async {
    device = FakeBackend();
    onDisk = _bundle('v1');
    modified = DateTime(2026, 9, 3, 10);
    library = await device.loadShaders(onDisk) as FakeLoadedShaderLibrary;
    refreshed.clear();
    refused.clear();
  });

  test('a file that has not moved is left alone', () async {
    final it = watch();
    expect(await it.poll(), isFalse);
    expect(await it.poll(), isFalse);
    expect(library.refreshes, 0);
    expect(refreshed, isEmpty);
  });

  test('a file that moved is read, refreshed, and the renderer told', () async {
    // Mutation: drop `onRefreshed()` from `poll` — the library is refreshed
    // and nothing relinks, which on screen is a reload that did nothing.
    final it = watch();
    onDisk = _bundle('v2');
    modified = DateTime(2026, 9, 3, 10, 1);
    expect(await it.poll(), isTrue);
    expect(library.name, 'v2');
    expect(refreshed, <int>[1]);
    // And not again until it moves again.
    expect(await it.poll(), isFalse);
    expect(library.refreshes, 1);
  });

  test('a refused bundle is reported, kept out, and not retried', () async {
    // Mutation: record `_seen` only on success — the broken file is read on
    // every poll and the bar fills with the same refusal.
    final it = watch();
    onDisk = ByteData(12);
    modified = DateTime(2026, 9, 3, 10, 2);
    expect(await it.poll(), isFalse);
    expect(refused, hasLength(1));
    expect(library.name, 'v1', reason: 'the previous bundle stays');
    expect(refreshed, isEmpty);

    expect(await it.poll(), isFalse);
    expect(refused, hasLength(1), reason: 'not retried until the file moves');

    // Fixed and written again: taken.
    onDisk = _bundle('v3');
    modified = DateTime(2026, 9, 3, 10, 3);
    expect(await it.poll(), isTrue);
    expect(library.name, 'v3');
  });

  test('no file yet is not a change', () async {
    final it = watch();
    modified = null;
    expect(await it.poll(), isFalse);
    expect(refused, isEmpty);
  });
}
