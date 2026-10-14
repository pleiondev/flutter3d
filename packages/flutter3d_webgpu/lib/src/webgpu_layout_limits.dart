/// The limits a device is opened with, and the check that holds a stage
/// pair's bind group layouts to them before the browser is asked.
///
/// **Why a check here at all, when the browser checks.** The browser answers
/// a layout late, on an error scope, and hands back an invalid object in the
/// meantime: the pipeline built over it, the bind groups made from it and the
/// pass that draws with them are each refused in turn, and each refusal
/// reads like a different mistake. A layout over a limit is known before any
/// of that from the reflection alone, so the device asks this first and
/// refuses the pipeline once, naming the limit.
///
/// Pure Dart, so a VM test holds it: the device needs a browser with WebGPU
/// to open, and this does not.
library;

import 'webgpu_shaders.dart';

/// The limits `WebGpuDevice.open` asks a device for, each at the adapter's
/// own value — see `webgpuRequiredLimits`.
///
/// **Every limit a bind group layout is held to.** A device asked for none
/// keeps WebGPU's minimums, and the adapter usually has more: 8 uniform blocks
/// with a dynamic offset in one pipeline layout, for one, where Chrome on an
/// M3 Mac reports 10. Every uniform block
/// here is bound with a dynamic offset (`WebGpuBindingLayouts`), so an
/// instanced mesh stage beside a material with blocks of its own can ask for
/// 9, and a device left at the minimum refused it on a machine that had the
/// room. The storage limits are a compute kernel's. An adapter grants every
/// value it reports, so asking for them never fails a device that would
/// otherwise open.
const List<String> webgpuRequestedLimits = <String>[
  'maxBindGroups',
  'maxDynamicUniformBuffersPerPipelineLayout',
  'maxSampledTexturesPerShaderStage',
  'maxSamplersPerShaderStage',
  'maxUniformBuffersPerShaderStage',
  'maxStorageBuffersPerShaderStage',
  'maxStorageTexturesPerShaderStage',
];

/// The limits [webgpuLayoutProblem] holds a pipeline layout to, read off the
/// device that was granted.
typedef WebGpuLayoutLimits = ({
  int maxBindGroups,
  int maxDynamicUniformBuffersPerPipelineLayout,
  int maxUniformBuffersPerShaderStage,
  int maxSampledTexturesPerShaderStage,
  int maxSamplersPerShaderStage,
});

/// Why the bind group layouts of [groups], for the pipeline called
/// [pipeline], cannot be made on a device with [limits], or null when they
/// can.
///
/// Counted the way WebGPU counts: a uniform block with a dynamic offset once
/// for the whole layout, whatever stages see it; a uniform block, a texture
/// and a sampler once for each stage that sees it.
String? webgpuLayoutProblem(
  String pipeline,
  List<WebGpuGroupShape> groups,
  WebGpuLayoutLimits limits,
) {
  String over(int count, String what, int limit, String name) =>
      'the pipeline $pipeline binds $count $what, and this device takes at '
      'most $limit ($name)';

  if (groups.length > limits.maxBindGroups) {
    return over(
      groups.length,
      'bind groups',
      limits.maxBindGroups,
      'maxBindGroups',
    );
  }
  final blocks = <WebGpuBoundBlock>[
    for (final group in groups) ...group.blocks,
  ];
  final samplers = <WebGpuBoundSampler>[
    for (final group in groups) ...group.samplers,
  ];
  // Every uniform block is bound with a dynamic offset, so every one counts.
  if (blocks.length > limits.maxDynamicUniformBuffersPerPipelineLayout) {
    return over(
      blocks.length,
      'uniform blocks with a dynamic offset in one pipeline layout',
      limits.maxDynamicUniformBuffersPerPipelineLayout,
      'maxDynamicUniformBuffersPerPipelineLayout',
    );
  }
  for (final (String stage, bool Function(WebGpuVisibility) sees)
      in <(String, bool Function(WebGpuVisibility))>[
        ('vertex', (WebGpuVisibility v) => v.vertex),
        ('fragment', (WebGpuVisibility v) => v.fragment),
      ]) {
    final stageBlocks = blocks
        .where((WebGpuBoundBlock b) => sees(b.visibility))
        .length;
    if (stageBlocks > limits.maxUniformBuffersPerShaderStage) {
      return over(
        stageBlocks,
        'uniform blocks in its $stage stage',
        limits.maxUniformBuffersPerShaderStage,
        'maxUniformBuffersPerShaderStage',
      );
    }
    // A bound sampler is a texture and a sampler, one of each.
    final stageSamplers = samplers
        .where((WebGpuBoundSampler s) => sees(s.visibility))
        .length;
    if (stageSamplers > limits.maxSampledTexturesPerShaderStage) {
      return over(
        stageSamplers,
        'textures in its $stage stage',
        limits.maxSampledTexturesPerShaderStage,
        'maxSampledTexturesPerShaderStage',
      );
    }
    if (stageSamplers > limits.maxSamplersPerShaderStage) {
      return over(
        stageSamplers,
        'samplers in its $stage stage',
        limits.maxSamplersPerShaderStage,
        'maxSamplersPerShaderStage',
      );
    }
  }
  return null;
}

/// The stage pairs whose bind group layouts a device refused, by a key the
/// device chooses (the pair's two compiled modules), and whether each
/// refusal has been told.
///
/// **Remembered by the pair, not by the pipeline handle.** A renderer may
/// make a pipeline over a pair, give it back and make it again every second
/// — a particle effect that comes and goes does — and a refusal kept with
/// the handle went with it: the layouts were made again, refused again, and
/// reported again, every time. No later attempt changes a limit, so the
/// first reason is kept and told once.
final class WebGpuLayoutRefusals {
  final Map<Object, ({String message, bool told})> _byPair =
      <Object, ({String message, bool told})>{};

  /// Whether [pair]'s layouts are refused.
  bool isRefused(Object pair) => _byPair.containsKey(pair);

  /// Why [pair]'s layouts are refused, or null when they are not.
  String? reasonOf(Object pair) => _byPair[pair]?.message;

  /// Records that [pair]'s layouts are refused for [message]. A pair already
  /// refused keeps its first reason.
  void refuse(Object pair, String message) =>
      _byPair[pair] ??= (message: message, told: false);

  /// The reason to report for [pair] — once: null when it is not refused or
  /// was told already.
  String? tell(Object pair) {
    final refusal = _byPair[pair];
    if (refusal == null || refusal.told) return null;
    _byPair[pair] = (message: refusal.message, told: true);
    return refusal.message;
  }

  /// How many pairs are refused.
  int get length => _byPair.length;

  /// Forgets every refusal, as a device that is disposed does.
  void clear() => _byPair.clear();
}
