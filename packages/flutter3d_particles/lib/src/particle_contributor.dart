import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'flipbook.dart';
import 'particle_system.dart';
import 'six_way.dart';

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
/// `ARCHITECTURE.md` §7, which keeps the lesson.
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

/// How six-way particles are drawn — `N6`: over what is behind them, sorted
/// farthest first, and otherwise as the additive ones are.
///
/// Smoke darkens what it covers, and addition can only brighten, so this is
/// the premultiplied "over" every transparent material draws with. Over is not
/// commutative, which is what the sort in `writeQuads` is for; depth writes
/// stay off for the additive state's reason, one puff must not cut a hole in
/// the puff behind it.
const PassState _kSixWayState = PassState(
  primitiveType: PrimitiveType.triangle,
  polygonMode: PolygonMode.fill,
  cullMode: CullMode.none,
  blend: BlendState.alphaBlend,
  depthWrite: false,
  depthCompare: CompareFunction.less,
);

final class ParticleContributor extends PassContributor {
  ParticleContributor(
    this.particles, {
    this.texture,
    this.flipbook,
    this.sixWay,
  });

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

  /// A six-way sheet to light every particle by the scene's lights — `N6` —
  /// or null for the additive stages.
  ///
  /// Takes the place of [texture]: the sheet is two textures of its own, drawn
  /// through a stage of its own, so a contributor given both draws the sheet.
  /// [flipbook] is the sheet's grid, as it is the sprite's.
  final SixWayMaterial? sixWay;

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
    final vertices = _vertices ??= Float32List(
      capacity * ParticleSystem.floatsPerParticle,
    );
    final indices = _indices ??= Uint32List(capacity * 6);

    // The camera's right and up in world space, which is what turns a point
    // into a quad that faces the viewer. Read off the view matrix's rows
    // rather than recomputed from angles the plugin does not have.
    final world = view.camera.worldMatrix;
    _right.setValues(world.entry(0, 0), world.entry(1, 0), world.entry(2, 0));
    _up.setValues(world.entry(0, 1), world.entry(1, 1), world.entry(2, 1));
    final sheet = sixWay;
    if (sheet != null) view.camera.readForward(_forward);

    final written = particles.writeQuads(
      _right,
      _up,
      vertices,
      indices,
      flipbook: flipbook,
      farthestAlong: sheet == null ? null : _forward,
    );
    if (written == 0) {
      developer.Timeline.finishSync();
      return;
    }

    // The fragment stage is called 'Particle', not 'ParticleFragment'. That is
    // worth a comment because guessing it wrong is invisible: the lookup
    // returns null, the plugin draws nothing, and the frame is merely a frame
    // without particles in it. The golden caught it; nothing else would have.
    final vertexShader = _shader(frame, 'ParticleVertex');
    final fragmentShader = _shader(
      frame,
      sheet != null
          ? 'ParticleSixWay'
          : texture == null
          ? 'Particle'
          : 'ParticleTextured',
    );
    // A six-way stage declares the light list's sampler, and one left unbound
    // is a native crash on Metal; outside a renderer's scene pass there are no
    // lights to bind, so it draws nothing rather than that.
    final lights = frame.lights;
    if (vertexShader == null ||
        fragmentShader == null ||
        (sheet != null && lights == null)) {
      developer.Timeline.finishSync();
      return;
    }

    final encoder = frame.encoder;

    // The mesh draws left their own pipeline and buffers bound, and this one
    // has a different vertex layout.
    encoder.clearBindings();
    encoder.bindPipeline(
      _pipelineFor(frame.device, vertexShader, fragmentShader),
    );
    encoder.setState(sheet == null ? _kParticleState : _kSixWayState);

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
    encoder.bindUniformBlock(vertexShader, _infoBlock, <String, Float32List>{
      'view_projection': viewProjection.storage,
    });

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
    encoder.bindUniformBlock(fragmentShader, 'FogInfo', <String, Float32List>{
      'fog': _fog,
      'eye': _eyeData,
    });

    if (sheet != null && lights != null) {
      _bindSixWay(frame, encoder, fragmentShader, sheet, lights);
    }

