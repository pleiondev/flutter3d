import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/light_node.dart';
import '../scene/scene.dart';
import 'lighting_model.dart';
import 'material.dart';
import 'render_list.dart';
import 'render_view.dart';

/// Uniform-block names as seen by shader reflection.
///
/// Impeller reflects a uniform block under its struct TYPE name, so
/// `uniform FrameInfo { ... } frame_info;` is looked up as `FrameInfo`. Using
/// the variable name instead is not an error at bind time — it just reflects as
/// a missing block, which surfaces much later as "no uniform block named ...".
const String _kFrameInfoBlock = 'FrameInfo';
const String _kFragInfoBlock = 'FragInfo';

/// Texture slots, unlike uniform blocks, are reflected under the variable name.
const String _kAlbedoTextureSlot = 'base_color_texture';

/// Scene-wide shading knobs that are not per-material.
final class RenderSettings {
  const RenderSettings({
    this.specular = 1.0,
    this.exposure = 1.6,
    this.wireframe = false,
    this.backfaceCulling = true,
  });

  final double specular;

  /// Linear multiplier applied before tone mapping.
  ///
  /// The default is a demo choice, not a physical constant: with light intensity
  /// at a unitless 1.0 the scene's brightest values land around linear 0.6, so
  /// the tone mapper's shoulder would otherwise go unused and the image would
  /// read as under-exposed. A real engine derives this from photometric light
  /// units or auto-exposure.
  final double exposure;
  final bool wireframe;
  final bool backfaceCulling;

  RenderSettings copyWith({
    double? specular,
    double? exposure,
    bool? wireframe,
    bool? backfaceCulling,
  }) =>
      RenderSettings(
        specular: specular ?? this.specular,
        exposure: exposure ?? this.exposure,
        wireframe: wireframe ?? this.wireframe,
        backfaceCulling: backfaceCulling ?? this.backfaceCulling,
      );
}

/// One rendered frame.
final class FrameResult {
  const FrameResult({
    required this.image,
    required this.submitMicros,
    required this.drawCalls,
    required this.culled,
    required this.pipelineSwitches,
  });

  final ui.Image image;

  /// Wall-clock time inside `CommandBuffer.submit`. Not a GPU timestamp —
  /// flutter_gpu exposes none — but enough to notice a regression.
  final int submitMicros;

  final int drawCalls;

  /// Meshes rejected by frustum culling, so the win is visible.
  final int culled;

  /// How often the pipeline changed. With sorting working this should be close
  /// to the number of distinct lighting models in view.
  final int pipelineSwitches;
}

/// Draws a [Scene] through one or more [RenderView]s.
///
/// Still not a frame graph: one pass, one target, no post-processing. What it does
/// have is the structure the rest depends on — a scene it does not own, views it
/// does not assume, a culled and sorted render list, and a pipeline cache.
final class Renderer {
  Renderer._({
    required this.library,
    required this.vertexShader,
    required this.fallbackAlbedo,
    required this.transients,
    required this.msaaEnabled,
  });

  final gpu.ShaderLibrary library;
  final gpu.Shader vertexShader;

  /// 1x1 opaque white, bound when a material has no base-colour texture.
  ///
  /// A shader that declares a sampler must have something bound to it, so
  /// "no texture" has to be a neutral texture rather than an absent binding.
  final gpu.Texture fallbackAlbedo;

  final bool msaaEnabled;

  /// Per-frame uniform allocators, rotated rather than reset in place.
  ///
  /// `CommandBuffer.submit` is asynchronous. Resetting a [gpu.HostBuffer] right
  /// after submit rewinds a bump allocator the GPU may still be reading, so the
  /// next frame overwrites live uniforms. The symptom is flickering under load,
  /// not a crash, which makes it hard to attribute.
  final List<gpu.HostBuffer> transients;
  int _frameIndex = 0;

  static const int _kFramesInFlight = 3;

  static const String bundleAsset = 'build/shaders/flutter3d.shaderbundle';

