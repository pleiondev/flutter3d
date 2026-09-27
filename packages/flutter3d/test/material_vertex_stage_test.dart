/// `gfx-75n`: a material brings its own vertex stage.
///
///     flutter test test/material_vertex_stage_test.dart
///
/// **The ceiling this takes out.** Everything a material could say named a
/// *fragment* stage; the vertex side was `MeshVertex` and `MeshSkinnedVertex`
/// by fixed name, so vertex displacement, an ocean, wind and a per-material
/// morph hook were all outside what the engine could express. That is not a
/// missing row in a feature table — it is the thing that decides whether
/// somebody writes an effect or forks the engine.
///
/// The stage is supplied the way an application supplies one: a shader library
/// handed to `Renderer.create` as `materials:`, which layers over the backend's
/// own. Nothing here touches a bundle manifest, because an application cannot.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

/// A vertex stage that draws everything at half size in clip space.
///
/// Deliberately the smallest thing that is not a copy of `MeshVertex`: it
/// delegates to the engine's own stage for every varying and then moves the
/// clip position, which is what a displacement stage does and what nothing
/// outside the engine could do before. A real one would move the vertex in its
/// own space and recompute the normal; this one only has to be visible.
final class _HalfSizeStage implements CpuVertexShaderByIndex {
  const _HalfSizeStage(this._inner);

  final CpuVertexShaderByIndex _inner;

  @override
  int get varyingCount => _inner.varyingCount;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) =>
      runAt(-1, 0, a, bindings, out);

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings bindings,
    Float32List out,
  ) {
    final clip = _inner.runAt(vertexIndex, instanceIndex, a, bindings, out);
    return Vector4(clip.x * 0.5, clip.y * 0.5, clip.z, clip.w);
  }
}

/// The library an application would hand over, with [skinned] deciding whether
/// it ships the second half of the pair.
CpuShaderLibrary _materials({bool skinned = true}) {
  final builtin = builtinCpuShaders();
  return CpuShaderLibrary(<String, CpuStage>{
    'HalfSize': CpuStage.vertex(
      _HalfSizeStage(builtin['MeshVertex']!.vertex! as CpuVertexShaderByIndex),
    ),
    if (skinned)
      'HalfSizeSkinned': CpuStage.vertex(
        _HalfSizeStage(
          builtin['MeshSkinnedVertex']!.vertex! as CpuVertexShaderByIndex,
        ),
      ),
  });
}

/// The stock lighting model with a vertex stage bolted on, and without.
const LightingModel _plain = LightingModel('Plain', 'Pbr', usesMetallic: true);
const LightingModel _halved = LightingModel(
  'Halved',
  'Pbr',
  vertexShaderName: 'HalfSize',
  usesMetallic: true,
);

Future<List<int>> _draw({
  required LightingModel lighting,
  bool skinnedMesh = false,
  bool shipSkinnedStage = true,
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(
    device: device,
    materials: _materials(skinned: shipSkinnedStage),
  );

  final scene = Scene();
  final geometry = CuboidShape(
    size: Vector3.all(1.2),
  ).build(layout: skinnedMesh ? VertexLayout.skinned : VertexLayout.standard);
  final node = MeshNode(
    DeviceMesh.upload(device, geometry),
    Material(name: 'subject', lighting: lighting),
    name: 'subject',
  );
  if (skinnedMesh) {
    final joint = scene.add(SceneNode(name: 'joint'));
    node.skeleton = Skeleton(
      name: 'one bone',
      joints: <SceneNode>[joint],
      inverseBindMatrices: <Matrix4>[Matrix4.identity()],
    );
    node.skinReach = 1.5;
  }
  scene
    ..add(node)
    ..add(
      LightNode(intensity: 6.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 0.0, 4.0)
        ..lookAt(Vector3.zero()),
    );

  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: const RenderSettings(),
  );
  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i)];
}

/// How many pixels the lit subject covers.
///
/// **Sixty-four rather than "anything above the clear".** The first draft used
/// four, and both frames came back at 2304 — every pixel of a 48 by 48 frame —
/// because the composite lifts a black clear off zero and the measure was of
/// the tone map rather than of the cube. Sixty-four separates a lit face from
/// the background it sits on with room on either side.
int _covered(List<int> pixels) {
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i] > 64 || pixels[i + 1] > 64 || pixels[i + 2] > 64) count++;
  }
  return count;
}

