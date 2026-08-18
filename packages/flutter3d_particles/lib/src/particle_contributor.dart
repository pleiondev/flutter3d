import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'flipbook.dart';
import 'particle_system.dart';

/// Draws every live particle as one batch of camera-facing quads.
///
/// inside the scene pass rather than after it, so particles are depth-tested
/// against the world — a spark behind a pillar has to be hidden by it — and so
/// they land in the HDR target where the bloom can pick the bright ones up,
/// which is most of what makes an explosion read as light.
///
/// Depth write is off and blending is additive. Additive is what removes the
/// need to sort: addition is commutative, so a thousand particles in one
/// unsorted batch composite correctly, and one draw call covers all of them.
/// How particles are drawn: additive, unculled, depth-tested but never written.
///
/// Depth write off, and it means it. That sentence was untrue for most of this
/// file's life — `flutter_gpu`'s setter ignored its argument until SDK 3.47, so
/// additive particles occluded each other on two backends out of three. See
/// `flutter3d_graphics/COMPATIBILITY.md`, which keeps the lesson.
///
/// A quad seen from behind is still a quad, which is why nothing is culled:
/// culling would make half the particles vanish depending on which way the
/// camera turned.
const PassState _kParticleState = PassState(
  primitiveType: PrimitiveType.triangle,
  polygonMode: PolygonMode.fill,
  cullMode: CullMode.none,
  blend: BlendState.additive,
  depthWrite: false,
  depthCompare: CompareFunction.less,
);

final class ParticleContributor extends PassContributor {
  ParticleContributor(this.particles, {this.texture, this.flipbook});

  final ParticleSystem particles;

  /// A sprite for every particle, or null for the procedural disc.
  ///
  /// **Null picks a different fragment stage, not a white texture.** The
  /// procedural stage has no sampler at all, and that is deliberate: binding a
  /// texture to a slot a compiled shader has no room for is this engine's most
  /// expensive recurring bug, and the crash is native with no Dart stack. Two
  /// stages, chosen here, is the arrangement that cannot make that mistake.
  ///
  /// Build it with a mip chain — `MipChain.build`, and ask
  /// `GraphicsDevice.supportsMipmaps` first. A particle is a quad that shrinks
  /// as it recedes, which is exactly the case a chain exists for, and one
  /// without a chain sparkles as it goes away.
  final TextureHandle? texture;

  /// The sheet [texture] is a grid of, or null for a single sprite.
  ///
  /// Only meaningful with a texture, and harmless without one: the cell it
  /// would choose scales coordinates the procedural stage reads as a radius,
  /// which would shrink the disc rather than doing anything useful. Set both or
  /// neither.
  final Flipbook? flipbook;

  static const String _infoBlock = 'ParticleInfo';


  @override
  bool get isActive => particles.aliveCount > 0;

  @override
  void encode(ContributorFrame frame) {
    final view = frame.view;
    final viewProjection = frame.viewProjection;
    if (view == null || viewProjection == null) return;
    developer.Timeline.startSync('ParticleContributor.encode');

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

    final written = particles.writeQuads(_right, _up, vertices, indices,
        flipbook: flipbook);
    if (written == 0) {
      developer.Timeline.finishSync();
      return;
    }

    // The fragment stage is called 'Particle', not 'ParticleFragment'. That is
    // worth a comment because guessing it wrong is invisible: the lookup
    // returns null, the plugin draws nothing, and the frame is merely a frame
    // without particles in it. The golden caught it; nothing else would have.
    final vertexShader = _shader(frame, 'ParticleVertex');
    final fragmentShader =
        _shader(frame, texture == null ? 'Particle' : 'ParticleTextured');
    if (vertexShader == null || fragmentShader == null) {
      developer.Timeline.finishSync();
      return;
    }

    final encoder = frame.encoder;

    // The mesh draws left their own pipeline and buffers bound, and this one
    // has a different vertex layout.
    encoder.clearBindings();
    encoder.bindPipeline(
      _pipeline ??= frame.device.createPipeline(vertexShader, fragmentShader),
    );
    encoder.setState(_kParticleState);

    final vertexCount = written * 4;
    final indexCount = written * 6;
    encoder.bindVertexData(
      ByteData.sublistView(
        vertices,
        0,
        written * ParticleSystem.floatsPerParticle,
      ),
      vertexCount,
    );
    encoder.bindIndexData(
      ByteData.sublistView(indices, 0, indexCount),
      IndexType.int32,
      indexCount,
    );
    encoder.bindUniformBlock(
      vertexShader,
      _infoBlock,
      <String, Float32List>{'view_projection': viewProjection.storage},
    );

    // Fog is attenuation here rather than a mix — see the fragment shader.
    // Without it a distant flame stays vivid against a wall that has faded
    // into the murk, which is the one place a viewer notices fog is missing.
    final fog = frame.settings.fog;
    final colour = fog.resolvedColor;
    _fog[0] = colour.x;
    _fog[1] = colour.y;
    _fog[2] = colour.z;
    _fog[3] = fog.density;
    view.camera.readWorldPosition(_eye);
    _eyeData[0] = _eye.x;
    _eyeData[1] = _eye.y;
    _eyeData[2] = _eye.z;
    encoder.bindUniformBlock(
      fragmentShader,
      'FogInfo',
      <String, Float32List>{'fog': _fog, 'eye': _eyeData},
    );

    final sprite = texture;
    if (sprite != null) {
      // Trilinear rather than `linearRepeat`, which is the engine's default and
      // has its mip filter off. A particle is a quad that shrinks as it
      // recedes; without the chain being blended it sparkles on the way out,
      // which reads as flickering rather than as distance.
      encoder.bindTexture(fragmentShader, 'particle_texture', sprite,
          sampler: SamplerOptions.trilinearRepeat);
    }

    encoder.draw();
    frame.state.drawCalls++;

    // The pipeline tracker describes the mesh pipelines only, and this pass
    // just replaced whatever it thought was bound.
    frame.state.invalidatePipeline();
    developer.Timeline.finishSync();
  }

  /// Looks a stage up, and complains once if it is missing.
  ///
  /// Once rather than every frame, because sixty identical lines a second is
  /// how a real message gets scrolled away — and silently is how this bug
  /// survived being written in the first place.
  ShaderHandle? _shader(ContributorFrame frame, String name) {
    final shader = frame.device.shaders[name];
    if (shader == null && _missing.add(name)) {
      assert(() {
        debugPrint('ParticleContributor: the shader bundle has no "$name"; '
            'no particles will be drawn.');
        return true;
      }());
    }
    return shader;
  }

  final Set<String> _missing = <String>{};

  final Float32List _fog = Float32List(4);
  final Float32List _eyeData = Float32List(4);
  final vm.Vector3 _eye = vm.Vector3.zero();
  PipelineHandle? _pipeline;
  Float32List? _vertices;
  Uint32List? _indices;
  final vm.Vector3 _right = vm.Vector3.zero();
  final vm.Vector3 _up = vm.Vector3.zero();
}