  final RenderList _renderList = RenderList();

  /// Pipelines keyed by fragment shader; creating one compiles and links state
  /// on the backend, far too expensive to repeat per frame.
  final Map<String, gpu.RenderPipeline> _pipelineCache =
      <String, gpu.RenderPipeline>{};

  final Map<String, gpu.Shader> _fragmentShaders = <String, gpu.Shader>{};

  int _targetWidth = 0;
  int _targetHeight = 0;
  gpu.Texture? _colorMsaa;
  gpu.Texture? _colorResolve;
  gpu.Texture? _depthStencil;

  factory Renderer.create({required gpu.Texture fallbackAlbedo}) {
    final library = gpu.ShaderLibrary.fromAsset(bundleAsset);
    if (library == null) {
      throw StateError('Failed to load the shader bundle: $bundleAsset');
    }
    final vertexShader = library['MeshVertex'];
    if (vertexShader == null) {
      throw StateError(
        'The bundle has no MeshVertex entry. Check '
        'shaders/flutter3d.shaderbundle.json.',
      );
    }

    return Renderer._(
      library: library,
      vertexShader: vertexShader,
      fallbackAlbedo: fallbackAlbedo,
      transients: List<gpu.HostBuffer>.generate(
        _kFramesInFlight,
        (_) => gpu.gpuContext.createHostBuffer(),
      ),
      msaaEnabled: gpu.gpuContext.doesSupportOffscreenMSAA,
    );
  }

  int get pipelineCount => _pipelineCache.length;

  gpu.Shader _fragmentShaderFor(LightingModel model) {
    return _fragmentShaders.putIfAbsent(model.shaderName, () {
      final shader = library[model.shaderName];
      if (shader == null) {
        throw StateError(
          'The bundle has no "${model.shaderName}" fragment shader. '
          'Rebuild it with tool/build_shaders.sh.',
        );
      }
      return shader;
    });
  }

  gpu.RenderPipeline _pipelineFor(LightingModel model) {
    return _pipelineCache.putIfAbsent(
      model.shaderName,
      () => gpu.gpuContext.createRenderPipeline(
        vertexShader,
        _fragmentShaderFor(model),
      ),
    );
  }

  void _ensureTargets(int width, int height) {
    if (width == _targetWidth && height == _targetHeight) return;

    final sampleCount = msaaEnabled ? 4 : 1;
    final colorFormat = gpu.gpuContext.defaultColorFormat;

    _colorResolve = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: colorFormat,
    );

    if (msaaEnabled) {
      // deviceTransient is tile memory: more bandwidth, less memory. Right for
      // intermediates like the MSAA and depth attachments, never read back.
      _colorMsaa = gpu.gpuContext.createTexture(
        gpu.StorageMode.deviceTransient,
        width,
        height,
        format: colorFormat,
        sampleCount: 4,
      );
    } else {
      _colorMsaa = null;
    }

    _depthStencil = gpu.gpuContext.createTexture(
      gpu.StorageMode.deviceTransient,
      width,
      height,
      format: gpu.gpuContext.defaultDepthStencilFormat,
      sampleCount: sampleCount,
    );