/// How many pixels differ in any colour channel.
int _differing(List<int> a, List<int> b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) count++;
  }
  return count;
}

void main() {
  test('a material that supplies none draws what it always drew', () async {
    // **The half that lets this land**, and the reason the seam is a null field
    // rather than a new required one: a material saying nothing about its vertex
    // stage goes through the pipeline it has always gone through, which is also
    // why the seventy-eight goldens cannot move.
    final withSeam = await _draw(lighting: _plain);

    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3.all(1.2)).build(),
          ),
          Material(name: 'subject', lighting: _plain),
        ),
      )
      ..add(
        LightNode(intensity: 6.0)
          ..setPosition(2.0, 3.0, 4.0)
          ..lookAt(Vector3.zero()),
      )
      ..add(
        CameraNode()
          ..setPosition(0.0, 0.0, 4.0)
          ..lookAt(Vector3.zero()),
      );
    final frame = renderer.render(
      width: _size,
      height: _size,
      scene: scene,
      views: <RenderView>[
        RenderView(
          camera: scene.cameras.single,
          clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
        ),
      ],
      settings: const RenderSettings(),
    );
    final bytes = await device.readPixels(frame.frame);
    final without = <int>[
      for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
    ];

    expect(withSeam, without);
  });

  test('a material that supplies one draws through it', () async {
    // **The row's own acceptance.** The stage halves the clip position, so the
    // cube covers about a quarter of the pixels it did — a claim about the
    // stage having run rather than about any particular pixel.
    final plain = await _draw(lighting: _plain);
    final halved = await _draw(lighting: _halved);

    final before = _covered(plain);
    final after = _covered(halved);

    expect(before, greaterThan(0), reason: 'nothing was drawn at all');
    expect(after, greaterThan(0), reason: 'the stage drew nothing');
    expect(
      _differing(plain, halved),
      greaterThan(0),
      reason: 'the supplied stage did not reach the picture at all',
    );
    expect(
      after,
      lessThan(before ~/ 2),
      reason: 'the supplied stage did not halve anything: $after of $before',
    );
  });

  test('and on a skinned mesh as well', () async {
    // The other half of the pair. A material that drew correctly on a prop and
    // put a character back in its bind pose would pass every test above.
    final plain = await _draw(lighting: _plain, skinnedMesh: true);
    final halved = await _draw(lighting: _halved, skinnedMesh: true);

    expect(_covered(plain), greaterThan(0));
    expect(_covered(halved), lessThan(_covered(plain) ~/ 2));
  });

  test(
    'a material missing the skinned half says which name it wanted',
    () async {
      // Rather than silently drawing the bind pose, which is what a fallback to
      // the engine's own stage would have looked like.
      await expectLater(
        () => _draw(
          lighting: _halved,
          skinnedMesh: true,
          shipSkinnedStage: false,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('HalfSizeSkinned'), contains('Halved')),
          ),
        ),
      );
    },
  );

  test(
    'two materials that differ only in their vertex stage are two pipelines',
    () async {
      // The pipeline cache was keyed on the fragment stage's name, which was
      // complete while the vertex side was fixed. Without the vertex name in the
      // key the second material is handed the first one's pipeline, and which one
      // wins depends on draw order — the worst shape a bug can take.
      final device = CpuDevice(
        width: _size,
        height: _size,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      final renderer = Renderer.create(device: device, materials: _materials());
      final mesh = DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3.all(1.0)).build(),
      );

      final scene = Scene()
        ..add(
          MeshNode(mesh, Material(name: 'plain', lighting: _plain))
            ..setPosition(-1.2, 0.0, 0.0),
        )
        ..add(
          MeshNode(mesh, Material(name: 'halved', lighting: _halved))
            ..setPosition(1.2, 0.0, 0.0),
        )
        ..add(
          LightNode(intensity: 6.0)
            ..setPosition(2.0, 3.0, 4.0)
            ..lookAt(Vector3.zero()),
        )
        ..add(
          CameraNode()
            ..setPosition(0.0, 0.0, 5.0)
            ..lookAt(Vector3.zero()),
        );

      final frame = renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
        settings: const RenderSettings(),
      );

      // Two pipelines for two materials that share a fragment stage.
      expect(frame.pipelineSwitches, greaterThan(1));
    },
  );
}
