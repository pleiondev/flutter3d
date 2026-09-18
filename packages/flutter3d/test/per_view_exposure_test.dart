/// `gfx-22n`: each view exposing its own part of the frame.
///
///     flutter test test/per_view_exposure_test.dart
///
/// **One exposure for the frame is right for one pair of eyes and wrong for
/// two players.** A stereo pair wants a single number — two eyes that disagree
/// about brightness while the head turns is worse than either eye being a stop
/// off, which is why `RenderSettings.forStereo` leaves the meter alone. Split
/// screen wants the opposite: two players in two rooms metered together means
/// whichever room is darker is the one nobody can see.
///
/// So this is a setting, it is off, and the tests that matter most are the
/// ones saying that off is exactly where the engine was — including with the
/// setting *on* and a single view, where the view is the frame and the
/// rectangle is the whole histogram.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A luminance readback: [side] squared texels, dark on the left half and
/// bright on the right.
ByteData _splitLuminance({
  required int side,
  required int dark,
  required int bright,
}) {
  final bytes = ByteData(side * side * 4);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final value = x < side ~/ 2 ? dark : bright;
      bytes.setUint8((y * side + x) * 4, value);
    }
  }
  return bytes;
}

void main() {
  group('the meter reads a rectangle', () {
    test('a view of the whole frame meters what the frame meters', () {
      // The single-view case, which is the one that has to be unchanged: the
      // rectangle covers everything, so the histogram is the histogram.
      final bytes = _splitLuminance(side: 64, dark: 40, bright: 200);
      final whole = ExposureMeter.meanStops(bytes);
      final asView = ExposureMeter.meanStops(
        bytes,
        within: (x: 0.0, y: 0.0, width: 1.0, height: 1.0),
      );

      expect(asView, whole);
    });

    test('the dark half meters darker than the bright half', () {
      // **The claim of the row, in the meter alone.** Two halves of one
      // readback, two answers, and the dark one has to be the lower.
      final bytes = _splitLuminance(side: 64, dark: 40, bright: 200);
      final left = ExposureMeter.meanStops(
        bytes,
        within: (x: 0.0, y: 0.0, width: 0.5, height: 1.0),
      );
      final right = ExposureMeter.meanStops(
        bytes,
        within: (x: 0.5, y: 0.0, width: 0.5, height: 1.0),
      );

      expect(left, lessThan(right));
      expect(left, ExposureMeter.stopsOf(40));
      expect(right, ExposureMeter.stopsOf(200));
    });

    test('and the whole frame lands between them', () {
      final bytes = _splitLuminance(side: 64, dark: 40, bright: 200);
      final whole = ExposureMeter.meanStops(bytes);

      expect(whole, greaterThanOrEqualTo(ExposureMeter.stopsOf(40)));
      expect(whole, lessThanOrEqualTo(ExposureMeter.stopsOf(200)));
    });

    test('a view thinner than a texel meters that texel, not nothing', () {
      // Rounded outwards and floored at one texel each way: a sliver view is
      // a real layout, and a meter that answered "no texels" would hand back
      // the floor and expose the sliver at a thousandth of a unit of light.
      final bytes = _splitLuminance(side: 64, dark: 40, bright: 200);
      final sliver = ExposureMeter.meanStops(
        bytes,
        within: (x: 0.0, y: 0.0, width: 0.001, height: 0.001),
      );

      expect(sliver, ExposureMeter.stopsOf(40));
    });

    test('a readback that is not square is metered whole', () {
      // Nothing here can say which texel is where in a picture whose shape it
      // does not know, so the honest answer is the whole histogram rather
      // than a rectangle of a guess.
      final bytes = ByteData(6 * 4);
      for (var i = 0; i < 6; i++) {
        bytes.setUint8(i * 4, 100);
      }

      expect(
        ExposureMeter.meanStops(
          bytes,
          within: (x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ),
        ExposureMeter.stopsOf(100),
      );
    });
  });

  group('a frame with the setting off is the frame it always was', () {
    Future<List<int>> frame(RenderSettings settings) async {
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
            Material(name: 'ball', baseColor: Vector4(0.8, 0.4, 0.2, 1.0)),
          ),
        )
        ..add(
          LightNode(intensity: 5.0)
            ..setPosition(2.0, 3.0, 4.0)
            ..lookAt(Vector3.zero()),
        )
        ..add(CameraNode()..setPosition(0.0, 0.0, 3.0));

      final result = renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
        settings: settings,
      );
      final bytes = await device.readPixels(result.frame);
      return <int>[
        for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
      ];
    }

    test('off by default', () {
      expect(const AutoExposureSettings().perView, isFalse);
    });

    test('switching it on with one view changes no byte', () async {
      // **The strongest form of "this costs nothing where it is not wanted".**
      // One view is the whole frame, so its rectangle is the whole histogram
      // and its exposure is the frame's. The composite takes its single-draw
      // path, and forty-four goldens stay where they are.
      final off = await frame(
        const RenderSettings(autoExposure: AutoExposureSettings(enabled: true)),
      );
      final on = await frame(
        const RenderSettings(
          autoExposure: AutoExposureSettings(enabled: true, perView: true),
        ),
      );

      expect(on, off);
    });

    test('and with the meter off entirely', () async {
      final plain = await frame(const RenderSettings());
      final asked = await frame(
        const RenderSettings(autoExposure: AutoExposureSettings(perView: true)),
      );

      expect(asked, plain);
    });
  });

  group('two views', () {
    Future<({List<int> pixels, FrameResult result})> split({
      required bool perView,
    }) async {
      final device = CpuDevice(
        width: _size,
        height: _size,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      final renderer = Renderer.create(device: device);
      // One bright half and one dark one: a ball lit hard on the left, and a
      // camera pointed away from it on the right.
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(device, SphereShape(radius: 0.6).build()),
            Material(name: 'ball', baseColor: Vector4(0.9, 0.9, 0.9, 1.0)),
          ),
        )
        ..add(
          LightNode(intensity: 30.0)
            ..setPosition(0.0, 0.0, 3.0)
            ..lookAt(Vector3.zero()),
        )
        ..add(CameraNode()..setPosition(0.0, 0.0, 3.0))
        ..add(CameraNode()..setPosition(0.0, 0.0, 30.0));

      final cameras = scene.cameras.toList();
      final result = renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[
          RenderView(
            camera: cameras[0],
            viewportFraction: const ViewportRect(0.0, 0.0, 0.5, 1.0),
          ),
          RenderView(
            camera: cameras[1],
            priority: 1,
            viewportFraction: const ViewportRect(0.5, 0.0, 0.5, 1.0),
          ),
        ],
        settings: RenderSettings(
          autoExposure: AutoExposureSettings(
            enabled: true,
            perView: perView,
            // At once rather than over seconds: a frame that has to be the
            // same every time it is drawn cannot wait for an adaptation.
            speedUp: double.infinity,
            speedDown: double.infinity,
          ),
        ),
      );
      final bytes = await device.readPixels(result.frame);
      return (
        pixels: <int>[
          for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
        ],
        result: result,
      );
    }

    test(
      'draw without error and report one frame exposure either way',
      () async {
        // `FrameResult.exposure` stays the frame's, because it is one number and
        // a frame with two views has two — a caller wanting those asks the
        // renderer, and a caller wanting "how bright was this frame" gets the
        // answer it always got.
        final one = await split(perView: false);
        final many = await split(perView: true);

        expect(one.result.exposure, isPositive);
        expect(many.result.exposure, isPositive);
        expect(many.pixels.length, one.pixels.length);
      },
    );

    test(
      'the composite draws once per view when each exposes itself',
      () async {
        // The pass count is the observable difference: one full-frame draw
        // becomes one per view, which is what lets the exposure in the uniform
        // differ between them.
        final one = await split(perView: false);
        final many = await split(perView: true);

        int compositeDraws(FrameResult r) =>
            r.passes.firstWhere((p) => p.name == 'composite').drawCalls;

        expect(
          compositeDraws(many.result),
          greaterThan(compositeDraws(one.result)),
        );
        expect(compositeDraws(one.result), 1);
        expect(compositeDraws(many.result), 2);
      },
    );
  });
}
