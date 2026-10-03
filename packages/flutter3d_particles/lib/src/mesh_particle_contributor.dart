/// Every live particle as a copy of one mesh, drawn in a single instanced call.
///
/// ## A second contributor, not a second mode of the first
///
/// [ParticleContributor] and this one share a pool, a pass and a blend, and
/// almost nothing else. A billboard is built on the CPU and sent as four
/// vertices; a mesh is uploaded once and sent as eight floats of placement.
/// The buffers differ, the layout differs, the shaders differ, and the only
/// code they could share is the fog block and the pass state — which is a
/// constant either way.
///
/// So they sit beside each other. The quad path's goldens were recorded against
/// its own arithmetic, and folding both into one class would have put those
/// pictures at the mercy of a branch taken for the other one.
///
/// ## What the layout says, and why the order matters twice
///
/// Slot 0 is the mesh, stepping per vertex, and it names only `position` and
/// `normal` — the two attributes the stage reads — at their offsets inside the
/// engine's standard vertex. Those offsets are derived from [VertexLayout] and
/// not written down here, so a mesh vertex stays described in one place.
///
/// Slot 1 is the placements, stepping per instance.
///
/// The order of the two matters more than it looks. On Impeller and WebGL an
/// attribute is matched by *name*, so the order is presentation. On the
/// software backend the attributes are assembled in layout order and handed to
/// the stage as one list read by position — see `ParticleMeshVertexShader`,
/// which is written against exactly this order and says so.
library;

import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'particle_system.dart';

final class MeshParticleContributor extends PassContributor {
  MeshParticleContributor(
    this.particles, {
    required this.mesh,
    this.blend = BlendState.additive,
  }) : _state = PassState(
         primitiveType: PrimitiveType.triangle,
         polygonMode: PolygonMode.fill,
         cullMode: CullMode.none,
         blend: blend,
         depthWrite: false,
         depthCompare: CompareFunction.less,
       );

  /// Each particle takes its colour out of what is behind it: the
  /// background times one minus the particle's colour. Dark smoke, soot, a
  /// shadow on the water: what additive particles cannot draw, since adding
  /// can only brighten.
  ///
  /// **A particle's colour is how much it darkens**, per channel, and its
  /// alpha scales that, as it scales the light an additive one adds. White
  /// at full alpha blacks out what is behind it; a grey of 0.6 takes sixty
  /// per cent away. Fog fades it to nothing with distance, as it fades an
  /// additive one.
  ///
  /// **Multiplication is commutative**, as addition is, so a batch of these
  /// composites correctly in any order and the pool is still one unsorted
  /// draw. "Over" blending would need the particles sorted every frame; the
  /// six-way stage of `ParticleContributor` pays that for lit smoke.
  static const BlendState darkening = BlendState(
    sourceColorFactor: BlendFactor.zero,
    destinationColorFactor: BlendFactor.oneMinusSourceColor,
    sourceAlphaFactor: BlendFactor.zero,
    destinationAlphaFactor: BlendFactor.one,
  );

  final ParticleSystem particles;

  /// The shape every particle is a copy of, already on the device.
  ///
  /// One mesh for the whole system rather than one per effect. Two shapes are
  /// two instanced draws and therefore two contributors, which is cheap to
  /// arrange and honest about the cost.
  final DrawableGeometry mesh;

  /// How a particle meets what is behind it: [BlendState.additive], which
  /// adds light (fire, sparks, a glow), or [darkening], which takes it away.
  /// The fragment stage is the same for both: it hands back the particle's
  /// colour times its alpha, shaded by facing and faded by fog, and the
  /// blend decides whether that is light added or light removed.
  ///
  /// Unculled, depth-tested but never written either way, the same request
  /// the billboard path makes and for the same reasons: a particle mesh
  /// tumbles and is seen from every side, and the fragment stage shades by
  /// facing rather than by winding, so a back face is dim rather than
  /// absent.
  final BlendState blend;

  final PassState _state;

  static const String _infoBlock = 'ParticleMeshInfo';

  /// The mesh's own attributes, at their offsets inside a standard vertex.
  ///
  /// Derived rather than written out: `VertexLayout.standard` is where a mesh
  /// vertex is described, and a second copy of a stride would be a second thing
  /// to keep right.
  static final BufferLayout _meshSlot = BufferLayout(
    strideInBytes: VertexLayout.standard.strideInBytes,
    attributes: <InputAttribute>[
      InputAttribute(
        name: 'position',
        format: VertexFormat.float32x3,
        offsetInBytes: VertexLayout.standard.floatOffsetOf('position') * 4,
      ),
      InputAttribute(
        name: 'normal',
        format: VertexFormat.float32x3,
        offsetInBytes: VertexLayout.standard.floatOffsetOf('normal') * 4,
      ),
    ],
  );

