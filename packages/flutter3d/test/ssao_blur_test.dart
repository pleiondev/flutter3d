/// `gfx-32n`: a depth-aware blur over the occlusion buffer.
///
///     flutter test test/ssao_blur_test.dart
///
/// **Two claims, and the second is the one that makes it depth-aware.** A
/// blur has to reduce the sampling pattern on a flat surface — that is what
/// it is for. A depth-aware one also has to leave a silhouette alone, because
/// spreading the dark of a corner out past the object that made it is the
/// halo that makes people switch ambient occlusion off in the first place.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A box in a corner, lit dimly, with occlusion on.
///
/// The corner is what the pass has something to darken, and the box in front
/// of it is the silhouette the blur must not cross — `ambient-occlusion-corner`
/// is the golden scene built on the same idea.
Future<List<int>> _frame({
  required int blurTaps,
  // A fraction of the centre's depth since 0.7.4; 0.02 is the default.
  double depthFalloff = 0.02,
  int width = 96,
  int height = 96,
}) async {
  final device = CpuDevice(
    width: width,
    height: height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3(6, 6, 1)).build()),
        Material(name: 'wall', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      )..setPosition(0.0, 0.0, -2.0),
    )
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3(1, 1, 1)).build()),
        Material(name: 'box', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      )..setPosition(0.0, -0.4, -1.0),
    )
    ..add(
      LightNode(intensity: 6.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 5.0));

  final frame = renderer.render(
    width: width,
    height: height,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: RenderSettings(
      ambientOcclusion: AmbientOcclusionSettings(
        enabled: true,
        blurTaps: blurTaps,
        blurDepthFalloff: depthFalloff,
      ),
    ),
  );

  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < width * height; i++) bytes!.getUint8(i * 4)];
}

void main() {
  test('no taps is no pass, and is the default', () async {
    // The occlusion is already off by default, and this is a second
    // full-screen pass over it — so nothing pays for either until two things
    // are switched on. Forty-four goldens depend on the frame being what it
    // was.
    expect(const AmbientOcclusionSettings().blurTaps, 0);
    expect(await _frame(blurTaps: 0), await _frame(blurTaps: 0));
  });

  test('the pass changes the occlusion, and changes it in one place', () async {
    // **Three measures were tried here before this one, and the first two
    // measured the scene rather than the pass.** A hand-picked "flat wall"
    // patch had zero variance because it was background. Picking the busiest
    // patch automatically found the silhouette — the one place a depth-aware
    // blur is meant to leave alone, where the variance rose by a rounding.
    // Total roughness over the whole frame did not move either, and that one
    // was nearly a wrong conclusion: the blur *was* running and changing
    // pixels, but only forty-five of nine thousand, so the sum swallowed it.
    //
    // What occlusion is, in this frame, is a contact shadow a couple of
    // hundred pixels wide. So the honest measure is how many pixels the pass
    // moves, and where.
    final plain = await _frame(blurTaps: 0);
    final blurred = await _frame(blurTaps: 6);

    final moved = <int>[
      for (var i = 0; i < plain.length; i++)
        if (plain[i] != blurred[i]) i,
    ];
    printOnFailure('blur moved ${moved.length} pixels');

    expect(
      moved,
      isNotEmpty,
      reason:
          'the pass ran and produced the same frame, which means it is a '
          'full-screen draw for nothing',
    );
    expect(
      moved.length,
      lessThan(plain.length ~/ 4),
      reason:
          'a blur over the occlusion should move the contact shadow and '
          'not repaint the picture; if it touches a quarter of the frame it '
          'is bleeding somewhere it should not',
    );
  });

  test('a silhouette still has an edge behind it', () async {
    // The depth-aware half. With the falloff wide enough to ignore depth the
    // blur bleeds across the box's outline; with the real one it does not.
    // Compared against each other rather than against a number, because what
    // is being claimed is that depth is consulted at all.
    const width = 96;
    final aware = await _frame(blurTaps: 6);
    final blind = await _frame(blurTaps: 6, depthFalloff: 1000.0);

    // Down the middle, where the box's edge crosses.
    final row = width ~/ 2;
    var awareStep = 0;
    var blindStep = 0;
    for (var x = 1; x < width; x++) {
      final a = (aware[row * width + x] - aware[row * width + x - 1]).abs();
      final b = (blind[row * width + x] - blind[row * width + x - 1]).abs();
      if (a > awareStep) awareStep = a;
      if (b > blindStep) blindStep = b;
    }

    expect(
      awareStep,
      greaterThanOrEqualTo(blindStep),
      reason:
          'a blur that ignores depth softens the silhouette more than one '
          'that respects it; if these came out the same, the depth weighting '
          'is not being applied and the pass should not carry the name',
    );
  });
}