    _targetWidth = width;
    _targetHeight = height;
  }

  /// Writes a uniform block using shader reflection, then binds it. Returns false
  /// when the shader has no such block.
  ///
  /// Members the shader never reads are dropped from the reflected block, so they
  /// are skipped rather than treated as errors: the unlit model legitimately has
  /// no `light_direction`.
  bool _bindUniformBlock(
    gpu.RenderPass pass,
    gpu.HostBuffer host,
    gpu.Shader shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    final slot = shader.getUniformSlot(blockName);
    final size = slot.sizeInBytes;
    if (size == null || size == 0) return false;

    final data = ByteData(size);
    members.forEach((name, values) {
      final offset = slot.getMemberOffsetInBytes(name);
      if (offset == null) return;
      for (var i = 0; i < values.length; i++) {
        data.setFloat32(offset + i * 4, values[i], Endian.host);
      }
    });

    pass.bindUniform(slot, host.emplace(data));
    return true;
  }

  /// Renders every view into one target and returns the composited image.
  ///
  /// Views share a single render pass and clear: viewports do not overlap in the
  /// split-screen case, and one pass is both cheaper and simpler than a pass per
  /// view. Views are drawn in ascending priority, as in PlayCanvas.
  FrameResult render({
    required int width,
    required int height,
    required Scene scene,
    required List<RenderView> views,
    RenderSettings settings = const RenderSettings(),
  }) {
    if (views.isEmpty) {
      throw ArgumentError('At least one RenderView is required.');
    }
    _ensureTargets(width, height);

    final resolve = _colorResolve!;
    final msaa = _colorMsaa;
    final clear = views.first.clearColor;

    final colorAttachment = msaa == null
        ? gpu.ColorAttachment(texture: resolve, clearValue: clear)
        : gpu.ColorAttachment(
            texture: msaa,
            resolveTexture: resolve,
            storeAction: gpu.StoreAction.multisampleResolve,
            clearValue: clear,
          );

    final renderTarget = gpu.RenderTarget.singleColor(
      colorAttachment,
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: _depthStencil!,
        // Standard depth: clear to the far plane, nearer fragments win.
        depthClearValue: 1.0,
      ),
    );

    final host = transients[_frameIndex % _kFramesInFlight];
    _frameIndex++;
    host.reset();

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(renderTarget);

    // Set the viewport and scissor explicitly: both default to a zero-sized
    // rect, and nothing in the API complains about drawing into one.
    pass.setDepthWriteEnable(true);
    pass.setDepthCompareOperation(gpu.CompareFunction.less);
    pass.setPrimitiveType(gpu.PrimitiveType.triangle);
    pass.setPolygonMode(
      settings.wireframe ? gpu.PolygonMode.line : gpu.PolygonMode.fill,
    );

    final ordered = List<RenderView>.of(views)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    var drawCalls = 0;
    var culled = 0;
    var pipelineSwitches = 0;
    LightingModel? boundPipeline;

    final lightDirection = vm.Vector3.zero();
    final cameraPosition = vm.Vector3.zero();

    for (final view in ordered) {
      final fraction = view.viewportFraction;
      final vx = (fraction.x * width).round();
      final vy = (fraction.y * height).round();
      final vw = math.max(1, (fraction.width * width).round());
      final vh = math.max(1, (fraction.height * height).round());

      pass.setViewport(gpu.Viewport(x: vx, y: vy, width: vw, height: vh));
      pass.setScissor(gpu.Scissor(x: vx, y: vy, width: vw, height: vh));

      final camera = view.camera;
      final aspect = vw / vh;
      final viewMatrix = camera.viewMatrix;
      final viewProjection = camera.viewProjection(aspect);
      final frustum = vm.Frustum.matrix(viewProjection);

      final visibleBefore = scene.meshes.length;
      _renderList.build(
        scene,
        view,
        viewMatrix: viewMatrix,
        frustum: frustum,
      );
      _renderList.sort(view);
      culled += visibleBefore - _renderList.length;

      camera.readWorldPosition(cameraPosition);

      // One directional light for now. More requires either an uber-shader loop
      // or clustered lighting, both of which are shader work, not scene work.
      final light = scene.firstLightOfType(LightType.directional);
      if (light != null) {
        light.readDirectionToLight(lightDirection);
      } else {
        lightDirection.setValues(0.45, 0.8, 0.6);
        lightDirection.normalize();
      }
      final lightColor = light == null
          ? Float32List.fromList(<double>[1.0, 0.97, 0.92, 1.0])
          : Float32List.fromList(<double>[
              light.color.x,
              light.color.y,
              light.color.z,
              light.intensity,
            ]);
      final lightDirData = Float32List.fromList(<double>[
        lightDirection.x,
        lightDirection.y,
        lightDirection.z,
        0.0,
      ]);
      final cameraData = Float32List.fromList(<double>[
        cameraPosition.x,
        cameraPosition.y,
        cameraPosition.z,
        0.0,
      ]);

      for (final indices in <List<int>>[
        _renderList.opaque,
        _renderList.transparent,
      ]) {
        for (var i = 0; i < indices.length; i++) {
          final item = _renderList.itemAt(indices[i]);
          final node = item.requireNode;
          final material = node.material;

          if (boundPipeline != material.lighting) {
            pass.bindPipeline(_pipelineFor(material.lighting));
            boundPipeline = material.lighting;
            pipelineSwitches++;
          }

          // Both matrices are cached on the node and keyed on its transform
          // version, so a static object costs nothing here.
          final modelMatrix = node.worldMatrix;
          final normalMatrix = node.worldNormalMatrix;

          pass.setWindingOrder(
            node.worldIsMirrored
                ? gpu.WindingOrder.clockwise
                : gpu.WindingOrder.counterClockwise,
          );
          final cull = settings.backfaceCulling &&
              !settings.wireframe &&
              !material.doubleSided;
          pass.setCullMode(cull ? gpu.CullMode.backFace : gpu.CullMode.none);

          final blend = material.alphaMode == MaterialAlphaMode.blend;
          pass.setColorBlendEnable(blend);
          if (blend) {
            pass.setColorBlendEquation(gpu.ColorBlendEquation());
            // Transparent surfaces must not occlude what is behind them.
            pass.setDepthWriteEnable(false);
          } else {
            pass.setDepthWriteEnable(true);
          }

          pass.bindVertexBuffer(node.mesh.vertexView, node.mesh.vertexCount);
          pass.bindIndexBuffer(
            node.mesh.indexView,
            node.mesh.indexType,
            node.mesh.indexCount,
          );

          _bindUniformBlock(pass, host, vertexShader, _kFrameInfoBlock, {
            'mvp': (viewProjection * modelMatrix).storage,
            'model': modelMatrix.storage,
            'normal_matrix': normalMatrix.storage,
          });

          final fragmentShader = _fragmentShaderFor(material.lighting);

          // Gated on model metadata, not reflection: a shader that only DECLARES
          // FragInfo still reports it with a non-zero size while the compiled
          // function binds no buffer, and binding that segfaults inside Metal.
          if (material.lighting.usesFragInfo) {
            _bindUniformBlock(pass, host, fragmentShader, _kFragInfoBlock, {
              'light_direction': lightDirData,
              'light_color': lightColor,
              'base_color': Float32List.fromList(<double>[
                material.baseColor.x,
                material.baseColor.y,
                material.baseColor.z,
                material.baseColor.w,
              ]),
              'camera_position': cameraData,
              'material': Float32List.fromList(<double>[
                material.metallic,
                material.roughness,
                scene.ambientIntensity,
                settings.specular,
              ]),
              'frame_params': Float32List.fromList(<double>[
                settings.exposure,
                0.0,
                0.0,
                0.0,
              ]),
            });
          }

          if (material.lighting.usesAlbedoTexture) {
            pass.bindTexture(
              fragmentShader.getUniformSlot(_kAlbedoTextureSlot),
              material.albedo ?? fallbackAlbedo,
              sampler: material.albedoSampler ??
                  gpu.SamplerOptions(
                    minFilter: gpu.MinMagFilter.linear,
                    magFilter: gpu.MinMagFilter.linear,
                    widthAddressMode: gpu.SamplerAddressMode.repeat,
                    heightAddressMode: gpu.SamplerAddressMode.repeat,
                  ),
            );
          }

          pass.draw();
          drawCalls++;
        }
      }
    }

    final stopwatch = Stopwatch()..start();
    commandBuffer.submit();
    stopwatch.stop();

    return FrameResult(
      image: resolve.asImage(),
      submitMicros: stopwatch.elapsedMicroseconds,
      drawCalls: drawCalls,
      culled: culled,
      pipelineSwitches: pipelineSwitches,
    );
  }
}
