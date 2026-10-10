/// Under reversed depth the near plane is fitted to what a view draws
/// (`PassContributor.boundsFor`): particles say where they are, so a scene
/// with particles in it is fitted rather than drawn with the camera's plane,
/// and the plane stops in front of the nearest particle rather than cutting
/// it.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
// `debugFittedNears` is the renderer's test seam, not its API.
import 'package:flutter3d_core/src/engine/render/renderer.dart'
    show RendererInternals;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;

/// One particle [size] metres across, [ahead] metres in front of the camera,
/// before a wall forty metres out.
ParticleSystem _one({required double ahead, double size = 2.0}) =>
    ParticleSystem(capacity: 1)..burst(
      ParticleEffect(
        count: 1,
        emitter: const SphereEmitter(speed: Range.exact(0.0)),
        lifetime: const Range.exact(5.0),
        size: Range.exact(size),
        color: Vector4(0.8, 0.5, 0.2, 1.0),
      ),
      Vector3(0.0, 0.0, -ahead),
    );

/// The near plane the scene pass was drawn with, for a wall forty metres out
/// and whatever [contributor] draws, under reversed depth.
double _fittedNear(
  CpuDevice device,
  PassContributor Function(CpuDevice device) contributor,
) {
  final camera = CameraNode();
  final scene = Scene()
    ..add(camera)
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(80.0, 80.0, 1.0)).build(),
        ),
        RenderMaterial(
          lighting: LightingModel.unlit,
          baseColor: LinearColor.fromSrgb(0.2, 0.2, 0.2, 1.0),
        ),
      )..setPosition(0.0, 0.0, -40.0),
    );
  final renderer = Renderer.create(device: device)
    ..renderSteps.addContributor(contributor(device));
  renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(
      tonemap: false,
      bloom: BloomSettings(enabled: false),
      reversedDepth: true,
    ),
  );
  return renderer.debugFittedNears.single;
}

CpuDevice _device() => CpuDevice(
  width: _size,
  height: _size,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  final authored = CameraNode().projection.near;

  test('billboards are fitted to, and the plane stops in front of them', () {
    // Mutation: answer null from `ParticleContributor.boundsFor`, the
    // default — the fit gives up and the plane is the camera's own.
    // Mutation: the quad's half-size instead of its half-diagonal — a quad
    // turned on the view axis reaches past it, and the plane cuts a corner
    // off a particle at the lens.
    final particles = _one(ahead: 5.0);
    final near = _fittedNear(
      _device(),
      (device) => ParticleContributor(particles),
    );
    expect(near, greaterThan(authored));
    // A two-metre quad's corner is 2 · √½ = 1.41 m from its centre, and can
    // come that much nearer along the view axis; the fit's margin takes the
    // plane a little nearer still.
    expect(near, lessThanOrEqualTo(5.0 - 2.0 * 0.70711));
  });

  test('mesh particles are fitted to by the mesh scaled by their size', () {
    // Mutation: answer null from `MeshParticleContributor.boundsFor`.
    // Mutation: the particle's centre alone — the cube's near face, a metre
    // nearer, is cut.
    final particles = _one(ahead: 5.0);
    final near = _fittedNear(
      _device(),
      (device) => MeshParticleContributor(
        particles,
        mesh: DeviceMesh.upload(device, CuboidShape().build()),
      ),
    );
    expect(near, greaterThan(authored));
    // A unit cube scaled by 2: its near face is a metre in front.
    expect(near, lessThanOrEqualTo(4.0));
  });

  test('a system with nothing alive is not asked, and the wall is fitted '
      'to', () {
    final near = _fittedNear(
      _device(),
      (device) => ParticleContributor(ParticleSystem(capacity: 1)),
    );
    expect(near, greaterThan(30.0));
  });
}
