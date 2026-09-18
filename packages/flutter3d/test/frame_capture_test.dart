/// `gfx-70n`: a frame captured pass by pass, with the pixels each one wrote.
///
///     flutter test test/frame_capture_test.dart
///
/// **What `FrameResult.passes` already does, and what it cannot.** `gfx-01n`
/// gave every pass its time, its draws, its triangles and its pipeline
/// switches, and the modeller shows them. That table answers "which pass is
/// slow". It cannot answer "why is the frame black", which is the question
/// actually asked, and no amount of timing will: a pass that ran in the usual
/// microseconds and wrote nothing looks exactly like one that worked.
///
/// The last test here is the acceptance in full — a pass is deliberately broken
/// and found from the capture alone, without looking at the scene, the settings
/// or the code that broke it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;

({CpuDevice device, Renderer renderer, Scene scene}) _built() {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.4)).build()),
        Material(name: 'cube', baseColor: Vector4(0.9, 0.5, 0.2, 1.0)),
        name: 'cube',
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
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
  );
}

Future<FrameCapture> _capture(
  ({CpuDevice device, Renderer renderer, Scene scene}) it, {
  RenderSettings settings = const RenderSettings(),
}) {
  final capture = it.renderer.captureNextFrame();
  it.renderer.render(
    width: _size,
    height: _size,
    scene: it.scene,
    views: <RenderView>[
      RenderView(
        camera: it.scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: settings,
  );
  return capture;
}

void main() {
  test('a capture names every pass the frame ran', () async {
    final capture = await _capture(_built());

    expect(capture.passes, isNotEmpty);
    expect(capture.passNamed('scene'), isNotNull);
    expect(capture.passNamed('composite'), isNotNull);
    expect(capture.width, _size);
  });

  test('and says what each one read and wrote', () async {
    // The names are the frame graph's own, which is what makes a capture
    // walkable: the pass that wrote a resource and the pass that read it are
    // joined by a string a reader can search for.
    final capture = await _capture(_built());
    final scene = capture.passNamed('scene')!;
    final composite = capture.passNamed('composite')!;

    expect(scene.writes, isNotEmpty);
    expect(
      composite.reads,
      contains(anyOf(scene.writes)),
      reason:
          'the composite reads nothing the scene wrote, so the capture cannot '
          'be walked from one pass to the next',
    );
  });

  test('and holds the pixels the scene pass wrote', () async {
    final capture = await _capture(_built());
    final scene = capture.passNamed('scene')!;
    final image = scene.images.firstWhere((i) => i.pixels != null);

    expect(image.width, _size);
    expect(image.height, _size);
    expect(image.isBlack, isFalse, reason: 'the scene pass drew nothing');
  });

  test(
    'a resource that cannot be read says why rather than going missing',
    () async {
      // **A capture with a gap in it is worse than no capture**, because the
      // reader assumes the pass wrote nothing. Tile memory cannot be read after
      // its pass, a multisampled attachment has no single value per pixel, and a
      // pass may simply not have provided a name this frame — three different
      // facts and three different answers.
      final capture = await _capture(_built());

      for (final pass in capture.passes) {
        for (final image in pass.images) {
          expect(
            image.pixels != null || (image.refused?.isNotEmpty ?? false),
            isTrue,
            reason:
                '${pass.name} left ${image.resource} with neither pixels nor '
                'a reason',
          );
        }
      }
    },
  );

  test('a deliberately broken pass is found from the capture alone', () async {
    // **The row's own acceptance.** The frame comes back black. Nothing below
    // looks at the scene, at the settings, or at what was done to break it: it
    // asks the capture which pass first left the picture black, and the answer
    // is the pass that was broken.
    //
    // What is broken here is the scene pass, by putting the camera where it can
    // see nothing and clearing to black — the shape a caller's own bug takes
    // when a matrix is wrong. The passes after it are all working perfectly and
    // all producing black, which is exactly why a table of times cannot find
    // this and a capture can.
    final it = _built();
    it.scene.cameras.single
      ..setPosition(0.0, 400.0, 0.0)
      ..lookAt(Vector3(0.0, 800.0, 0.0));

    final capture = await _capture(it);

    // The name is read off the capture rather than assumed, which is what a
    // reader does: find a pass whose output is black, then check that the one
    // before it was not.
    final blackFrom = <String>[
      for (final pass in capture.passes)
        if (pass.images.any((i) => i.pixels != null && i.isBlack)) pass.name,
    ];

    expect(blackFrom, isNotEmpty, reason: 'nothing in the frame is black');
    expect(
      blackFrom.first,
      'scene',
      reason:
          'the first pass with a black output is $blackFrom, so the capture '
          'points at the wrong one',
    );
  });

  test('a working frame does not accuse the scene pass', () async {
    // The control. Without it the test above passes on a capture that calls
    // every frame black.
    final capture = await _capture(_built());
    final scene = capture.passNamed('scene')!;

    expect(scene.images.where((i) => i.pixels != null && i.isBlack), isEmpty);
  });

  test('capturing is off unless it is asked for', () async {
    // The readback of every pass's output is far too expensive to leave on,
    // which is why this is a one-shot and not a setting.
    final it = _built();
    it.renderer.render(
      width: _size,
      height: _size,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.scene.cameras.single)],
      settings: const RenderSettings(),
    );

    // Asking now captures the *next* frame, not the one that just ran, so the
    // future is still waiting for a frame that has not happened.
    final capture = it.renderer.captureNextFrame();
    final raced = await Future.any(<Future<Object?>>[
      capture,
      Future<Object?>.delayed(Duration.zero, () => 'still waiting'),
    ]);

    expect(raced, 'still waiting');
  });
}
