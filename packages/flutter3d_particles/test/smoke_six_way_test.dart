/// `smoke-six-way` — `N6`: a puff of the engine's own baked smoke, drawn by
/// the software backend through a real renderer and lit from two sides.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// One bake for every test: the sheet depends on nothing they change.
final SixWaySheet _sheet = bakeSixWay(
  density: smokePuff(),
  frames: 1,
  columns: 1,
  cell: 32,
);

/// Three puffs in a row at the origin, seen from four metres, under [lights];
/// the composited frame, which is sRGB.
Float32List _render(
  List<LightNode> lights, {
  bool clustered = false,
  Vector3? ambient,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle upload(Uint8List bytes) => device.createTextureFromPixels(
    width: _sheet.width,
    height: _sheet.height,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(bytes),
  )!;

  final particles = ParticleSystem(capacity: 8);
  for (final x in <double>[-0.4, 0.0, 0.4]) {
    particles.burst(
      ParticleEffect(
        count: 1,
        emitter: const SphereEmitter(speed: Range.exact(0.0)),
        lifetime: const Range.exact(5.0),
        size: const Range.exact(1.6),
        color: Vector4(1.0, 1.0, 1.0, 1.0),
      ),
      Vector3(x, 0.0, x * 0.5),
    );
  }

  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 4.0)
    ..lookAt(Vector3.zero());
  // Not the light a scene with none is given: these tests count lights.
  final scene = Scene()
    ..defaultLightWhenUnlit = false
    ..add(camera);
  lights.forEach(scene.add);

  final renderer = Renderer.create(device: device)
    ..addContributor(
      ParticleContributor(
        particles,
        sixWay: SixWayMaterial(
          positive: upload(_sheet.positive),
          negative: upload(_sheet.negative),
          ambient: ambient,
        ),
      ),
    );
  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      clusteredLights: clustered,
    ),
  );
  return device.readHdrPixels(result.frame);
}

LightNode _point(Vector3 at, Vector3 colour, {double intensity = 12.0}) =>
    LightNode(type: LightType.point, intensity: intensity)
      ..color.setFrom(colour)
      ..setPosition(at.x, at.y, at.z);

/// Red and blue summed over a band of columns, [from] inclusive to [to].
({double red, double blue}) _band(Float32List frame, int from, int to) {
  var red = 0.0;
  var blue = 0.0;
  for (var y = 0; y < _size; y++) {
    for (var x = from; x < to; x++) {
      red += frame[(y * _size + x) * 4];
      blue += frame[(y * _size + x) * 4 + 2];
    }
  }
  return (red: red, blue: blue);
}

void main() {
  test('smoke-six-way: each side of the puff takes the light on that side', () {
    final frame = _render(<LightNode>[
      _point(Vector3(-3.0, 0.0, 0.0), Vector3(1.0, 0.2, 0.1)),
      _point(Vector3(3.0, 0.0, 0.0), Vector3(0.1, 0.2, 1.0)),
    ]);
    final left = _band(frame, 0, _size ~/ 3);
    final right = _band(frame, _size * 2 ~/ 3, _size);

    // Something was drawn, and lit.
    expect(left.red, greaterThan(1.0));
    expect(right.blue, greaterThan(1.0));
    // Mutation: read the left picture for a light on the right. Each side
    // turns the other's colour.
    expect(left.red, greaterThan(left.blue * 2.0));
    expect(right.blue, greaterThan(right.red * 2.0));
  });

  test('smoke with no light and no ambient is black, and covers', () {
    final frame = _render(const <LightNode>[]);
    var coverage = 0.0;
    var light = 0.0;
    for (var i = 0; i < frame.length; i += 4) {
      light += frame[i] + frame[i + 1] + frame[i + 2];
      coverage += frame[i + 3];
    }
    expect(light, 0.0);
    // The clear alpha is one either way, so a covered pixel stays at one;
    // what matters is that nothing lit it.
    expect(coverage, greaterThan(0.0));
  });

  test('ambient reaches every side at once', () {
    final frame = _render(const <LightNode>[], ambient: Vector3.all(1.0));
    final left = _band(frame, 0, _size ~/ 2);
    final right = _band(frame, _size ~/ 2, _size);
    expect(left.red, greaterThan(1.0));
    expect(right.red, greaterThan(1.0));
  });

  group('past the eight slots', () {
    // Identical white lights in one place, so twelve are exactly one and a
    // half times eight, and any light the tail drops or counts twice shows.
    List<LightNode> lamps(int count) => <LightNode>[
      for (var i = 0; i < count; i++)
        _point(Vector3(0.0, 1.0, 3.0), Vector3.all(1.0), intensity: 0.3),
    ];

    // The composite writes sRGB, so light is summed after undoing that; the
    // lamps are dim enough that nothing reaches one and is clipped.
    double sum(Float32List frame) {
      var total = 0.0;
      for (var i = 0; i < frame.length; i += 4) {
        final c = frame[i];
        expect(c, lessThan(1.0));
        total += c < 0.04045
            ? c / 12.92
            : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
      }
      return total;
    }

    test('the list lights a puff as it lights a surface', () {
      final eight = sum(_render(lamps(8)));
      final twelve = sum(_render(lamps(12)));
      expect(eight, greaterThan(1.0));
      // Mutation: bind a tail count of nought. Twelve reads as eight.
      expect(twelve / eight, closeTo(1.5, 2e-3));
    });

    test('and so do the cells, with the slots not counted twice', () {
      final list = _render(lamps(12));
      final cells = _render(lamps(12), clustered: true);
      var worst = 0.0;
      for (var i = 0; i < list.length; i++) {
        final d = (list[i] - cells[i]).abs();
        if (d > worst) worst = d;
      }
      // Mutation: drop `InSlots` from the contributor's reader. The slot
      // lights count twice.
      expect(worst, lessThan(1e-4));
    });
  });
}
