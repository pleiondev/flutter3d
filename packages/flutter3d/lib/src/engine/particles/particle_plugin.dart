import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../render/render_plugin.dart';
import 'particle_system.dart';

/// Draws every live particle as one batch of camera-facing quads.
///
/// [RenderStage.inScene] rather than after it, so particles are depth-tested
/// against the world — a spark behind a pillar has to be hidden by it — and so
/// they land in the HDR target where the bloom can pick the bright ones up,
/// which is most of what makes an explosion read as light.
///
/// Depth write is off and blending is additive. Additive is what removes the
/// need to sort: addition is commutative, so a thousand particles in one
/// unsorted batch composite correctly, and one draw call covers all of them.
final class ParticlePlugin extends RenderPlugin {
  ParticlePlugin(this.particles);

  final ParticleSystem particles;

  static const String _infoBlock = 'ParticleInfo';

  @override
  RenderStage get stage => RenderStage.inScene;

  @override
  bool get isActive => particles.aliveCount > 0;

  @override
  void encode(PluginFrame frame) {
    final view = frame.view;
    final viewProjection = frame.viewProjection;
    if (view == null || viewProjection == null) return;
    developer.Timeline.startSync('ParticlePlugin.encode');

    final capacity = particles.capacity;
    final vertices = _vertices ??=
        Float32List(capacity * ParticleSystem.floatsPerParticle);
    final indices = _indices ??= Uint32List(capacity * 6);

    // The camera's right and up in world space, which is what turns a point
    // into a quad that faces the viewer. Read off the view matrix's rows
    // rather than recomputed from angles the plugin does not have.
    final world = view.camera.worldMatrix;
    _right.setValues(world.entry(0, 0), world.entry(1, 0), world.entry(2, 0));
    _up.setValues(world.entry(0, 1), world.entry(1, 1), world.entry(2, 1));

    final written = particles.writeQuads(_right, _up, vertices, indices);
    if (written == 0) {
      developer.Timeline.finishSync();
      return;
    }

    final library = frame.services.library;
    final vertexShader = library['ParticleVertex'];
    final fragmentShader = library['ParticleFragment'];
    if (vertexShader == null || fragmentShader == null) {
      developer.Timeline.finishSync();
      return;
    }

    final pass = frame.pass;

    // The mesh draws left their own pipeline and buffers bound, and this one
    // has a different vertex layout.
    pass.clearBindings();
    pass.bindPipeline(
      _pipeline ??= gpu.gpuContext.createRenderPipeline(
        vertexShader,
        fragmentShader,
      ),
    );
    pass.setPrimitiveType(gpu.PrimitiveType.triangle);
    pass.setPolygonMode(gpu.PolygonMode.fill);
    // A quad seen from behind is still a quad; culling one would make half the
    // particles vanish depending on which way the camera turned.
    pass.setCullMode(gpu.CullMode.none);
    pass.setColorBlendEnable(true);
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.one,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.one,
      ),
    );
    // Tested against the world, but never written: particles must not occlude
    // each other, and with additive blending they have no business trying.
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.less);

    final vertexCount = written * 4;
    final indexCount = written * 6;
    pass.bindVertexBuffer(
      frame.host.emplace(
        ByteData.sublistView(
          vertices,
          0,
          written * ParticleSystem.floatsPerParticle,
        ),
      ),
      vertexCount,
    );
    pass.bindIndexBuffer(
      frame.host.emplace(ByteData.sublistView(indices, 0, indexCount)),
      gpu.IndexType.int32,
      indexCount,
    );
    frame.services.bindUniformBlock(
      pass,
      frame.host,
      vertexShader,
      _infoBlock,
      <String, Float32List>{'view_projection': viewProjection.storage},
    );

    pass.draw();
    frame.state.drawCalls++;

    // The pipeline tracker describes the mesh pipelines only, and this pass
    // just replaced whatever it thought was bound.
    frame.state.invalidatePipeline();
    developer.Timeline.finishSync();
  }

  gpu.RenderPipeline? _pipeline;
  Float32List? _vertices;
  Uint32List? _indices;
  final vm.Vector3 _right = vm.Vector3.zero();
  final vm.Vector3 _up = vm.Vector3.zero();
}
