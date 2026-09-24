/// `gfx-34n`: a lens, and the circle of confusion that follows from it.
///
///     flutter test test/depth_of_field_test.dart
///
/// **The arithmetic is held against the thin-lens equation, not against a
/// recorded picture.** A golden image of a blur says the blur has not changed;
/// it does not say the blur is a lens. These tests say what the equation says:
/// halve the f-number and the circle doubles exactly, double the focal length
/// and it quadruples, and at the focus distance it is zero. Somebody who knows
/// what f/1.4 does to a background can check the engine against what they
/// know.
///
/// The rendering tests then say the equation reaches the frame — that a wall
/// twelve metres back moves when the lens is opened, that a narrower aperture
/// moves less of it, and that the plane in focus does not move at all.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 128;

/// Full-frame 35mm, the default — and what makes a focal length in
/// millimetres mean anything at all.
const double _sensor = 0.036;

/// What the encoder hands the shader: texels across the sensor's width.
const double _texelsPerMetre = _size / _sensor;

/// An 85mm portrait lens wide open, which is what a depth of field looks like
/// when somebody wants one.
const DepthOfFieldSettings _portrait = DepthOfFieldSettings(
  enabled: true,
  focusDistance: 4.0,
  focalLength: 0.085,
  aperture: 1.4,
);

/// The circle at [depth] for a lens, as a radius in texels — the CPU
/// backend's own arithmetic, reached directly.
double _circle(
  double depth, {
  double focusDistance = 4.0,
  double focalLength = 0.085,
  double aperture = 1.4,
  double maxRadius = 1e9,
}) => DepthOfFieldShader.circleOfConfusion(
  depth,
  focusDistance: focusDistance,
  focalLength: focalLength,
  aperture: aperture,
  maxRadius: maxRadius,
  texelsPerMetre: _texelsPerMetre,
);

/// A ball at the focus distance and a wall well behind it.
///
/// Lit rather than unlit, because the surface buffer this pass reads its depth
/// from is written by the lighting stages.
Future<List<int>> _frame(
  DepthOfFieldSettings lens, {
  Set<String> disabled = const <String>{},
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.5).build()),
        Material(name: 'near', baseColor: Vector4(0.9, 0.2, 0.2, 1.0)),
      )..setPosition(-0.9, 0.0, 0.0),
    )
    ..add(
      MeshNode(
        // The front face lands at eleven and a half metres: the cuboid is a
        // metre deep and its centre is eight back from the origin.
        DeviceMesh.upload(device, CuboidShape(size: Vector3(6, 6, 1)).build()),
        Material(name: 'far', baseColor: Vector4(0.1, 0.8, 0.3, 1.0)),
      )..setPosition(0.0, 0.0, -8.0),
    )
    ..add(
      LightNode(intensity: 6.0)
        ..setPosition(3.0, 3.0, 5.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));

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
    settings: RenderSettings(depthOfField: lens, disabledPasses: disabled),
  );

  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i)];
}

/// How many pixels differ in any colour channel.
int _changed(List<int> a, List<int> b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) count++;
  }
  return count;
}

