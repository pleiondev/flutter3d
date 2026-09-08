/// The value types a [TextureHandle], a [GeometryBuffer], a [ShaderHandle] and
/// a [PipelineHandle] carry on this backend.
///
/// Split out of `webgpu_device.dart` for the reason `webgl_types.dart` is: none
/// of these has state of its own to hide. They are the shapes plugged into a
/// handle's `backend` field by the device and read back out by the encoder, and
/// a file holding only those is a file a reader can finish.
///
/// **[WebGpuStageProgram] is the seam this package's two halves meet at.** A
/// `ShaderHandle` on this backend carries a compiled module, an entry point and
/// the reflection that came out of the bundle — the attribute locations, the
/// block offsets and the sampler binding pairs `webgpu_bundle_section.dart`
/// decodes. Whatever builds a library of stages produces these; the encoder
/// consumes them and asks nothing else of it.
library;

import 'dart:js_interop';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart';
import 'webgpu_interop.dart';

/// One compiled stage: a module, the entry point inside it, and what the
/// browser cannot be asked about either.
///
/// **A module and an entry point rather than a module alone**, because WGSL
/// puts every stage of a translation unit in one module and tells them apart
/// with `@vertex` and `@fragment`. The thing a pipeline is built from is the
/// pair.
///
/// [reflection] is the stage as the bundle described it — the same
/// [WebGpuStage] the section codec reads, carried through unchanged. It is what
/// makes `bindUniformBlock` and `bindTexture` answer to names on an API that
/// kept none: a `GPUShaderModule` cannot be interrogated for its bindings at
/// all, so the group and binding numbers have to arrive beside the code.
final class WebGpuStageProgram {
  const WebGpuStageProgram({
    required this.module,
    required this.entryPoint,
    required this.reflection,
  });

  final GPUShaderModule module;
  final String entryPoint;
  final WebGpuStage reflection;

  /// The block called [name], or null where this stage declares none.
  ///
  /// A scan rather than a map because a stage declares a handful of blocks and
  /// the list arrives in the order the reflection stated. Building a map per
  /// stage would be a map per stage for a lookup that runs a few times a draw
  /// over three entries.
  WebGpuBlock? blockNamed(String name) {
    for (final block in reflection.blocks) {
      if (block.name == name) return block;
    }
    return null;
  }

  /// The texture-and-sampler pair called [name], or null where this stage
  /// declares none. See [blockNamed] for why it is a scan.
  WebGpuSampler? samplerNamed(String name) {
    for (final sampler in reflection.samplers) {
      if (sampler.name == name) return sampler;
    }
    return null;
  }
}

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

/// What `createPipeline` records, since WebGPU cannot build anything yet.
///
/// **The pipeline is not built at `createPipeline` and cannot be.** A
/// `GPURenderPipeline` declares its colour formats, its depth format, its
/// sample count, its topology, its cull mode, its winding, its depth test, its
/// stencil test and a blend equation per target; at `createPipeline` the caller
/// has said none of those. The first three belong to a pass that has not been
/// opened and the rest arrive as setters afterwards. So this is the stage pair
/// and the layout, and the real object is looked up at the draw.
///
/// [layout] is resolved here rather than at the draw because it is a property
/// of the pipeline and not of the state around it. A caller that passed one
/// gets that one; a caller that passed null — which is every pipeline in this
/// engine but the instanced ones — gets one derived from the vertex stage's
/// reflection, which is what `GraphicsDevice.createPipeline` means by "the
/// backend works it out from the shader". The spike this file grew from refused
/// null outright, on the grounds that a `GPUShaderModule` reflects nothing;
/// that was true of the module and not of the bundle, which states every
/// attribute's name, location and format.
final class WebGpuPipelineProgram {
  WebGpuPipelineProgram({
    required this.name,
    required this.vertex,
    required this.fragment,
    required VertexLayoutSpec? layout,
  }) : layout = layout ?? _derivedLayout(vertex);

