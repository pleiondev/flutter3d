/// The committed stage table is what the compiler says today.
///
///     flutter test test/stage_bindings_test.dart
///
/// `flutter3d_shaders/lib/stage_bindings.dart` is what `FakeBackend` holds a
/// renderer to on the VM. A table older than the shaders would hold it to
/// stages that no longer exist, and pass or fail for reasons nobody wrote
/// down, so this compiles every stage again and compares.
///
/// Mutation: add a sampler to any stage's entry in the committed file.
library;

import 'dart:io';

import 'package:flutter3d_shaders/stage_bindings.dart';
import 'package:flutter3d_shaders/uniform_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/stage_bindings.dart';

void main() {
  test('stage_bindings.dart matches a fresh compile', () {
    final fresh = reflectStages(
      shadersRoot: Directory('../flutter3d_shaders/shaders').absolute.path,
    );
    const stale =
        'the table is older than the shaders: run '
        '`dart run tool/stage_bindings.dart` in flutter3d_impeller';
    expect(stageBindings.keys.toSet(), fresh.keys.toSet(), reason: stale);
    for (final MapEntry(key: name, value: stage) in fresh.entries) {
      expect(
        stageBindings[name]!.blocks,
        stage.blocks,
        reason: '$name: $stale',
      );
      expect(
        stageBindings[name]!.samplers,
        stage.samplers,
        reason: '$name: $stale',
      );
      // `H1`: the layouts beside the names, which the software rasteriser
      // checks members against and the typed blocks are built from.
      final blocks = reflectedBlocks[name] ?? const {};
      expect(
        uniformBlocks[name]?.keys.toSet() ?? const <String>{},
        blocks.keys.toSet(),
        reason: '$name: $stale',
      );
      for (final MapEntry(key: block, value: members) in blocks.entries) {
        expect(
          <String, Object?>{
            for (final MapEntry(:key, :value)
                in uniformBlocks[name]![block]!.entries)
              key: value,
          },
          members,
          reason: '$name.$block: $stale',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
