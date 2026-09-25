/// A rectangle light lights one face of the world, the whole of what lies
/// above a surface's horizon, and a clear coat by its own integral — `L7`.
///
///     dart test test/area_light_sides_test.dart
///
/// Three corrections to `gfx-77n`'s panel, each checked here against what it
/// used to get wrong: light through the panel's back, a panel on the horizon
/// read as dark, and a coat whose reflection of the panel was brighter than a
/// mirror's.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

const int _size = 48;

/// The irradiance a rectangle of unit radiance delivers to the origin with
/// normal [n], by midpoint quadrature over [steps]² patches of it: each patch
/// is `cos(surface) · cos(panel) / r²` times its area, with both cosines
/// clamped, which is what a form factor is the closed form of.
double _integrate(
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
    final u = (i + 0.5) / steps * 2.0 - 1.0;
    for (var j = 0; j < steps; j++) {
      final v = (j + 0.5) / steps * 2.0 - 1.0;
      final point = centre + halfWidth * u + halfHeight * v;
      final distance2 = point.length2;
      final direction = point.normalized();
      final cosSurface = n.dot(direction);
      final cosPanel = -panelNormal.dot(direction);
      if (cosSurface <= 0.0 || cosPanel <= 0.0) continue;
      total += cosSurface * cosPanel / distance2 * patchArea;
    }
  }
  return total;
}

/// The corners `SampleLight` builds for a panel seen from the origin.
List<Vector3> _corners(Vector3 centre, Vector3 halfWidth, Vector3 halfHeight) =>
    <Vector3>[
      centre - halfWidth - halfHeight,
      centre + halfWidth - halfHeight,
      centre + halfWidth + halfHeight,
      centre - halfWidth + halfHeight,
    ];

