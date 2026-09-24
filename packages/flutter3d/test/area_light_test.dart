/// A rectangle lights a room the way a window does — `gfx-77n`.
///
///     flutter test test/area_light_test.dart
///
/// **The fourth light type, and the first that is not punctual.** The other
/// three put all their light through one point, so what reaches a surface is a
/// single cosine and a falloff. A rectangle has extent: what reaches a surface
/// is an integral over the panel, and the shape of that integral is the whole
/// difference between a room lit by a window and a room lit by a bright dot
/// with a window painted behind it.
///
/// The diffuse half is exact and this file proves it against a reference: a
/// brute-force quadrature of the same rectangle, written independently in the
/// test and agreeing with the closed form to a fraction of a per cent. That is
/// the row's own acceptance and it is the check worth having, because a form
/// factor is four `acos` calls that look equally plausible whichever way the
/// signs go.
///
/// The specular half is the representative point, which is an approximation and
/// is tested for the property it is chosen for rather than against a reference:
/// the highlight follows the panel's orientation.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// The irradiance a rectangle of unit radiance delivers to [at] with normal
/// [n], by summing over [steps]² patches of it.
///
/// **Written from the definition, not from the thing it checks.** Each patch
/// contributes `cos(surface) * cos(panel) / r²` times its own area, which is
/// the integral a form factor is a closed form of. Nothing here is shared with
/// `rectangleFormFactor`; that is the point of it.
double _integrateRectangle(
  Vector3 at,
  Vector3 n, {
  required Vector3 centre,
  required Vector3 halfWidth,
  required Vector3 halfHeight,
  int steps = 400,
}) {
  final panelNormal = halfWidth.cross(halfHeight)..normalize();
  final patchArea =
      (halfWidth.length * 2.0 / steps) * (halfHeight.length * 2.0 / steps);

  var total = 0.0;
  for (var i = 0; i < steps; i++) {
    // Patch centres rather than corners, which is midpoint quadrature and
    // converges as the square of the step rather than linearly.
    final u = (i + 0.5) / steps * 2.0 - 1.0;
    for (var j = 0; j < steps; j++) {
      final v = (j + 0.5) / steps * 2.0 - 1.0;
      final point = centre + halfWidth * u + halfHeight * v;
      final toPoint = point - at;
      final distance2 = toPoint.length2;
      if (distance2 < 1e-12) continue;
      final direction = toPoint.normalized();
      final cosSurface = n.dot(direction);
      // The panel emits from the face its normal points out of; the other side
      // is dark, which is what makes it a window rather than a glowing sheet.
      final cosPanel = -panelNormal.dot(direction);
      if (cosSurface <= 0.0 || cosPanel <= 0.0) continue;
      total += cosSurface * cosPanel / distance2 * patchArea;
    }
  }
  return total;
}

List<Vector3> _cornersFrom(
  Vector3 at, {
  required Vector3 centre,
  required Vector3 halfWidth,
  required Vector3 halfHeight,
}) {
  final toCentre = centre - at;
  return <Vector3>[
    toCentre - halfWidth - halfHeight,
    toCentre + halfWidth - halfHeight,
    toCentre + halfWidth + halfHeight,
    toCentre - halfWidth + halfHeight,
  ];
}

({CpuDevice device, Renderer renderer}) _engine() {
  final it = cpuTestDevice(width: _width, height: _height);
  return (
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

/// A floor with one rectangle above it, facing down.
///
/// The panel is rolled about its own normal by [roll] radians, which is the
/// degree of freedom a scalar size cannot carry and the one the specular test
/// turns.
({Scene scene, CameraNode camera}) _room({
  double roll = 0.0,
  double panelWidth = 2.0,
  double panelHeight = 0.4,
  double roughness = 0.12,
}) {
  final scene = Scene()..ambientIntensity = 0.0;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(12.0, 0.4, 12.0)).build(),
      ),
      Material(
        name: 'floor',
        baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
        metallic: 0.0,
        roughness: roughness,
      ),
      name: 'floor',
    )..setPosition(0.0, -0.2, 0.0),
  );

  // Facing down is the node's local −Z pointing at the floor, so the node is
  // pitched a quarter turn; the roll then spins the panel in its own plane.
  scene.add(
    LightNode(type: LightType.area, intensity: 12.0, name: 'window')
      ..width = panelWidth
      ..height = panelHeight
      ..setPosition(0.0, 2.0, 0.0)
      ..setRotationYawPitchRoll(0.0, -math.pi / 2.0, roll),
  );

  final camera = CameraNode()
    ..setPosition(0.0, 1.5, -4.0)
    ..lookAt(Vector3.zero());
  return (scene: scene, camera: camera);
}

