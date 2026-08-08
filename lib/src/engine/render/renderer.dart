import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../gpu/gpu_mesh.dart';
import '../scene/light_buffer.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';
import 'debug_draw.dart';
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
const String _kLineInfoBlock = 'LineInfo';

/// Texture slots, unlike uniform blocks, are reflected under the variable name.
const String _kAlbedoTextureSlot = 'base_color_texture';

/// Scene-wide shading knobs that are not per-material.
final class RenderSettings {
  const RenderSettings({
    this.specular = 1.0,
    this.exposure = 1.6,
    this.wireframe = false,
    this.backfaceCulling = true,
    this.debug = const DebugDrawOptions(),
    this.highlighted = const <SceneNode>[],
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

  /// Which debug overlays to draw on top of the scene.
  final DebugDrawOptions debug;

  /// Nodes to outline, typically whatever picking last selected.
  final List<SceneNode> highlighted;

  RenderSettings copyWith({
    double? specular,
    double? exposure,
    bool? wireframe,
    bool? backfaceCulling,
    DebugDrawOptions? debug,
    List<SceneNode>? highlighted,
  }) =>
      RenderSettings(
        specular: specular ?? this.specular,
        exposure: exposure ?? this.exposure,
        wireframe: wireframe ?? this.wireframe,
        backfaceCulling: backfaceCulling ?? this.backfaceCulling,
        debug: debug ?? this.debug,
        highlighted: highlighted ?? this.highlighted,
      );
}

/// One rendered frame.
final class FrameResult {
  const FrameResult({
    required this.image,
    required this.cpuMicros,
    required this.submitMicros,
    required this.drawCalls,
    required this.culled,
    required this.pipelineSwitches,
    required this.debugLines,
    required this.lights,
    required this.lightsDropped,
    required this.pipelines,
  });

  final ui.Image image;

  /// Wall-clock time spent inside [Renderer.render], submit included.
  ///
  /// This is what the renderer costs the UI thread. It is not the GPU cost: the
  /// frame is still executing when this number is taken.
  final int cpuMicros;

  /// Wall-clock time inside `CommandBuffer.submit`. Not a GPU timestamp —
  /// flutter_gpu exposes none — but enough to notice a regression.
  final int submitMicros;

  final int drawCalls;

  /// Meshes rejected by frustum culling, so the win is visible.
  final int culled;

  /// How often the pipeline changed. With sorting working this should be close
  /// to the number of distinct lighting models in view.
  final int pipelineSwitches;

  /// Line segments submitted by the debug overlay, zero when it is off.
  final int debugLines;

  /// Lights actually shaded this frame.
  final int lights;

  /// Lights that did not fit in the uniform array, so a scene that quietly
  /// stopped lighting its ninth lamp says so instead of looking wrong.
  final int lightsDropped;

  /// Pipelines the renderer has built so far.
  ///
  /// Reported per frame because it is the number that has to stay put: light
  /// count, light type and material values are all uniforms, and any of them
  /// pushing this up would mean a permutation had crept in where a uniform
  /// belonged. With no runtime shader compilation, that is not a slow path —
  /// it is a wrong one.
  final int pipelines;
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
    required this.debugLineVertexShader,
    required this.debugLineFragmentShader,
    required this.fallbackAlbedo,
    required this.transients,
    required this.msaaEnabled,
  });

  final gpu.ShaderLibrary library;
  final gpu.Shader vertexShader;

  /// The debug overlay's own stage pair. Separate from the mesh shaders because
  /// the line buffer has a different vertex layout, and flutter_gpu takes the
  /// layout from the shader's `in` declarations.
  final gpu.Shader debugLineVertexShader;
  final gpu.Shader debugLineFragmentShader;

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

  /// Reused across frames, so a steady overlay allocates nothing.
  final DebugDraw debugDraw = DebugDraw();

  /// The scene's lights, repacked once per view.
  final LightBuffer lights = LightBuffer();

  // Uniform scratch, reused rather than rebuilt per draw. Writing a fresh
  // Float32List for every member of every draw is precisely the allocation
  // pattern the render list was shaped to avoid.
  final Float32List _cameraData = Float32List(4);
  final Float32List _baseColorData = Float32List(4);
  final Float32List _materialData = Float32List(4);
  final Float32List _frameParams = Float32List(4);

  gpu.RenderPipeline? _debugLinePipeline;

