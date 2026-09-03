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

import 'dart:io' show FileSystemException;
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

  late Future<ByteData> Function() read;

  ShaderWatch watch({DateTime? seen}) => ShaderWatch(
    library: library,
    seen: seen ?? modified,
    modifiedAt: () => modified,
    readBytes: () => read(),
    onRefreshed: () => refreshed.add(library.refreshes),
    onRefused: refused.add,
  );

  setUp(() async {
    device = FakeBackend();
    onDisk = _bundle('v1');
    modified = DateTime(2026, 9, 3, 10);
    read = () async => onDisk;
    library = await device.loadShaders(onDisk) as FakeLoadedShaderLibrary;
    refreshed.clear();
    refused.clear();
  });

  test('a write between the load and the watch is not missed', () async {
    // The bytes were read at ten o'clock; the file moved a minute later,
    // before the watch existed. Mutation: take `_seen` from `modifiedAt()`
    // in the constructor rather than from `seen` — the later write is
    // stamped as seen, and the library never reads it.
    onDisk = _bundle('v2');
    modified = DateTime(2026, 9, 3, 10, 1);
    final it = watch(seen: DateTime(2026, 9, 3, 10));
    expect(await it.poll(), isTrue);
    expect(library.name, 'v2');
  });

  test('a file that cannot be read is reported and waited out', () async {
    // The bundle is being replaced — removed, not yet written — when the
    // poll reads it. Mutation: drop the `on FileSystemException` in `poll`
    // and the error escapes the timer with nothing to catch it. Recorded as
    // seen, because the write that finishes moves the time again.
    final it = watch();
    read = () => throw const FileSystemException('half-written');
    modified = DateTime(2026, 9, 3, 10, 1);
    expect(await it.poll(), isFalse);
    expect(refused, hasLength(1));
    expect(refused.single.name, 'v1');
    expect(refused.single.reason, contains('half-written'));
    expect(library.name, 'v1');
    expect(await it.poll(), isFalse);
    expect(refused, hasLength(1), reason: 'not retried until the file moves');

    // Written in full: taken.
    onDisk = _bundle('v2');
    read = () async => onDisk;
    modified = DateTime(2026, 9, 3, 10, 2);
    expect(await it.poll(), isTrue);
    expect(library.name, 'v2');
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