  final String name;
  final WebGpuStageProgram vertex;
  final WebGpuStageProgram fragment;

  /// Where the vertex inputs come from. Never null: see the class comment.
  final VertexLayoutSpec layout;

  /// One interleaved buffer holding every attribute the stage declares, in
  /// location order.
  ///
  /// The convention `VertexLayout` in the engine already documents, and the
  /// same one WebGL2 reconstructs from `getActiveAttrib`: attributes packed
  /// tightly in the order their locations run, and the stride their total. The
  /// reflection carries the format of each, so the offsets are a running sum
  /// rather than a guess about component widths.
  static VertexLayoutSpec _derivedLayout(WebGpuStageProgram vertex) {
    final ordered = <WebGpuAttribute>[...vertex.reflection.attributes]
      ..sort(
        (WebGpuAttribute a, WebGpuAttribute b) =>
            a.location.compareTo(b.location),
      );
    final attributes = <InputAttribute>[];
    var offset = 0;
    for (final attribute in ordered) {
      attributes.add(
        InputAttribute(
          name: attribute.name,
          format: attribute.format,
          offsetInBytes: offset,
        ),
      );
      offset += attribute.format.bytesPerElement;
    }
    return VertexLayoutSpec(<BufferLayout>[
      BufferLayout(strideInBytes: offset, attributes: attributes),
    ]);
  }

  /// What one `@group` of this pipeline holds, in binding order.
  ///
  /// Built once per stage pair and read at every draw: the blocks in this order
  /// are the order `setBindGroup`'s dynamic offsets go in, and getting that
  /// wrong draws the wrong object rather than failing.
  late final List<WebGpuGroupShape> groupShapes = _shapesOf(this);

  static List<WebGpuGroupShape> _shapesOf(WebGpuPipelineProgram pipeline) {
    final blocks = <int, Map<int, WebGpuBlock>>{};
    final samplers = <int, Map<int, WebGpuSampler>>{};
    var highest = -1;
    for (final stage in <WebGpuStageProgram>[
      pipeline.vertex,
      pipeline.fragment,
    ]) {
      for (final block in stage.reflection.blocks) {
        blocks.putIfAbsent(
          block.group,
          () => <int, WebGpuBlock>{},
        )[block.binding] = block;
        if (block.group > highest) highest = block.group;
      }
      for (final sampler in stage.reflection.samplers) {
        samplers.putIfAbsent(
          sampler.group,
          () => <int, WebGpuSampler>{},
        )[sampler.textureBinding] = sampler;
        if (sampler.group > highest) highest = sampler.group;
      }
    }
    return <WebGpuGroupShape>[
      for (var group = 0; group <= highest; group++)
        WebGpuGroupShape(
          blocks: _sorted<WebGpuBlock>(
            blocks[group],
            (WebGpuBlock a, WebGpuBlock b) => a.binding.compareTo(b.binding),
          ),
          samplers: _sorted<WebGpuSampler>(
            samplers[group],
            (WebGpuSampler a, WebGpuSampler b) =>
                a.textureBinding.compareTo(b.textureBinding),
          ),
        ),
    ];
  }

  static List<T> _sorted<T>(Map<int, T>? byBinding, Comparator<T> order) =>
      byBinding == null
      ? const <Never>[]
      : (byBinding.values.toList()..sort(order));

  /// Which stages a binding of this pipeline is visible to.
  ///
  /// A block declared by both stages — `FrameInfo` is, in every lit shader —
  /// has to say so, and a bind group layout that named one stage would be
  /// refused by the other's use of it.
  int visibilityOfBlock(int group, int binding) =>
      _visibility(group, binding, sampler: false);

  /// Which stages a sampler pair of this pipeline is visible to. See
  /// [visibilityOfBlock].
  int visibilityOfSampler(int group, int binding) =>
      _visibility(group, binding, sampler: true);

