/// The value types a [TextureHandle] and a [GeometryBuffer] carry on this
/// backend, and the bind group layouts a stage pair needs.
///
/// Split out of `webgpu_device.dart` for the reason `webgl_types.dart` is: none
/// of these has state of its own to hide. They are the shapes plugged into a
/// handle's `backend` field by the device and read back out by the encoder, and
/// a file holding only those is a file a reader can finish.
///
/// **What a [ShaderHandle] and a [PipelineHandle] carry is not here**, and the
/// absence is the seam this package's two halves closed at. A compiled stage
/// and the pipeline over a pair of them are [WebGpuShader] and [WebGpuPipeline]
/// in `webgpu_shaders.dart` — a file that imports no browser binding, so name
/// resolution, the vertex layout arithmetic, the merge of two stages'
/// reflection and every refusal are asserted on the VM in a second rather than
/// only in a browser with a GPU. What is left here is the half that genuinely
/// needs `dart:js_interop`: textures and their views, buffers, and the
/// `GPUBindGroupLayout`s built from a pipeline's group shapes.
library;

import 'dart:js_interop';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart';
import 'webgpu_interop.dart';
import 'webgpu_shaders.dart';

/// A texture this device owns, and the views it has been asked for.
///
/// **The views are cached on the texture rather than made at each use**, and
/// that is not a micro-optimisation: `createView` allocates an object the
/// browser tracks, a pass opens with one per attachment and a draw binds one
/// per sampler, so a frame that made them fresh would hand the collector a few
/// thousand short-lived interop objects. They are also compared by identity in
/// the bind group cache, and a fresh view every draw would make that cache
/// answer no every time.
final class WebGpuTexture {
  WebGpuTexture({
    required this.texture,
    required this.dimension,
    required this.sampleable,
  });

  final GPUTexture texture;

  /// How a shader reads this: as a flat image or as six faces by direction.
  final WebGpuTextureDimension dimension;

  /// Whether this may be bound to a sampler at all.
  ///
  /// False for a `deviceTransient` target, which is the closest this API has to
  /// Impeller's tile memory: WebGPU has no transient storage mode, so the
  /// honest translation is an attachment allocated without `TEXTURE_BINDING`.
  /// Carried rather than derived so a bind of one is a Dart assertion rather
  /// than a browser message about a usage flag.
  final bool sampleable;

  GPUTextureView? _sampledView;
  final Map<int, GPUTextureView> _attachmentViews = <int, GPUTextureView>{};

  /// The view a sampler reads: the whole texture, in its own dimension.
  GPUTextureView get sampledView => _sampledView ??= texture.createView(
    GPUTextureViewDescriptor(dimension: dimension.gpuName, aspect: 'all'),
  );

  /// The view a pass attaches: one [face] of one [level], always as a flat
  /// image.
  ///
  /// **A cube face and a mip level are the same mechanism here**, which is the
  /// one place this API is simpler than the two the other hardware backends sit
  /// on: `baseArrayLayer` picks the face, `baseMipLevel` picks the level, and
  /// the result is an ordinary 2D attachment either way.
  GPUTextureView attachmentView({int face = 0, int level = 0}) =>
      _attachmentViews.putIfAbsent(
        face * 64 + level,
        () => texture.createView(
          GPUTextureViewDescriptor(
            dimension: '2d',
            aspect: 'all',
            baseMipLevel: level,
            mipLevelCount: 1,
            baseArrayLayer: face,
            arrayLayerCount: 1,
          ),
        ),
      );
}

/// A buffer this device owns.
///
/// Wrapped rather than handed over bare so that a `GeometryBuffer` from another
/// device — or from a test's fake — is a cast that fails here rather than a
/// draw the browser refuses three calls later.
final class WebGpuGeometry {
  const WebGpuGeometry(this.buffer);
  final GPUBuffer buffer;
}

/// The bind group layouts one stage pair needs, and the pipeline layout over
/// them.
///
/// **Stated rather than inferred, and the other answer has a cost attached.**
/// `createRenderPipeline` accepts the string `"auto"` and works a layout out
/// from the WGSL, which is what a spike does; the bind groups such a pipeline
/// hands out belong to that pipeline alone, so two pipelines built that way
/// cannot share a group even when their bindings are identical. For a renderer
/// with one camera block and forty materials that is forty copies of the
/// camera. Built here from the bundle's reflection, one layout serves every
/// pipeline of the pair, and a pass keys its bind groups on the resources
/// rather than on which pipeline asked for them.
///
/// Made once per stage pair and cached by the device — see
/// `WebGpuDevice.bindingsFor`.
final class WebGpuBindingLayouts {
  WebGpuBindingLayouts._(this.pipelineLayout, this.groups, this.shapes);

  /// The layouts for [pipeline], built against [gpu].
  factory WebGpuBindingLayouts.of(GPUDevice gpu, WebGpuPipeline pipeline) {
    final shapes = pipeline.groups;
    final groups = <GPUBindGroupLayout>[
      for (var group = 0; group < shapes.length; group++)
        gpu.createBindGroupLayout(
          GPUBindGroupLayoutDescriptor(
            label: '${pipeline.name} group $group',
            entries: _entriesOf(shapes[group]).toJS,
          ),
        ),
    ];
    return WebGpuBindingLayouts._(
      gpu.createPipelineLayout(
        GPUPipelineLayoutDescriptor(
          label: pipeline.name,
          bindGroupLayouts: groups.toJS,
        ),
      ),
      groups,
      shapes,
    );
  }

  /// Which stages a binding is visible to, as this API's flag word.
  ///
  /// The one line that turns `webgpu_shaders.dart`'s two booleans into
  /// `GPUShaderStage` bits, which is the whole of what that file gave up by
  /// refusing to import a browser binding.
  static int _visibility(WebGpuVisibility visibility) =>
      GpuShaderStage.vertex;

  static List<GPUBindGroupLayoutEntry> _entriesOf(WebGpuGroupShape shape) {
    final entries = <GPUBindGroupLayoutEntry>[
      for (final bound in shape.blocks)
        GPUBindGroupLayoutEntry.buffer(
          binding: bound.block.binding,
          visibility: _visibility(bound.visibility),
          buffer: GPUBufferBindingLayout(
            type: 'uniform',
            // **The one member that keeps the bind group cache worth having.**
            // With a dynamic offset, one bind group covers every draw's copy of
            // a block and the offset rides on `setBindGroup`; without it, every
            // draw's block is a different buffer range and so a different
            // group, and a frame of forty materials builds forty copies of the
            // camera.
            hasDynamicOffset: true,
            minBindingSize: bound.block.sizeInBytes,
          ),
        ),
    ];
    for (final bound in shape.samplers) {
      final sampler = bound.sampler;
      final visibility = _visibility(bound.visibility);
      entries.add(
        GPUBindGroupLayoutEntry.texture(
          binding: sampler.textureBinding,
          visibility: visibility,
          texture: GPUTextureBindingLayout(
            sampleType: 'float',
            viewDimension: sampler.dimension.gpuName,
            multisampled: false,
          ),
        ),
      );
      entries.add(
        GPUBindGroupLayoutEntry.sampler(
          binding: sampler.samplerBinding,
          visibility: visibility,
          sampler: GPUSamplerBindingLayout(type: 'filtering'),
        ),
      );
    }
    return entries;
  }

  final GPUPipelineLayout pipelineLayout;

  /// Index *n* is `@group(n)`.
  final List<GPUBindGroupLayout> groups;

  /// What each of [groups] holds, for assembling a bind group and ordering its
  /// dynamic offsets.
  final List<WebGpuGroupShape> shapes;
}
