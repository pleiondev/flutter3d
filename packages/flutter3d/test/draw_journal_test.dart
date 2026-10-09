/// `P12`: every draw of one frame written down, when somebody asked for it.
///
///     flutter test test/draw_journal_test.dart
///
/// The counters on `FrameResult.passes` say a pass drew forty things; the
/// journal says which forty, with what. It costs an allocation per draw, so it
/// is on for the one captured frame and off in every other — and these tests
/// hold both halves of that, plus the arithmetic that makes the list honest:
/// the draws a pass described and the draws it only counted add up to the
/// draws it reported.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 24;

({CpuDevice device, Renderer renderer, Scene scene, DeviceMesh mesh}) _built() {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final mesh = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3.all(1.4)).build(),
  );
  final scene = Scene()
    ..add(
      MeshNode(
        mesh,
        RenderMaterial(
          name: 'crate',
          baseColor: LinearColor.fromSrgb(0.9, 0.5, 0.2, 1.0),
        ),
        name: 'crate',
      ),
    )
    ..add(
      LightNode(intensity: 6.0 * Photometric.legacyUnit)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 0.0, 4.0)
        ..lookAt(Vector3.zero()),
    );
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    mesh: mesh,
  );
}

Future<FrameCapture> _capture(
  ({CpuDevice device, Renderer renderer, Scene scene, DeviceMesh mesh}) it, {
  bool draws = false,
  Float32List? Function(TextureHandle texture)? readFloats,
}) {
  final capture = it.renderer.captureNextFrame(
    draws: draws,
    readFloats: readFloats,
  );
  it.renderer.render(
    width: _size,
    height: _size,
    scene: it.scene,
    views: <RenderView>[
      RenderView(
        camera: it.scene.cameras.single,
        clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
  );
  return capture;
}

void main() {
  test(
    'a journaled frame names the mesh and material each draw used',
    () async {
      final it = _built();
      final capture = await _capture(it, draws: true);

      final crate = capture.draws.where((d) => d.kind == 'mesh').single;
      expect(crate.pass, 'scene');
      expect(crate.mesh, 'crate');
      expect(crate.material, 'crate');
      expect(crate.vertices, it.mesh.vertexCount);
      expect(crate.indices, it.mesh.indexCount);
      expect(crate.triangles, it.mesh.indexCount ~/ 3);
      expect(crate.uniforms['baseColor'], <Object>[
        closeTo(0.9, 1e-6),
        closeTo(0.5, 1e-6),
        closeTo(0.2, 1e-6),
        1.0,
      ]);
      expect(crate.uniforms['mvp'], hasLength(16));
      expect(crate.state['cull'], 'back');
      // Mutation: recording `draws.length` before the add, or the pass before
      // `beginPass`, numbers every draw zero or files it under the wrong pass.
      expect(
        capture.draws.map((d) => d.index),
        List<int>.generate(capture.draws.length, (i) => i),
      );
    },
  );

  test(
    'described and undescribed draws add up to what each pass counted',
    () async {
      // **The journal does not describe a full-screen triangle**, and must not
      // pretend the pass drew nothing either. Mutation: dropping `endPass`
      // leaves `undetailedDraws` empty, and the composite's draws vanish from a
      // list that claims to be the frame's.
      final capture = await _capture(_built(), draws: true);

      for (final pass in capture.passes) {
        final described = capture.draws
            .where((d) => d.pass == pass.name)
            .length;
        expect(
          described + (capture.undetailedDraws[pass.name] ?? 0),
          pass.drawCalls,
          reason: 'pass ${pass.name}',
        );
      }
      expect(capture.passNamed('composite')!.drawCalls, greaterThan(0));
      expect(capture.undetailedDraws, contains('composite'));
    },
  );

  test('a capture that did not ask for draws journals none', () async {
    // The journal is for the one frame; the frame after it pays nothing.
    // Mutation: leaving `passState.journal` set from `_captureDraws` without
    // clearing it between requests journals every later capture too.
    final it = _built();
    await _capture(it, draws: true);
    final plain = await _capture(it);

    expect(plain.draws, isEmpty);
    expect(plain.undetailedDraws, isEmpty);
    expect(plain.passNamed('scene')!.drawCalls, greaterThan(0));
  });

  test('a capture carries each pass its cost', () async {
    final capture = await _capture(_built());
    final scene = capture.passNamed('scene')!;

    expect(scene.drawCalls, greaterThan(0));
    expect(scene.triangles, greaterThan(0));
  });

  test('readFloats puts each output its own floats beside its bytes', () async {
    // On the software backend, whose targets are floats already: what lets a
    // NaN be told apart from the byte it clamps to.
    final it = _built();
    final capture = await _capture(it, readFloats: it.device.readHdrPixels);
    final image = capture
        .passNamed('scene')!
        .images
        .firstWhere((i) => i.pixels != null);

    expect(image.floats, isNotNull);
    expect(image.floats!.length, image.width * image.height * 4);
    final plain = await _capture(it);
    expect(
      plain.passNamed('scene')!.images.every((i) => i.floats == null),
      isTrue,
    );
  });
}