  int _visibility(int group, int binding, {required bool sampler}) {
    var flags = 0;
    void look(WebGpuStageProgram stage, int flag) {
      if (sampler) {
        for (final entry in stage.reflection.samplers) {
          if (entry.group == group && entry.textureBinding == binding) {
            flags |= flag;
          }
        }
      } else {
        for (final entry in stage.reflection.blocks) {
          if (entry.group == group && entry.binding == binding) flags |= flag;
        }
      }
    }

    look(vertex, GpuShaderStage.vertex);
    look(fragment, GpuShaderStage.fragment);
    return flags;
  }

  /// The `@location` [name] was given, from whichever stage declares it.
  ///
  /// A vertex layout states names because the two hardware backends agree about
  /// names and disagree about everything else — see `InputAttribute.name`. WGSL
  /// kept only the number, so the bundle carries the pair and this is the
  /// lookup.
  ///
  /// Throws where the layout names an input the stage does not have, rather
  /// than picking a location: a pipeline built with the wrong number reads the
  /// wrong bytes and draws a picture.
  int locationOf(String name) {
    for (final attribute in vertex.reflection.attributes) {
      if (attribute.name == name) return attribute.location;
    }
    throw ArgumentError.value(
      name,
      'name',
      'is not an input of the vertex stage "${vertex.entryPoint}", which '
          'declares ${vertex.reflection.attributes.map((WebGpuAttribute a) => a.name).join(', ')}. A vertex layout names inputs and WGSL keeps only '
          'locations, so the two are matched through the bundle\'s reflection',
    );
  }
}

/// What one `@group` of a pipeline holds: its uniform blocks and its
/// texture-and-sampler pairs, each in binding order.
///
/// Both lists are ordered by binding number rather than by the order the
/// reflection stated, because `GPURenderPassEncoder.setBindGroup` takes its
/// dynamic offsets in the order the layout's dynamic entries were declared, and
/// a layout declared in binding order makes the two readings agree. An offset
/// list out of order draws the last object's transform on this one and reports
/// nothing.
final class WebGpuGroupShape {
  const WebGpuGroupShape({required this.blocks, required this.samplers});

  final List<WebGpuBlock> blocks;
  final List<WebGpuSampler> samplers;

  /// Whether this group has nothing in it, which a pipeline's lower group
  /// numbers legitimately do: a shader that declares `@group(1)` and no
  /// `@group(0)` still needs a placeholder in slot zero of its pipeline layout.
  bool get isEmpty => blocks.isEmpty && samplers.isEmpty;
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
  factory WebGpuBindingLayouts.of(
    GPUDevice gpu,
    WebGpuPipelineProgram pipeline,
  ) {
    final shapes = pipeline.groupShapes;
    final groups = <GPUBindGroupLayout>[
      for (var group = 0; group < shapes.length; group++)
        gpu.createBindGroupLayout(
          GPUBindGroupLayoutDescriptor(
            label: '${pipeline.name} group $group',
            entries: _entriesOf(pipeline, group, shapes[group]).toJS,
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

  static List<GPUBindGroupLayoutEntry> _entriesOf(
    WebGpuPipelineProgram pipeline,
    int group,
    WebGpuGroupShape shape,
  ) {
    final entries = <GPUBindGroupLayoutEntry>[
      for (final block in shape.blocks)
        GPUBindGroupLayoutEntry.buffer(
          binding: block.binding,
          visibility: pipeline.visibilityOfBlock(group, block.binding),
          buffer: GPUBufferBindingLayout(
            type: 'uniform',
            // **The one member that keeps the bind group cache worth having.**
            // With a dynamic offset, one bind group covers every draw's copy of
            // a block and the offset rides on `setBindGroup`; without it, every
            // draw's block is a different buffer range and so a different
            // group, and a frame of forty materials builds forty copies of the
            // camera.
            hasDynamicOffset: true,
            minBindingSize: block.sizeInBytes,
          ),
        ),
    ];
    for (final sampler in shape.samplers) {
      final visibility = pipeline.visibilityOfSampler(
        group,
        sampler.textureBinding,
      );
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