Future<Uint8List> _draw(({Scene scene, CameraNode camera}) room) async {
  final engine = _engine();
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = await engine.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

void main() {
  group('the diffuse half is exact', () {
    test('the closed form matches a brute-force integration', () {
      // Five arrangements rather than one, because the four terms of the sum
      // cancel differently as the panel moves off the axis, and a sign error in
      // one edge survives a test that only ever looks straight up at it.
      final cases = <({String name, Vector3 at, Vector3 n, Vector3 centre})>[
        (
          name: 'straight below the middle',
          at: Vector3.zero(),
          n: Vector3(0.0, 1.0, 0.0),
          centre: Vector3(0.0, 2.0, 0.0),
        ),
        (
          name: 'off to one side',
          at: Vector3.zero(),
          n: Vector3(0.0, 1.0, 0.0),
          centre: Vector3(1.5, 2.0, 0.0),
        ),
        (
          name: 'off the other axis',
          at: Vector3.zero(),
          n: Vector3(0.0, 1.0, 0.0),
          centre: Vector3(0.0, 2.0, -1.2),
        ),
        (
          name: 'a long way off, where the panel is nearly a point',
          at: Vector3.zero(),
          n: Vector3(0.0, 1.0, 0.0),
          centre: Vector3(0.0, 9.0, 0.0),
        ),
        (
          name: 'close enough to fill much of the sky',
          at: Vector3.zero(),
          n: Vector3(0.0, 1.0, 0.0),
          centre: Vector3(0.0, 0.6, 0.0),
        ),
      ];

      final halfWidth = Vector3(0.8, 0.0, 0.0);
      final halfHeight = Vector3(0.0, 0.0, 0.5);

      for (final it in cases) {
        final reference = _integrateRectangle(
          it.at,
          it.n,
          centre: it.centre,
          halfWidth: halfWidth,
          halfHeight: halfHeight,
        );
        final closed = rectangleFormFactor(
          _cornersFrom(
            it.at,
            centre: it.centre,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
          ),
          it.n,
        );

        // Relative, because the five cases span two orders of magnitude: the
        // panel overhead delivers about a steradian's worth and the one at nine
        // metres a fiftieth of that, and one absolute tolerance would either
        // pass everything or fail the small case on quadrature noise.
        expect(
          (closed - reference).abs() / reference,
          lessThan(0.005),
          reason:
              '${it.name}: closed form $closed against reference $reference',
        );
      }
    });

    test('the panel is dark on its back', () {
      // One-sided by construction rather than by a flag: seen from behind, the
      // four edges wind the other way and the sum comes out negative, which the
      // clamp turns into nothing. A two-sided panel would light the floor above
      // a ceiling window, which is not what a window does.
      final halfWidth = Vector3(0.8, 0.0, 0.0);
      final halfHeight = Vector3(0.0, 0.0, 0.5);
      final above = rectangleFormFactor(
        _cornersFrom(
          Vector3(0.0, 3.0, 0.0),
          centre: Vector3(0.0, 2.0, 0.0),
          halfWidth: halfWidth,
          halfHeight: halfHeight,
        ),
        Vector3(0.0, -1.0, 0.0),
      );
      expect(above, 0.0);
    });

    test('a panel of no area delivers nothing', () {
      // Not a NaN, which is the other thing a degenerate cross product gives
      // and the one that spreads through the bloom to the whole frame.
      final zero = rectangleFormFactor(
        _cornersFrom(
          Vector3.zero(),
          centre: Vector3(0.0, 2.0, 0.0),
          halfWidth: Vector3.zero(),
          halfHeight: Vector3.zero(),
        ),
        Vector3(0.0, 1.0, 0.0),
      );
      expect(zero, 0.0);
    });

    test('a panel rated in lumens sends out those lumens', () {
      // The flux is measured, not assumed: every patch of a large hemisphere
      // in front of the panel receives `radiance × form factor`, with the
      // radiance the shader gives it, `intensity / area`, and the patches sum
      // to what the panel emits. A Lambertian panel emits `π` times its axial
      // intensity, so that is what [Photometric.toLumens] has to say.
      //
      // Mutation: rate the panel over `2π`, the figure for a source equally
      // bright at every angle. The panel then emits half its rating.
      final halfWidth = Vector3(0.3, 0.0, 0.0);
      final halfHeight = Vector3(0.0, 0.0, 0.2);
      final area = halfWidth.cross(halfHeight).length * 4.0;
      const intensity = 1.0;
      final radiance = intensity / area;

      const radius = 40.0;
      const rings = 180;
      const segments = 90;
      var flux = 0.0;
      for (var i = 0; i < rings; i++) {
        // The panel emits along −Y, `cross(halfWidth, halfHeight)`.
        final theta = (i + 0.5) / rings * math.pi / 2.0;
        final ring = math.sin(theta) * (math.pi / 2.0 / rings);
        for (var j = 0; j < segments; j++) {
          final phi = (j + 0.5) / segments * 2.0 * math.pi;
          final direction = Vector3(
            math.sin(theta) * math.cos(phi),
            -math.cos(theta),
            math.sin(theta) * math.sin(phi),
          );
          final at = direction.scaled(radius);
          final received =
              radiance *
              rectangleFormFactor(
                _cornersFrom(
                  at,
                  centre: Vector3.zero(),
                  halfWidth: halfWidth,
                  halfHeight: halfHeight,
                ),
                -direction,
              );
          flux +=
              received * radius * radius * ring * (2.0 * math.pi / segments);
        }
      }

      expect(flux / intensity, closeTo(math.pi, 0.01 * math.pi));
      expect(
        Photometric.toLumens(intensity, type: LightType.area) /
            Photometric.toCandela(intensity),
        closeTo(flux / intensity, 0.01 * math.pi),
        reason: 'the rating and what the shader sends out disagree',
      );
      expect(
        Photometric.fromLumens(
          Photometric.toLumens(intensity, type: LightType.area),
          type: LightType.area,
        ),
        closeTo(intensity, 1e-9),
      );
    });
  });

  group('the panel lights a floor', () {
    test('the falloff away from the panel is soft and monotone', () async {
      final pixels = await _draw(_room());

      // Read along one row of the floor, outward from under the panel. A
      // punctual light gives the same shape, so what this catches is not the
      // effect but its absence: a form factor with a sign wrong somewhere is
      // not merely dimmer, it is blotchy, and a monotone run of samples is the
      // cheapest statement that it is not.
      final row = _height - 12;
      final samples = <int>[
        for (var x = _width ~/ 2; x < _width - 4; x += 4)
          pixels[(row * _width + x) * 4],
      ];

      expect(
        samples.first,
        greaterThan(8),
        reason: 'the floor under the panel is unlit',
      );
      for (var i = 1; i < samples.length; i++) {
        expect(
          samples[i],
          lessThanOrEqualTo(samples[i - 1]),
          reason: 'brightness rose again at sample $i: $samples',
        );
      }
      expect(
        samples.first - samples.last,
        greaterThan(4),
        reason: 'the floor is lit evenly, so nothing is falling off: $samples',
      );
    });

    test('rolling the panel turns the highlight with it', () async {
      // The property the representative point is chosen for. A punctual stand-in
      // at the panel's centre would give an identical frame at any roll, because
      // a point has no orientation — so this is the test that fails the moment
      // the specular half stops being about the rectangle.
      final flat = await _draw(_room());
      final rolled = await _draw(_room(roll: math.pi / 2.0));

      var changed = 0;
      for (var i = 0; i < flat.length; i += 4) {
        if ((flat[i] - rolled[i]).abs() > 2) changed++;
      }
      expect(
        changed,
        greaterThan(64),
        reason: 'a quarter turn of the panel moved $changed pixels',
      );
    });
  });

  group('the fourth kind costs the other three nothing', () {
    test('the three older codes did not move', () {
      // The shader classifies by `<` against these, so appending was the one
      // change that costs nothing: a scene with no rectangle takes the path it
      // always took, which is what keeps forty-four recorded frames still.
      expect(ShaderLightType.directional, 0.0);
      expect(ShaderLightType.point, 1.0);
      expect(ShaderLightType.spot, 2.0);
      expect(ShaderLightType.area, 3.0);
    });

    test('a spot light still packs cosines where a rectangle packs edges', () {
      // The two share `directions` and `cones`, so this is the regression that
      // matters: a spot whose cone array started holding a half-height vector
      // would light a cone of the wrong width, and nothing about the packing
      // would look wrong.
      final scene = Scene();
      final spot = LightNode(
        type: LightType.spot,
        outerConeAngle: math.pi / 6.0,
        name: 'spot',
      );
      scene.add(spot);
      final buffer = LightBuffer()..gather(scene.lights);

      expect(buffer.cones[0], closeTo(math.cos(0.0), 1e-6));
      expect(buffer.cones[1], closeTo(math.cos(math.pi / 6.0), 1e-6));
      expect(buffer.cones[2], 0.0);
      expect(buffer.directions[3], 0.0, reason: 'range');
    });

    test('a rectangle packs its two edges and nothing else', () {
      final scene = Scene();
      scene.add(
        LightNode(type: LightType.area, name: 'window')
          ..width = 3.0
          ..height = 1.0,
      );
      final buffer = LightBuffer()..gather(scene.lights);

      // An unrotated panel has its width along +X and its height along +Y, and
      // the halves are what the shader needs: the corners are the centre plus
      // and minus each.
      expect(buffer.directions[0], closeTo(1.5, 1e-6));
      expect(buffer.directions[1], closeTo(0.0, 1e-6));
      expect(buffer.cones[0], closeTo(0.0, 1e-6));
      // Negated, so that `cross(width, height)` is the node's own −Z and a
      // window aimed with `lookAt` emits forward like every other light. See
      // the packing comment; a rectangle is symmetric, so nothing in the
      // picture can tell which way its height runs.
      expect(buffer.cones[1], closeTo(-0.5, 1e-6));
      expect(buffer.positions[3], ShaderLightType.area);
    });
  });
}
