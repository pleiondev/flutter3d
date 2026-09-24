/// What moved during the exposure is smeared along the way it moved — `R6`.
///
///     dart test test/motion_blur_test.dart
///
/// Each frame here is the second of two: the first gives the frame history
/// a past, and the second is drawn after the scene or the camera moved. The
/// same two frames are drawn with the blur off and on, and the tests say
/// where the two differ — only where something moved, only along the way it
/// moved, and further for a longer shutter.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3, Vector4;

const int _width = 96;
const int _height = 64;

/// A spoke half a wheel long, turned [angle] about the view axis.
Quaternion _turned(double angle) =>
    Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), angle);

typedef _Staged = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  MeshNode spoke,
  CameraNode camera,
});

_Staged _staged() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final spoke = MeshNode(
    DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(3.0, 0.4, 0.4)).build(),
    ),
    Material(name: 'spoke', baseColor: Vector4(0.9, 0.8, 0.2, 1.0)),
  )..setPosition(0.0, 0.0, -5.0);
  final camera = CameraNode();
  final scene = Scene()
    ..add(spoke)
    ..add(
      LightNode(intensity: 6.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(camera);
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    spoke: spoke,
    camera: camera,
  );
}

Future<List<int>> _draw(_Staged it, RenderSettings settings) async {
  final frame = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings,
  );
  final bytes = await it.device.readPixels(frame.frame);
  return <int>[
    for (var i = 0; i < _width * _height * 4; i++) bytes!.getUint8(i),
  ];
}

/// The second of two frames, [move] applied between them.
Future<List<int>> _moved(
  RenderSettings settings,
  void Function(_Staged it) move,
) async {
  final it = _staged();
  await _draw(it, settings);
  move(it);
  return _draw(it, settings);
}

/// The frame without the blur, arranged to differ from the frame with it
/// by nothing else. Bloom off: its glow spreads the spoke over every row, and
/// the tests ask which rows the blur alone touched. The surface buffer on:
/// the blur reads it, and a frame that attaches it is not multisampled, so
/// without it every silhouette would count as a difference.
const RenderSettings _sharp = RenderSettings(
  bloom: BloomSettings(enabled: false),
  surfaceBuffer: true,
);

RenderSettings _blur({double shutter = 1.0}) => _sharp.copyWith(
  motionBlur: MotionBlurSettings(enabled: true, shutterFraction: shutter),
);

/// The pixels where [a] and [b] differ in any colour channel by more than
/// [by] levels.
List<(int, int)> _changed(
  List<int> a,
  List<int> b, {
  int by = 0,
}) => <(int, int)>[
  for (var y = 0; y < _height; y++)
    for (var x = 0; x < _width; x++)
      if (<int>[0, 1, 2].any(
        (c) =>
            (a[(y * _width + x) * 4 + c] - b[(y * _width + x) * 4 + c]).abs() >
            by,
      ))
        (x, y),
];

void main() {
  test('off by default, and nothing fills a velocity for it', () {
    final it = _staged();
    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: const RenderSettings(),
    );
    final ran = result.passes.map((p) => p.name);
    expect(ran, isNot(contains('camera velocity')));
    expect(ran, isNot(contains('motion blur')));
  });

  test('on, the velocity is filled without the temporal resolve', () {
    final it = _staged();
    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: _blur(),
    );
    final ran = result.passes.map((p) => p.name).toList();
    expect(ran, containsAllInOrder(<String>['camera velocity', 'motion blur']));
    expect(ran, isNot(contains('temporal resolve')));
  });

  test('a still scene is left exactly as it was', () async {
    final sharp = await _moved(_sharp, (_) {});
    final blurred = await _moved(_blur(), (_) {});
    expect(_changed(sharp, blurred), isEmpty);
  });

  test('motion-blur-spin: the rim streaks and the hub stays sharp', () async {
    // Mutation: return `centre` unconditionally from `MotionBlurShader`.
    // Nothing changes anywhere and the rim count is zero.
    void spin(_Staged it) => it.spoke.setRotation(_turned(0.6));
    final sharp = await _moved(_sharp, spin);
    final blurred = await _moved(_blur(), spin);
    final changed = _changed(sharp, blurred);

    double fromHub((int, int) p) => math.sqrt(
      math.pow(p.$1 + 0.5 - _width / 2, 2) +
          math.pow(p.$2 + 0.5 - _height / 2, 2),
    );
    final rim = changed.where((p) => fromHub(p) >= 14.0).length;
    // A level of tolerance at the hub: a sample that lands back on the pixel
    // itself is the same colour weighted again, which is the same answer to
    // within the rounding of the division.
    final hub = _changed(
      sharp,
      blurred,
      by: 1,
    ).where((p) => fromHub(p) < 1.5).length;
    // The tip is about twenty pixels out and turns through 0.6 of a radian:
    // twelve pixels of motion, six either side of it with the shutter open
    // the whole frame.
    expect(rim, greaterThan(40));
    // On the four pixels round the axle the spoke moves under half a pixel
    // either side, and nothing within reach moves far enough to cross them.
    // Three pixels out it already does: the spoke's long edges sweep about a
    // pixel there.
    expect(hub, 0);
  });

  test('a sideways move streaks along its rows and no further', () async {
    // Mutation: swap the two scales in `_encodeMotionBlur` (`scaleX` from the
    // height, `scaleY` from the width). The streak is still horizontal but
    // shorter; swapping `.rg` for `.gr` in the gather turns it vertical and
    // rows outside the spoke change.
    void slide(_Staged it) => it.spoke.setPosition(0.6, 0.0, -5.0);
    final sharp = await _moved(_sharp, slide);
    final blurred = await _moved(_blur(), slide);
    final changed = _changed(sharp, blurred);
    expect(changed.length, greaterThan(20));

    // The rows the spoke covers in the sharp frame — anything not the
    // background the corner shows — and one either side for its shaded
    // edge.
    final rows = <int>{
      for (var y = 0; y < _height; y++)
        for (var x = 0; x < _width; x++)
          if (<int>[
            0,
            1,
            2,
          ].any((c) => sharp[(y * _width + x) * 4 + c] != sharp[c]))
            y,
    };
    final top = rows.reduce(math.min) - 1;
    final bottom = rows.reduce(math.max) + 1;
    expect(bottom - top, lessThan(_height ~/ 3), reason: 'the spoke is thin');
    expect(
      changed.where((p) => p.$2 < top || p.$2 > bottom),
      isEmpty,
      reason: 'a horizontal motion smeared something vertically',
    );
  });

  test('a longer shutter smears further', () async {
    void slide(_Staged it) => it.spoke.setPosition(0.6, 0.0, -5.0);
    final sharp = await _moved(_sharp, slide);
    final quarter = _changed(sharp, await _moved(_blur(shutter: 0.25), slide));
    final whole = _changed(sharp, await _moved(_blur(), slide));
    expect(quarter, isNotEmpty);
    expect(whole.length, greaterThan(quarter.length));
  });

  test('a camera that pans blurs a scene that stood still', () async {
    // The camera's own velocity, with no object velocity drawn: the spoke
    // never moves.
    void pan(_Staged it) => it.camera.setPosition(0.4, 0.0, 0.0);
    final sharp = await _moved(_sharp, pan);
    final blurred = await _moved(_blur(), pan);
    expect(_changed(sharp, blurred).length, greaterThan(20));
  });

  test('no shutter is no pass', () {
    final it = _staged();
    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: _blur(shutter: 0.0),
    );
    final ran = result.passes.map((p) => p.name);
    expect(ran, isNot(contains('motion blur')));
    expect(ran, isNot(contains('camera velocity')));
  });
}
