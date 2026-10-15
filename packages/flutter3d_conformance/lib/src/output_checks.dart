/// Which check holds each feature the HAL gained in 1.0 by what it draws or
/// writes — and, for the few nothing here can draw, why.
///
/// **The table is read by `tool/structure.dart`** ("every feature added in
/// 1.0 has a check that compares its output"): every stable feature
/// declared after `capabilities.dart`'s "since 1.0" marker is a key of
/// [outputChecks] or of [unmeasuredFeatures], and the check each names has
/// to read pixels, bytes or query results back and to name the feature it
/// holds. The honesty check beside these asks the other question — that a
/// feature not listed is refused by name — so a check here declines on a
/// device without its feature rather than asking it twice.
library;

import '../flutter3d_conformance.dart';
import 'output_draw_checks.dart';
import 'output_resource_checks.dart';

/// A 1.0 feature's wire name, to the name of the check that compares its
/// output against the software rasteriser's arithmetic.
const Map<String, String> outputChecks = <String, String>{
  '2d-array-textures': 'two views drawn a pass each land in their own layers',
  '3d-textures': 'a 3D texture keeps its slices apart',
  'cube-array-textures': 'a cube array keeps its faces apart',
  'render-to-array-layer':
      'two views drawn a pass each land in their own layers',
  'texture-writes': 'a texture write lands where it was aimed',
  'buffers': 'a buffer reads back what it was made with and written',
  'buffer-copy': 'a buffer copy moves the bytes it names',
  'texture-copy':
      'two views copied into a runtime image land in their own layers',
  'buffer-texture-copy':
      'a copy between a buffer and a texture keeps the bytes',
  'storage-textures': 'a blur kernel gives the same bytes',
  'indirect-draw': 'an indirect draw reads its arguments',
  'indirect-dispatch': 'an indirect dispatch runs the workgroups it names',
  'indirect-first-instance':
      'an indirect draw from a first instance draws every instance',
  'non-indexed-draw': 'a non-indexed draw ignores the bound indices',
  'depth-bias': 'a depth bias moves the depth the way its sign says',
  'color-write-mask': 'a colour write mask keeps the channels it leaves out',
  'depth-clip-control': 'depth clamp keeps what the depth clip cuts',
  'min-max-blend': 'min and max blending pick a channel each',
  'sampler-lod-clamp': 'a minimum level clamp picks the level',
  'sampler-border-color': 'a border address mode reads the border colour',
  'occlusion-query': 'an occlusion query counts the samples that land',
  'timestamp-query': "a pass's timestamps advance",
  'texture-compression-bc':
      'a compressed format it supports samples its colour back',
  'texture-compression-etc2':
      'a compressed format it supports samples its colour back',
  'texture-compression-astc':
      'a compressed format it supports samples its colour back',
  'texture-compression-astc-hdr':
      'a compressed format it supports samples its colour back',
  'float32-blendable': 'a 32-bit float target blends',
  'rg11b10ufloat-renderable': 'the packed float format takes a draw',
  'uniform-bytes': 'uniform bytes reach the block they are bound to',
  'mapped-buffers': 'a mapped buffer carries its bytes both ways',
  'synchronous-readback': 'a synchronous readback reads what was written',
  'pipeline-statistics-query':
      'a pipeline statistics query counts one triangle',
  'render-bundles': 'a render bundle draws what it recorded at every replay',
  'multi-draw': 'a multi-draw draws each window it is handed',
  'multi-draw-indirect': 'a multi-draw-indirect draws its records or its count',
  'base-vertex-base-instance':
      'a base vertex shifts the indices and a first instance draws',
  'reversed-depth': 'a reversed depth range keeps its precision near zero',
  'viewport-beyond-target':
      'a viewport past the target draws its window of the frame',
  'multiview': 'two views drawn in one multiview pass land in both layers',
  'shared-textures': 'a zero-copy texture share carries the pixels',
  'shared-buffers': 'a zero-copy buffer share carries the bytes',
  'shared-fences': 'a zero-copy texture share carries the pixels',
  '1d-textures': 'a 1D texture keeps its texels',
  'depth-bias-clamp': 'a depth bias clamp bounds the bias',
  'primitive-strips': 'every primitive type is assembled as itself or refused',
  'point-primitives': 'every primitive type is assembled as itself or refused',
  'index-uint32': 'a 32-bit index reaches past 65535',
  'blend-constant-alpha': 'a blend constant reaches the blend, or is refused',
  'fractional-viewport': 'a fractional viewport is not rounded',
  'uniform-buffers': 'a uniform buffer reaches the block it is bound to',
};

/// The 1.0 features no check here can compare yet, and why: each needs a
/// stage the engine's bundle does not have. Their refusal half is still the
/// honesty check's.
const Map<String, String> unmeasuredFeatures = <String, String>{
  'shader-f16':
      'a shader-language feature: a stage compiled with it is refused by '
      'loadShaders, and the bundle has none',
  'subgroups':
      'a shader-language feature: a stage compiled with it is refused by '
      'loadShaders, and the bundle has none',
  'clip-distances':
      'a shader-language feature: a stage compiled with it is refused by '
      'loadShaders, and the bundle has none',
  'read-write-storage-textures':
      'bound only through a compute stage that declares a read-write storage '
      'texture, and no conformance kernel declares one',
  'render-stage-storage':
      'no render stage in the bundle declares a storage binding to read',
  'dual-source-blending':
      'no fragment stage in the bundle writes a second source colour for '
      'the source1 factors to read',
  'sampler-compare':
      'no stage in the bundle samples a depth texture through a comparison '
      'sampler',
};

/// The output checks that need no stage — buffers, copies, writes, sharing
/// and the device's lifetime — for [conformanceChecks].
List<ConformanceCheck> get featureOutputChecks => resourceOutputChecks;

/// The output checks that draw or sample, for [shaderChecks]: a backend
/// that has not compiled a stage yet runs [featureOutputChecks] first.
List<ConformanceCheck> get drawnOutputChecks => <ConformanceCheck>[
  ...drawOutputChecks,
  ...sampledOutputChecks,
];