/// The HDR frame of [objects] under [light], seen by [camera], with no
/// ambient and no environment: whatever is lit, the panel lit.
Float32List _render(
  List<MeshNode> Function(CpuDevice device) objects, {
  required LightNode? light,
  required CameraNode camera,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene()..ambientIntensity = 0.0;
  for (final node in objects(device)) {
    scene.add(node);
  }
  if (light != null) scene.add(light);
  scene.add(camera);
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(
      tonemap: false,
      bloom: BloomSettings(enabled: false),
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// A square panel [size] metres across, [height] metres up, facing down.
LightNode _panel({
  double height = 2.0,
  double size = 1.0,
  double intensity = 12.0,
}) => LightNode(type: LightType.area, intensity: intensity)
  ..width = size
  ..height = size
  ..setPosition(0.0, height, 0.0)
  ..setRotationYawPitchRoll(0.0, -math.pi / 2.0, 0.0);

/// The brightest green value in [hdr].
double _peakGreen(Float32List hdr) {
  var peak = 0.0;
  for (var i = 1; i < hdr.length; i += 4) {
    peak = math.max(peak, hdr[i]);
  }
  return peak;
}

void main() {
  group('the diffuse is clipped to the horizon', () {
    // The receiver at the origin looking up; each panel faces it and crosses
    // its horizon somewhere. Unclipped, the part below cancels the part above.
    final up = Vector3(0.0, 1.0, 0.0);
    final cases =
        <
          ({
            String name,
            Vector3 n,
            Vector3 centre,
            Vector3 halfWidth,
            Vector3 halfHeight,
          })
        >[
          (
            // Symmetric about the horizon: the old sum read exactly nought.
            name: 'a wall panel centred on the horizon',
            n: up,
            centre: Vector3(0.0, 0.0, -1.5),
            halfWidth: Vector3(0.8, 0.0, 0.0),
            halfHeight: Vector3(0.0, 0.5, 0.0),
          ),
          (
            name: 'a wall panel mostly above it',
            n: up,
            centre: Vector3(0.3, 0.3, -1.2),
            halfWidth: Vector3(0.8, 0.0, 0.0),
            halfHeight: Vector3(0.0, 0.5, 0.0),
          ),
          (
            // The side of a sphere under a ceiling panel, near its terminator.
            name: 'a ceiling panel seen from a steep slope',
            n: Vector3(math.sin(1.3), math.cos(1.3), 0.0),
            centre: Vector3(-0.4, 1.0, 0.0),
            halfWidth: Vector3(1.0, 0.0, 0.0),
            halfHeight: Vector3(0.0, 0.0, 0.6),
          ),
        ];

    for (final it in cases) {
      test(it.name, () {
        final reference = _integrate(
          it.n,
          centre: it.centre,
          halfWidth: it.halfWidth,
          halfHeight: it.halfHeight,
        );
        final closed = rectangleFormFactor(
          _corners(it.centre, it.halfWidth, it.halfHeight),
          it.n,
        );
        // Mutation: count every edge whole, as the unclipped sum did, and the
        // first case reads nought against 0.046, the second eight per cent
        // short and the third less than half.
        expect(reference, greaterThan(0.02));
        expect(
          (closed - reference).abs() / reference,
          lessThan(0.005),
          reason: 'closed form $closed against reference $reference',
        );
      });
    }

    test('a panel wholly below the horizon delivers nothing', () {
      final closed = rectangleFormFactor(
        _corners(
          Vector3(0.0, -1.0, 0.0),
          Vector3(0.5, 0.0, 0.0),
          Vector3(0.0, 0.0, -0.5),
        ),
        up,
      );
      expect(closed, 0.0);
    });
  });

  group('the panel lights one face of the world', () {
    // A slab above a ceiling panel, its top facing away from the panel's
    // dark back: the floor of the room upstairs.
    List<MeshNode> upstairs(CpuDevice device) => <MeshNode>[
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(6.0, 0.4, 6.0)).build(),
        ),
        Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0), roughness: 0.4),
      )..setPosition(0.0, 3.2, 0.0),
    ];
    CameraNode camera() => CameraNode()
      ..setPosition(0.0, 6.0, -4.0)
      ..lookAt(Vector3(0.0, 3.4, 0.0));

    // What the slab reads with no light on it, and what the background
    // behind it reads, is under a tenth; lit, its top is near one.
    test('the room above a downward panel stays dark', () {
      final below = _render(upstairs, light: _panel(), camera: camera());
      // Mutation: drop both the side test in `sampleLight` and the horizon
      // clip, and the slab's top peaks near two, as lit as if the panel
      // faced it. Either alone keeps it dark: the clipped sum is never
      // positive from behind, and with the clip dropped the side test still
      // turns the point away.
      expect(_peakGreen(below), lessThan(0.15));
    });

    test('and lights it from above', () {
      final above = _render(
        upstairs,
        light: _panel(height: 5.0),
        camera: camera(),
      );
      expect(_peakGreen(above), greaterThan(0.5));
    });
  });

  group('a clear coat reflects a panel by its own integral', () {
    // A floor under a large panel, seen where it mirrors the panel.
    List<MeshNode> Function(CpuDevice) floor(Material material) =>
        (device) => <MeshNode>[
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3(12.0, 0.4, 12.0)).build(),
            ),
            material,
          )..setPosition(0.0, -0.2, 0.0),
        ];
    CameraNode camera() => CameraNode()
      ..setPosition(0.0, 1.0, -2.5)
      ..lookAt(Vector3(0.0, 0.0, 0.0));
    LightNode light() => _panel(size: 3.0);

    test('the coat adds a few per cent of what a mirror reflects', () {
      // The calibration: a white metal as smooth as the model allows
      // reflects the panel whole.
      final mirror = _peakGreen(
        _render(
          floor(
            Material(
              lighting: LightingModel.pbrLayered,
              baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
              metallic: 1.0,
              roughness: 0.0,
            ),
          ),
          light: light(),
          camera: camera(),
        ),
      );
      Material paint({required double coat}) => Material(
        lighting: LightingModel.pbrLayered,
        baseColor: Vector4(0.02, 0.02, 0.02, 1.0),
        roughness: 0.8,
        extensions: MaterialExtensions(
          clearcoat: coat,
          clearcoatRoughness: 0.0,
        ),
      );
      final bare = _render(
        floor(paint(coat: 0.0)),
        light: light(),
        camera: camera(),
      );
      final coated = _render(
        floor(paint(coat: 1.0)),
        light: light(),
        camera: camera(),
      );
      final added = Iterable<int>.generate(
        bare.length ~/ 4,
        (pixel) => pixel * 4 + 1,
      ).fold(0.0, (peak, i) => math.max(peak, coated[i] - bare[i]));
      // A dielectric of index 1.5 reflects four per cent head-on and more
      // towards grazing, which this view is not far from: about a sixth of
      // the mirror here. Mutation: evaluate the coat at the representative
      // point again, and it adds nineteen times the mirror's whole
      // reflection.
      expect(mirror, greaterThan(0.1));
      expect(added, greaterThan(0.02 * mirror));
      expect(added, lessThan(0.25 * mirror));
    });
  });
}