  /// One placement per particle: where, what colour, how big.
  static const BufferLayout _instanceSlot = BufferLayout(
    strideInBytes: ParticleSystem.floatsPerInstance * 4,
    stepMode: VertexStepMode.instance,
    attributes: <InputAttribute>[
      InputAttribute(name: 'i_position', format: VertexFormat.float32x3),
      InputAttribute(
        name: 'i_color',
        format: VertexFormat.float32x4,
        offsetInBytes: 12,
      ),
      InputAttribute(
        name: 'i_scale',
        format: VertexFormat.float32,
        offsetInBytes: 28,
      ),
    ],
  );

  static final VertexLayoutSpec _layout = VertexLayoutSpec(<BufferLayout>[
    _meshSlot,
    _instanceSlot,
  ]);

  @override
  bool get isActive => particles.aliveCount > 0;

  @override
  void encode(ContributorFrame frame) {
    final view = frame.view;
    final viewProjection = frame.viewProjection;
    if (view == null || viewProjection == null) return;
    developer.Timeline.startSync('MeshParticleContributor.encode');

    final instances = _instances ??= Float32List(
      particles.capacity * ParticleSystem.floatsPerInstance,
    );
    final written = particles.writeInstances(instances);
    if (written == 0) {
      developer.Timeline.finishSync();
      return;
    }

    final vertexShader = _shader(frame, 'ParticleMeshVertex');
    final fragmentShader = _shader(frame, 'ParticleMesh');
    if (vertexShader == null || fragmentShader == null) {
      developer.Timeline.finishSync();
      return;
    }

    final encoder = frame.encoder;

    // Whatever drew last left its own pipeline and buffers bound, and this one
    // has two vertex buffers where everything else in the engine has one.
    encoder.clearBindings();
    encoder.bindPipeline(
      _pipeline ??= frame.device.createPipeline(
        vertexShader,
        fragmentShader,
        layout: _layout,
      ),
    );
    encoder.setState(_state);

    encoder.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
    encoder.bindVertexData(
      ByteData.sublistView(
        instances,
        0,
        written * ParticleSystem.floatsPerInstance,
      ),
      written,
      slot: 1,
    );
    encoder.bindIndexBuffer(mesh.indices, mesh.indexType, mesh.indexCount);

    encoder.bindUniformBlock(vertexShader, _infoBlock, <String, Float32List>{
      'view_projection': viewProjection.storage,
    });

    final fog = frame.settings.fog;
    final colour = fog.resolvedColor;
    _fog[0] = colour.x;
    _fog[1] = colour.y;
    _fog[2] = colour.z;
    view.camera.readViewOrigin(_eye);
    // The air as thick as it is at the camera: a height fog's falloff is not
    // integrated here — `FogSettings.densityAt` says what that costs.
    _fog[3] = fog.densityAt(_eye.y);
    _eyeData[0] = _eye.x;
    _eyeData[1] = _eye.y;
    _eyeData[2] = _eye.z;
    // The view axis and the lens, so the stage measures the fog from the
    // eye's plane through an orthographic camera rather than in rings round a
    // point the picture does not depend on — `P7`.
    view.camera.readForward(_eye);
    _forwardData
      ..[0] = _eye.x
      ..[1] = _eye.y
      ..[2] = _eye.z;
    _projectionData[0] = isOrthographic(viewProjection) ? 1.0 : 0.0;
    encoder.bindUniformBlock(fragmentShader, 'FogInfo', <String, Float32List>{
      'fog': _fog,
      'eye': _eyeData,
      'forward': _forwardData,
      'projection': _projectionData,
    });

    encoder.draw(instanceCount: written);
    frame.state.drawCalls++;
    frame.state.invalidatePipeline();
    developer.Timeline.finishSync();
  }

  /// Looks a stage up, and complains once if it is missing.
  ///
  /// Once rather than every frame: sixty identical lines a second is how a real
  /// message gets scrolled away, and silence is how the billboard path's
  /// misspelled stage name survived being written.
  ShaderHandle? _shader(ContributorFrame frame, String name) {
    final shader = frame.device.shaders[name];
    if (shader == null && _missing.add(name)) {
      assert(() {
        developer.log(
          'MeshParticleContributor: the shader bundle has no "$name"; '
          'no mesh particles will be drawn.',
          name: 'flutter3d_particles',
        );
        return true;
      }());
    }
    return shader;
  }

  final Set<String> _missing = <String>{};
  final Float32List _fog = Float32List(4);
  final Float32List _eyeData = Float32List(4);
  final Float32List _forwardData = Float32List(4);
  final Float32List _projectionData = Float32List(4);
  final vm.Vector3 _eye = vm.Vector3.zero();
  PipelineHandle? _pipeline;
  Float32List? _instances;

  @override
  void relinkShaders() => _pipeline = null;
}