void main() {
  group('the thin-lens equation', () {
    test('at the focus distance the circle is a point', () {
      expect(_circle(4.0), 0.0);
    });

    test('halving the f-number doubles the circle, exactly', () {
      // The f-number divides, so this is exact rather than approximate — and
      // it is the direction a photographer expects. A "blur amount" slider
      // between zero and one would run the other way.
      final atFour = _circle(10.0, aperture: 4.0);
      expect(_circle(10.0, aperture: 2.0), closeTo(atFour * 2.0, 1e-9));
      expect(_circle(10.0, aperture: 8.0), closeTo(atFour / 2.0, 1e-9));
    });

    test('doubling the focal length all but quadruples the circle', () {
      // Squared in the numerator, so four — and then a little more, because
      // the focal length is in the denominator too as `focus - focal`. The
      // excess is stated rather than tolerated: at four metres a 170mm lens
      // gives 4.05 times the circle of an 85mm one, and a test that let
      // `closeTo(4.0, 0.1)` stand would pass just as happily on arithmetic
      // that had the second term wrong.
      final short = _circle(10.0, focalLength: 0.085);
      final long = _circle(10.0, focalLength: 0.17);
      expect(long / short, closeTo(4.0 * (4.0 - 0.085) / (4.0 - 0.17), 1e-9));
    });

    test('either side of focus spreads, and further is more', () {
      expect(_circle(2.0), greaterThan(0.0), reason: 'in front spreads too');
      expect(_circle(40.0), greaterThan(_circle(6.0)));
    });

    test('the far field approaches a limit rather than growing forever', () {
      // As depth goes to infinity `|d - focus| / d` goes to one, so the circle
      // settles at half of `focal^2 / (N * (focus - focal))` in texels. A
      // formula that kept growing would ask for a kernel the width of the
      // screen to draw a skybox.
      const focus = 4.0;
      const focal = 0.085;
      const fnumber = 1.4;
      final limit =
          focal * focal / (fnumber * (focus - focal)) * 0.5 * _texelsPerMetre;

      expect(_circle(1e9), closeTo(limit, limit * 1e-6));
      expect(_circle(1e9), lessThan(limit));
    });

    test('the radius is clamped, because a gather has a budget', () {
      // The optics are happy to ask for a circle wider than the taps that are
      // there — this lens wants two and a third texels at infinity. Clamping
      // shows as a background that stops getting softer, which is the failure
      // worth having.
      expect(_circle(1e9), greaterThan(1.0));
      expect(_circle(1e9, maxRadius: 1.0), 1.0);
    });

    test('nothing drawn is infinitely far, so the sky blurs as far does', () {
      // The cleared background of the surface buffer reads zero. Until 0.7.4
      // that meant no circle, and a lens focused on a face kept the horizon
      // behind it sharp. The worry that answer was guarding against — a halo
      // around every silhouette against the sky — is the gather's to prevent,
      // and it does now: a sharp sample in front of the blurred sky does not
      // reach it.
      expect(_circle(0.0), closeTo(_circle(1e9), 1e-6));
      expect(_circle(-3.0), closeTo(_circle(1e9), 1e-6));
    });

    test('the blur is a share of the picture, not a count of pixels', () {
      // Texels per metre carries the frame's width, so the same lens on a
      // frame twice as wide draws a circle twice as many texels across — the
      // same photograph, larger. This is what lets `gfx-35n` drop the
      // resolution without changing what is in focus.
      final wide = DepthOfFieldShader.circleOfConfusion(
        12.0,
        focusDistance: 4.0,
        focalLength: 0.085,
        aperture: 1.4,
        maxRadius: 1e9,
        texelsPerMetre: _texelsPerMetre * 2.0,
      );
      expect(wide, closeTo(_circle(12.0) * 2.0, 1e-9));
    });
  });

  group('the lens in a frame', () {
    test('off by default, and off is the frame it always was', () async {
      expect(const DepthOfFieldSettings().enabled, isFalse);
      final plain = await _frame(const DepthOfFieldSettings());
      expect(plain, await _frame(const DepthOfFieldSettings()));
    });

    test('a lens wide open changes the picture', () async {
      final plain = await _frame(const DepthOfFieldSettings());
      final lensed = await _frame(_portrait);

      expect(
        _changed(plain, lensed),
        greaterThan(0),
        reason:
            'a pass that gathers two dozen taps a pixel and changes nothing '
            'is a draw call and nothing else',
      );
    });

    test('a narrower aperture moves fewer pixels than a wider one', () async {
      // The claim of the whole row, seen from outside: the f-number decides
      // how much of the frame leaves focus, and it decides it in the direction
      // the number means.
      final plain = await _frame(const DepthOfFieldSettings());
      final wide = await _frame(_portrait);
      final narrow = await _frame(_portrait.copyWith(aperture: 16.0));

      expect(_changed(plain, narrow), lessThan(_changed(plain, wide)));
    });

    test('the plane in focus is the plane that does not move', () async {
      // Focused on the wall's front face rather than on the ball, and sampled
      // on the wall away from the ball's silhouette. The circle there is zero
      // by the equation, so the pass takes its early exit and the pixel comes
      // back byte for byte — which is the check that a gather is not quietly
      // averaging a neighbourhood it was told to leave alone.
      final plain = await _frame(const DepthOfFieldSettings());
      final onWall = await _frame(_portrait.copyWith(focusDistance: 11.5));

      const x = _size ~/ 4;
      const y = _size ~/ 4;
      const at = (y * _size + x) * 4;
      expect(
        <int>[onWall[at], onWall[at + 1], onWall[at + 2]],
        <int>[plain[at], plain[at + 1], plain[at + 2]],
      );
    });

    test('the pass takes its name out of the graph when told to', () async {
      // The switch `gfx-31n` added, applied to the newest pass: a name in
      // `disabledPasses` is a pass that did not run, and the frame is byte for
      // byte the one the lens was never in.
      final plain = await _frame(const DepthOfFieldSettings());
      final lensed = await _frame(_portrait);
      final switchedOff = await _frame(
        _portrait,
        disabled: const <String>{'depth of field'},
      );

      expect(
        _changed(plain, lensed),
        greaterThan(0),
        reason: 'a switch for a pass that does nothing proves nothing',
      );
      expect(switchedOff, plain);
    });

    test('the radius bound reaches the frame, not just the arithmetic', () {
      // `maxRadius` is the one number here that is a budget rather than a
      // lens, and a bound that only ever held inside `circleOfConfusion`
      // would be a bound on nothing. Clamped to under half a texel there is
      // no circle left to gather, so the pass must take the same early exit
      // it takes for a pixel in focus — which is the strongest statement
      // available about what the bound does to a frame.
      expect(_circle(1e9, maxRadius: 0.25), 0.25);
    });

    test('a clamped lens leaves the frame alone', () async {
      final plain = await _frame(const DepthOfFieldSettings());
      final clamped = await _frame(_portrait.copyWith(maxRadius: 0.25));

      expect(
        _changed(plain, clamped),
        0,
        reason:
            'every circle in the frame is under half a texel, so every pixel '
            'is in focus as far as the gather is concerned',
      );
    });
  });
}