    final sprite = texture;
    if (sheet == null && sprite != null) {
      // Trilinear rather than `linearRepeat`, which is the engine's default and
      // has its mip filter off. A particle is a quad that shrinks as it
      // recedes; without the chain being blended it sparkles on the way out,
      // which reads as flickering rather than as distance.
      encoder.bindTexture(
        fragmentShader,
        'particle_texture',
        sprite,
        sampler: SamplerOptions.trilinearRepeat,
      );
    }

    encoder.draw();
    frame.state.drawCalls++;

    // The pipeline tracker describes the mesh pipelines only, and this pass
    // just replaced whatever it thought was bound.
    frame.state.invalidatePipeline();
    developer.Timeline.finishSync();
  }

  /// The six-way stage's own block, its sheet, and the lights reaching the
  /// particles' bounds.
  void _bindSixWay(
    ContributorFrame frame,
    PassEncoder encoder,
    ShaderHandle stage,
    SixWayMaterial sheet,
    ContributorLights lights,
  ) {
    _sixWayRight.setAll(0, _right.storage);
    _sixWayUp.setAll(0, _up.storage);
    _sixWayForward.setAll(0, _forward.storage);
    _sixWayEmission.setAll(0, sheet.emission.storage);
    _sixWayAmbient.setAll(0, sheet.ambient.storage);
    encoder.bindUniformBlock(stage, 'SixWayInfo', <String, Float32List>{
      'right': _sixWayRight,
      'up': _sixWayUp,
      'forward': _sixWayForward,
      'emission': _sixWayEmission,
      'ambient': _sixWayAmbient,
    });

    // Trilinear, for the sprite's reason: a puff shrinks as it recedes.
    encoder
      ..bindTexture(
        stage,
        'six_way_positive',
        sheet.positive,
        sampler: SamplerOptions.trilinearRepeat,
      )
      ..bindTexture(
        stage,
        'six_way_negative',
        sheet.negative,
        sampler: SamplerOptions.trilinearRepeat,
      );

    // One selection for the whole batch, as an instanced mesh gets one for
    // its bounds: a cloud of smoke is local, and the stage reads a light's
    // falloff per fragment, so near and far puffs still differ.
    final radius = particles.boundsInto(_centre);
    lights.bind(encoder, stage, centre: _centre, radius: radius);
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
        developer.log(
          'ParticleContributor: the shader bundle has no "$name"; '
          'no particles will be drawn.',
          name: 'flutter3d_particles',
        );
        return true;
      }());
    }
    return shader;
  }

  /// The pipeline for [device], built once per device rather than once ever.
  ///
  /// **`_pipeline ??=` was keyed on nothing**, so a contributor that outlived
  /// one device handed that device's pipeline to the next one's pass. Two
  /// devices in one process is not hypothetical here: a golden test draws the
  /// same effect through the software backend and then through Impeller, and
  /// `openDevice` falls back to the software backend at run time when
  /// flutter_gpu will not start. What that produces is a bind of an object the
  /// receiving backend never made — a wrong picture at best, and on a backend
  /// with a driver under it, not that.
  PipelineHandle _pipelineFor(
    GraphicsDevice device,
    ShaderHandle vertex,
    ShaderHandle fragment,
  ) {
    final key = identityHashCode(device);
    if (_pipelineDevice != key) {
      _pipeline = device.createPipeline(vertex, fragment);
      _pipelineDevice = key;
    }
    return _pipeline!;
  }

  int? _pipelineDevice;

  final Set<String> _missing = <String>{};

  final Float32List _fog = Float32List(4);
  final Float32List _eyeData = Float32List(4);
  final vm.Vector3 _eye = vm.Vector3.zero();
  PipelineHandle? _pipeline;
  Float32List? _vertices;
  Uint32List? _indices;
  final vm.Vector3 _right = vm.Vector3.zero();
  final vm.Vector3 _up = vm.Vector3.zero();
  final vm.Vector3 _forward = vm.Vector3.zero();
  final vm.Vector3 _centre = vm.Vector3.zero();
  final Float32List _sixWayRight = Float32List(4);
  final Float32List _sixWayUp = Float32List(4);
  final Float32List _sixWayForward = Float32List(4);
  final Float32List _sixWayEmission = Float32List(4);
  final Float32List _sixWayAmbient = Float32List(4);
}
