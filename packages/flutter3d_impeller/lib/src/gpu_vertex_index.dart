/// The vertex and instance index as attributes, for the one target that has
/// no built-in for either: Impeller's OpenGL ES backend.
///
/// **Why.** That backend compiles the bundle as GLSL ES 1.00, which has no
/// `gl_VertexID` and no `gl_InstanceID`, and a stage that reads one is refused
/// by the driver when it is compiled at run time — so Linux, and an Android
/// phone without Vulkan, drew nothing. `flutter3d_shaders`'
/// `lib/vertex_index.glsl` declares [glesVertexIndexAttribute] and
/// [glesInstanceIndexAttribute] on that target alone, and this file is the
/// other half: the layout that names them and the buffers that feed them.
///
/// **One extra slot per index, after the pipeline's own.** The vertex index is
/// a float per vertex, stepping with the vertices; the instance index a float
/// per instance, stepping with the instances. Each buffer holds 0, 1, 2 … and
/// is shared by every draw, grown when a draw needs more of it. Slot 0 is
/// bound from the start of the mesh's own buffer, so the n-th vertex reads n,
/// exactly what the built-in would have said.
///
/// **Told apart by trying, not by asking.** flutter_gpu does not say which
/// backend it is on, and resolves a layout's attributes by name through the
/// stage's reflection: a layout naming `f3d_vertex_index` links where the stage
/// declares it — the OpenGL ES variant — and is refused where it does not.
/// [IndexStreamsAnswer] remembers the first refusal of a stage known to read
/// the index, so Metal and Vulkan pay it once per device and never again.
///
/// Free of flutter_gpu, so the decisions are tested without a GPU.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// The attribute `lib/vertex_index.glsl` declares for the vertex index on
/// OpenGL ES.
const String glesVertexIndexAttribute = 'f3d_vertex_index';

/// The attribute `lib/vertex_index.glsl` declares for the instance index on
/// OpenGL ES.
const String glesInstanceIndexAttribute = 'f3d_instance_index';

/// Which of the two indices a vertex stage reads.
typedef IndexUse = ({bool vertex, bool instance});

/// The engine's vertex stages that read an index, and which.
///
/// Held to what `impellerc` writes for OpenGL ES by
/// `test/gles_vertex_index_test.dart`, so a stage that starts or stops reading
/// one fails there rather than drawing from an unbound slot. A stage a
/// material brings is not listed: every material vertex stage morphs, so it
/// reads the vertex index — see [indexUseOf].
const Map<String, IndexUse> engineIndexUse = <String, IndexUse>{
  'MeshVertex': (vertex: true, instance: false),
  'MeshSkinnedVertex': (vertex: true, instance: false),
  'MeshLightmappedVertex': (vertex: true, instance: false),
  'MeshInstancedVertex': (vertex: true, instance: true),
  'VelocityVertex': (vertex: true, instance: false),
  'VelocitySkinnedVertex': (vertex: true, instance: false),
  'VelocityInstancedVertex': (vertex: true, instance: false),
  'CausticPhotonVertex': (vertex: false, instance: true),
};

/// The engine's vertex stages that read no index, by name: the full-screen
/// pass, the sky, the debug lines and the rest. A pipeline over one of them is
/// built as it always was, with no attempt.
bool _readsNoIndex(String stage) => const <String>{
  'FullscreenVertex',
  'DebugLineVertex',
  'PolylineVertex',
  'ParticleVertex',
  'ParticleMeshVertex',
  'SkyVertex',
  'SkyCubeVertex',
  'SkyPhysicalVertex',
  'ShadowTileResetVertex',
  'VertexTextureProbeVertex',
  'ImpostorVertex',
}.contains(stage);

/// Which index [stage] reads on OpenGL ES: the engine's from
/// [engineIndexUse], none for the engine's stages that read neither, and the
/// vertex index for any other — a material's vertex stage, which morphs.
IndexUse indexUseOf(String stage) =>
    engineIndexUse[stage] ??
    (_readsNoIndex(stage)
        ? (vertex: false, instance: false)
        : (vertex: true, instance: false));