  /// A 0, 1, 2, … index buffer for the debug overlay.
  ///
  /// The overlay's vertices are already in draw order, so indices carry no
  /// information — but `draw()` submits nothing without an index buffer bound,
  /// and there is no non-indexed entry point in the API. Keeping the identity
  /// sequence in a device buffer that only grows means the cost is one upload
  /// when the overlay gets bigger, not one per frame.
  gpu.DeviceBuffer? _debugIndexBuffer;
  int _debugIndexCapacity = 0;

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
    gpu.Shader require(String name) {
      final shader = library[name];
      if (shader == null) {
        throw StateError(
          'The bundle has no "$name" entry. Check '
          'shaders/flutter3d.shaderbundle.json and rebuild with '
          'tool/build_shaders.sh.',
        );
      }
      return shader;
    }

    return Renderer._(
      library: library,
      vertexShader: require('MeshVertex'),
      debugLineVertexShader: require('DebugLineVertex'),
      debugLineFragmentShader: require('DebugLine'),
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
    // Timeline markers, not print statements: the phases below are only
    // meaningful next to Flutter's own build and raster spans, and only in
    // profile or release, where the debug interpreter is not the bottleneck.
    developer.Timeline.startSync('Renderer.render');
    final frameClock = Stopwatch()..start();
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

    final ordered = List<RenderView>.of(views)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    var drawCalls = 0;
    var culled = 0;
    var pipelineSwitches = 0;
    var debugLines = 0;
    var lightOverflow = 0;
    LightingModel? boundPipeline;

    final cameraPosition = vm.Vector3.zero();

    for (final view in ordered) {
      // Per view rather than once: the debug overlay at the end of each view
      // leaves the pass in line-drawing state, so the next view has to
      // re-establish its own.
      //
      // Viewport and scissor are set explicitly because both default to a
      // zero-sized rect, and nothing in the API complains about drawing into one.
      pass.setDepthWriteEnable(true);
      pass.setDepthCompareOperation(gpu.CompareFunction.less);
      pass.setPrimitiveType(gpu.PrimitiveType.triangle);
      pass.setPolygonMode(
        settings.wireframe ? gpu.PolygonMode.line : gpu.PolygonMode.fill,
      );

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
      developer.Timeline.startSync('RenderList.build');
      _renderList.build(
        scene,
        view,
        viewMatrix: viewMatrix,
        frustum: frustum,
      );
      developer.Timeline.finishSync();

      developer.Timeline.startSync('RenderList.sort');
      _renderList.sort(view);
      developer.Timeline.finishSync();
      culled += visibleBefore - _renderList.length;

      camera.readWorldPosition(cameraPosition);

      // Every visible light, packed once per view rather than per draw. The
      // count is a uniform, so switching a light off shortens the shader's loop
      // without touching the pipeline — which is the whole point of the array,
      // given there is no runtime shader compilation to fall back on.
      lights.gather(scene.lights);
      if (lights.count == 0) lights.useDefaultLight();
      lightOverflow = lights.overflow;

      _cameraData[0] = cameraPosition.x;
      _cameraData[1] = cameraPosition.y;
      _cameraData[2] = cameraPosition.z;

      developer.Timeline.startSync('Renderer.encodeDraws');
      for (final indices in <List<int>>[
        _renderList.opaque,
        _renderList.transparent,
      ]) {
        for (var i = 0; i < indices.length; i++) {
          final item = _renderList.itemAt(indices[i]);
          final node = item.requireNode;
          final mesh = node.mesh;
          // The scene deals in MeshGeometry so that culling and picking need no
          // device; only here does it matter that the geometry actually reached
          // the GPU. A CPU-only mesh in a drawn scene is a bug in the caller,
          // not something to skip quietly.
          if (mesh is! GpuMesh) {
            throw StateError(
              'MeshNode "${node.name}" holds ${mesh.runtimeType}, which has no '
              'GPU buffers. Upload it with GpuMesh.upload before drawing it.',
            );
          }
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

          pass.bindVertexBuffer(mesh.vertexView, mesh.vertexCount);
          pass.bindIndexBuffer(
            mesh.indexView,
            mesh.indexType,
            mesh.indexCount,
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
            _baseColorData[0] = material.baseColor.x;
            _baseColorData[1] = material.baseColor.y;
            _baseColorData[2] = material.baseColor.z;
            _baseColorData[3] = material.baseColor.w;

            _materialData[0] = material.metallic;
            _materialData[1] = material.roughness;
            _materialData[2] = scene.ambientIntensity;
            _materialData[3] = settings.specular;

            _frameParams[0] = settings.exposure;
            _frameParams[1] = lights.count.toDouble();

            _bindUniformBlock(pass, host, fragmentShader, _kFragInfoBlock, {
              // Whole arrays written from their reflected base offset. Impeller
              // reflects the array, not its elements — `lights[0]` comes back
              // null — but the std140 stride for a vec4 array is a flat 16
              // bytes, so a contiguous write lands each element correctly.
              'light_position': lights.positions,
              'light_color': lights.colors,
              'light_direction': lights.directions,
              'light_cone': lights.cones,
              'base_color': _baseColorData,
              'camera_position': _cameraData,
              'material': _materialData,
              'frame_params': _frameParams,
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
      developer.Timeline.finishSync();

      if (_encodeDebugLines(
        pass: pass,
        host: host,
        scene: scene,
        view: view,
        viewProjection: viewProjection,
        aspect: aspect,
        settings: settings,
      )) {
        debugLines += debugDraw.lineCount;
        drawCalls++;
        // The overlay bound its own pipeline, so the next view must rebind.
        boundPipeline = null;
      }
    }

    developer.Timeline.startSync('CommandBuffer.submit');
    final stopwatch = Stopwatch()..start();
    commandBuffer.submit();
    stopwatch.stop();
    developer.Timeline.finishSync();

    final image = resolve.asImage();
    frameClock.stop();
    developer.Timeline.finishSync();

    return FrameResult(
      image: image,
      cpuMicros: frameClock.elapsedMicroseconds,
      submitMicros: stopwatch.elapsedMicroseconds,
      drawCalls: drawCalls,
      culled: culled,
      pipelineSwitches: pipelineSwitches,
      debugLines: debugLines,
      lights: lights.count,
      lightsDropped: lightOverflow,
      pipelines: _pipelineCache.length,
    );
  }

  /// Builds and submits the debug overlay for one view. Returns false when there
  /// was nothing to draw.
  ///
  /// The whole overlay is a single non-indexed `PrimitiveType.line` draw out of
  /// the per-frame host buffer, so switching it on costs one buffer write and one
  /// draw call no matter how much it shows.
  bool _encodeDebugLines({
    required gpu.RenderPass pass,
    required gpu.HostBuffer host,
    required Scene scene,
    required RenderView view,
    required vm.Matrix4 viewProjection,
    required double aspect,
    required RenderSettings settings,
  }) {
    if (!settings.debug.anyEnabled && settings.highlighted.isEmpty) {
      return false;
    }

    developer.Timeline.startSync('DebugDraw.build');
    debugDraw.buildForScene(
      scene,
      settings.debug,
      activeCamera: view.camera,
      aspect: aspect,
      highlighted: settings.highlighted,
    );
    developer.Timeline.finishSync();
    if (debugDraw.isEmpty) return false;

    developer.Timeline.startSync('DebugDraw.encode');
    // The mesh draws left an index buffer bound; this draw is non-indexed, and
    // a stale index buffer would make it read triangle indices as line vertices.
    pass.clearBindings();

    pass.bindPipeline(
      _debugLinePipeline ??= gpu.gpuContext.createRenderPipeline(
        debugLineVertexShader,
        debugLineFragmentShader,
      ),
    );
    pass.setPrimitiveType(gpu.PrimitiveType.line);
    pass.setPolygonMode(gpu.PolygonMode.fill);
    pass.setCullMode(gpu.CullMode.none);
    pass.setColorBlendEnable(false);
    // Drawn on top of the scene: a bounding box that disappears inside the very
    // object it bounds is not much of a diagnostic.
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);

    final vertexCount = debugDraw.vertexCount;
    pass.bindVertexBuffer(host.emplace(debugDraw.vertexBytes), vertexCount);
    pass.bindIndexBuffer(
      _identityIndices(vertexCount),
      gpu.IndexType.int32,
      vertexCount,
    );
    _bindUniformBlock(pass, host, debugLineVertexShader, _kLineInfoBlock, {
      'view_projection': viewProjection.storage,
    });

    pass.draw();
    developer.Timeline.finishSync();
    return true;
  }

  /// A view over the identity index sequence, growing the backing buffer when
  /// the overlay outgrows it.
  gpu.BufferView _identityIndices(int count) {
    if (count > _debugIndexCapacity) {
      var capacity = math.max(_debugIndexCapacity * 2, 1024);
      while (capacity < count) {
        capacity *= 2;
      }
      final indices = Uint32List(capacity);
      for (var i = 0; i < capacity; i++) {
        indices[i] = i;
      }
      _debugIndexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
        indices.buffer.asByteData(),
      );
      _debugIndexCapacity = capacity;
    }
    return gpu.BufferView(
      _debugIndexBuffer!,
      offsetInBytes: 0,
      lengthInBytes: count * 4,
    );
  }
}
