/// The layouts and buffers that feed the index attributes on OpenGL ES (D56),
/// without a GPU.
///
///     flutter test test/gpu_vertex_index_test.dart
///
/// Mutation: number the index slots from 0 in `withIndexStreams`, and slot 0
/// is overwritten by the index buffer.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/src/gpu_vertex_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slot 0 written out is the standard vertex, or the skinned one', () {
    final standard = defaultSlotZero('MeshVertex');
    expect(standard.strideInBytes, 64);
    expect(
      standard.attributes.map((a) => '${a.name}@${a.offsetInBytes}'),
      <String>[
        'position@0',
        'normal@12',
        'texcoord@24',
        'tangent@32',
        'color@48',
      ],
    );
    final skinned = defaultSlotZero('RimGlowVertexSkinned');
    expect(skinned.strideInBytes, 96);
    expect(skinned.attributes.last.name, 'weights');
    expect(skinned.attributes.last.offsetInBytes, 80);
  });

  test('the index buffers go after the pipeline\'s own slots', () {
    final batch = VertexLayoutDescriptor(<BufferLayout>[
      defaultSlotZero('MeshInstancedVertex'),
      const BufferLayout(
        strideInBytes: 80,
        stepMode: VertexStepMode.instance,
        attributes: <InputAttribute>[
          InputAttribute(name: 'i_row0', format: VertexFormat.float32x4),
        ],
      ),
    ]);
    final indexed = withIndexStreams(
      batch,
      'MeshInstancedVertex',
      indexUseOf('MeshInstancedVertex'),
    )!;
    expect(indexed.slots.vertex, 2);
    expect(indexed.slots.instance, 3);
    final buffers = indexed.layout.buffers;
    expect(buffers, hasLength(4));
    expect(buffers[2].attributes.single.name, glesVertexIndexAttribute);
    expect(buffers[2].stepMode, VertexStepMode.vertex);
    expect(buffers[3].attributes.single.name, glesInstanceIndexAttribute);
    expect(buffers[3].stepMode, VertexStepMode.instance);
  });

  test('a stage built with no layout gets slot 0 spelt out first', () {
    final indexed = withIndexStreams(
      null,
      'MeshVertex',
      indexUseOf('MeshVertex'),
    )!;
    expect(indexed.layout.buffers.first.strideInBytes, 64);
    expect(indexed.slots.vertex, 1);
    expect(indexed.slots.instance, isNull);
  });

  test('a stage that reads no index is built as it always was', () {
    expect(
      withIndexStreams(
        null,
        'FullscreenVertex',
        indexUseOf('FullscreenVertex'),
      ),
      isNull,
    );
    // A material's own vertex stage morphs, so it reads the vertex index.
    expect(indexUseOf('RimGlowVertex'), (vertex: true, instance: false));
  });

  test('a device that refuses the index for an engine stage stops trying', () {
    final answer = IndexStreamsAnswer();
    const use = (vertex: true, instance: false);
    expect(answer.shouldTry(use), isTrue);
    // A material's stage refused proves nothing: it may read no index.
    answer.refused('RimGlowVertex');
    expect(answer.shouldTry(use), isTrue);
    answer.refused('MeshVertex');
    expect(answer.declared, isFalse);
    expect(answer.shouldTry(use), isFalse);

    final gles = IndexStreamsAnswer()..linked('MeshVertex');
    expect(gles.declared, isTrue);
    // Once known to declare them, a refusal elsewhere changes nothing.
    gles.refused('MeshSkinnedVertex');
    expect(gles.shouldTry(use), isTrue);
  });

  test('the index buffer counts from nought and grows by powers of two', () {
    expect(indexBufferCapacity(1), 256);
    expect(indexBufferCapacity(257), 512);
    expect(indexBufferCapacity(70000), 131072);
    final values = indexBufferBytes(300).buffer.asFloat32List();
    expect(values, hasLength(512));
    expect(values.take(4), <double>[0, 1, 2, 3]);
    expect(values.last, 511);
    expect(values, isA<Float32List>());
  });
}