/// The slot-0 layout a stage built with no layout reads on this backend: the
/// standard vertex, or the skinned one for a stage named as skinned, as the
/// engine's own stages and a material's `<name>Skinned` are.
///
/// What flutter_gpu derives from the stage's own declarations when it is
/// handed nothing, written out because a layout with an index slot has to
/// spell slot 0 too.
BufferLayout defaultSlotZero(String stage) {
  const standard = <(String, VertexFormat)>[
    ('position', VertexFormat.float32x3),
    ('normal', VertexFormat.float32x3),
    ('texcoord', VertexFormat.float32x2),
    ('tangent', VertexFormat.float32x4),
    ('color', VertexFormat.float32x4),
  ];
  final attributes = <(String, VertexFormat)>[
    ...standard,
    if (stage.contains('Skinned')) ...<(String, VertexFormat)>[
      ('joints', VertexFormat.float32x4),
      ('weights', VertexFormat.float32x4),
    ],
  ];
  var offset = 0;
  final inputs = <InputAttribute>[
    for (final (name, format) in attributes)
      InputAttribute(
        name: name,
        format: format,
        offsetInBytes:
            (offset += format.bytesPerElement) - format.bytesPerElement,
      ),
  ];
  return BufferLayout(strideInBytes: offset, attributes: inputs);
}

/// Where a pipeline's index buffers go: the slot of each, or null for an
/// index the stage does not read.
final class IndexStreamSlots {
  /// The slots of the [vertex] and [instance] index buffers, each null when the
  /// stage does not read it.
  const IndexStreamSlots({this.vertex, this.instance});

  /// The vertex buffer slot of the per-vertex index stream, or null when the
  /// stage does not read the vertex index.
  final int? vertex;

  /// The vertex buffer slot of the per-instance index stream, or null when the
  /// stage does not read the instance index.
  final int? instance;
}

/// [layout] with the index buffers [use] names after its own slots — or, when
/// [layout] is null, after [defaultSlotZero] of [stage] — and where each went.
/// Null when [use] names neither.
({VertexLayoutDescriptor layout, IndexStreamSlots slots})? withIndexStreams(
  VertexLayoutDescriptor? layout,
  String stage,
  IndexUse use,
) {
  if (!use.vertex && !use.instance) return null;
  final own = layout?.buffers ?? <BufferLayout>[defaultSlotZero(stage)];
  var next = own.length;
  final vertexSlot = use.vertex ? next++ : null;
  final instanceSlot = use.instance ? next++ : null;
  return (
    layout: VertexLayoutDescriptor(<BufferLayout>[
      ...own,
      if (use.vertex)
        const BufferLayout(
          strideInBytes: 4,
          attributes: <InputAttribute>[
            InputAttribute(
              name: glesVertexIndexAttribute,
              format: VertexFormat.float32,
            ),
          ],
        ),
      if (use.instance)
        const BufferLayout(
          strideInBytes: 4,
          stepMode: VertexStepMode.instance,
          attributes: <InputAttribute>[
            InputAttribute(
              name: glesInstanceIndexAttribute,
              format: VertexFormat.float32,
            ),
          ],
        ),
    ]),
    slots: IndexStreamSlots(vertex: vertexSlot, instance: instanceSlot),
  );
}

/// The index buffers a linked pipeline reads, keyed on its `GpuPipeline`: set
/// when it was linked with them, absent when it was linked without.
final Expando<IndexStreamSlots> pipelineIndexStreams =
    Expando<IndexStreamSlots>('the index buffers a pipeline reads');

/// What a device has learnt about the index attributes: unknown until a
/// pipeline over a stage known to read one is built, then whether its stages
/// declare them.
final class IndexStreamsAnswer {
  bool? _declared;

  /// Whether a pipeline over a stage that reads [use] should be tried with the
  /// index buffers: not on a device that refused them for an engine stage.
  bool shouldTry(IndexUse use) =>
      _declared != false && (use.vertex || use.instance);

  /// A pipeline over [stage] linked with the index buffers: this device's
  /// stages declare them.
  void linked(String stage) {
    if (engineIndexUse.containsKey(stage)) _declared = true;
  }

  /// A pipeline over [stage] was refused with them. Only an engine stage
  /// known to read an index settles the question: a stage from elsewhere may
  /// simply not read one.
  void refused(String stage) {
    if (engineIndexUse.containsKey(stage) && _declared == null) {
      _declared = false;
    }
  }

  /// Whether this device is known to declare the attributes, known not to,
  /// or not known yet.
  bool? get declared => _declared;
}

/// The bytes of an index buffer that holds at least [count] entries: 0, 1,
/// 2 … as floats, rounded up to a power of two of at least 256 so a device
/// grows it a few times in its life rather than at every larger mesh.
ByteData indexBufferBytes(int count) {
  final capacity = indexBufferCapacity(count);
  return Float32List.fromList(<double>[
    for (var i = 0; i < capacity; i++) i.toDouble(),
  ]).buffer.asByteData();
}

/// How many entries [indexBufferBytes] writes for [count].
int indexBufferCapacity(int count) {
  var capacity = 256;
  while (capacity < count) {
    capacity *= 2;
  }
  return capacity;
}
