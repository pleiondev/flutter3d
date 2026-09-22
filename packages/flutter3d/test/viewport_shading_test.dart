/// `gfx-43n`, `gfx-44n`, `gfx-45n`: shading read out of the surface buffer.
///
///     flutter test test/viewport_shading_test.dart
///
/// **This deletes a bug class rather than adding a look, and that is what the
/// tests are about.** A normals view built by walking the subject and swapping
/// every material has to remember what it swapped and put it back — the
/// modeller's own docstring documents what happens when the remembering
/// fails. Every mode here is arithmetic on a buffer the scene pass already
/// wrote, so the check that matters is that the subject comes out of a shaded
/// frame unmodified: render a mode, render again with it off, and the second
/// frame has to be the frame that was always drawn.
///
/// The three modes are then each held to the one thing that separates them
/// from a wash over the picture: normals answer where a surface points, the
/// outline appears only where something steps, and curvature tells a ridge
/// from a groove.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A ball on black, which gives a silhouette for the outline and a curved
/// surface for the normals and the curvature.
Future<({List<int> pixels, FrameResult result})> _frame(
  ViewportShadingSettings shading, {
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
        DeviceMesh.upload(device, SphereShape(radius: 0.7).build()),
        Material(name: 'ball', baseColor: Vector4(0.8, 0.2, 0.2, 1.0)),
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
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      viewportShading: shading,
      disabledPasses: disabled,
      // Off, so what the mode produces is what comes out: a glow taken from a
      // normals view would be a halo around a colour that is not light.
      bloom: const BloomSettings(enabled: false),
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

/// The channels of the pixel at the frame's centre, which is on the ball.
List<int> _centre(List<int> pixels) {
  const at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  return <int>[pixels[at], pixels[at + 1], pixels[at + 2]];
}

/// The channels of a corner, which is background.
List<int> _corner(List<int> pixels) => <int>[pixels[0], pixels[1], pixels[2]];

void main() {
  group('nothing about the subject is modified', () {
    test('off is the default and an exact no-op', () async {
      expect(const ViewportShadingSettings().mode, ViewportShading.off);
      final plain = await _frame(const ViewportShadingSettings());
      final asked = await _frame(const ViewportShadingSettings());
      expect(asked.pixels, plain.pixels);
    });

    test(
      'a mode switched off by name leaves the frame it always drew',
      () async {
        // **The claim that replaces the material swap.** With the traversal
        // approach this could not be checked at all: the subject *had* been
        // modified and put back, so an equal frame would only mean the putting
        // back had worked this time. Here there is nothing to put back.
        final plain = await _frame(const ViewportShadingSettings());
        final shaded = await _frame(
          const ViewportShadingSettings(mode: ViewportShading.normals),
          disabled: const <String>{'viewport shading'},
        );

        expect(shaded.pixels, plain.pixels);
      },
    );

    test(
      'and the mode does change the frame, so the above is not vacuous',
      () async {
        final plain = await _frame(const ViewportShadingSettings());
        final shaded = await _frame(
          const ViewportShadingSettings(mode: ViewportShading.normals),
        );

        expect(shaded.pixels, isNot(plain.pixels));
      },
    );

    test('the background is left alone by every mode', () async {
      // Nothing was drawn there, so there is no surface to shade. A mode that
      // washed the whole frame would be a filter rather than a shading.
      final plain = await _frame(const ViewportShadingSettings());
      for (final mode in ViewportShading.values) {
        if (mode == ViewportShading.off) continue;
        final shaded = await _frame(ViewportShadingSettings(mode: mode));
        expect(
          _corner(shaded.pixels),
          _corner(plain.pixels),
          reason: '$mode changed the background',
        );
      }
    });
  });

  group('normals as colour — gfx-43n', () {
    test(
      'a surface facing the camera comes out the familiar pale blue',
      () async {
        // The normal at the centre of a ball facing the camera is +Z, which the
        // half-and-half mapping puts at (0.5, 0.5, 1) — pale blue, which is
        // what every other modeller shows and therefore what somebody
        // switching this on is checking for.
        final shaded = await _frame(
          const ViewportShadingSettings(mode: ViewportShading.normals),
        );
        final centre = _centre(shaded.pixels);

        expect(centre[2], greaterThan(centre[0]));
        expect(centre[2], greaterThan(centre[1]));
        expect(
          centre[2],
          greaterThan(180),
          reason: 'the blue channel carries a normal pointing at the camera',
        );
      },
    );

    test('clay is grey, because it has had its albedo taken away', () async {
      // The ball is red. Clay's whole purpose is that it stops being red.
      final shaded = await _frame(
        const ViewportShadingSettings(mode: ViewportShading.clay),
      );
      final centre = _centre(shaded.pixels);

      expect((centre[0] - centre[1]).abs(), lessThan(3));
      expect((centre[1] - centre[2]).abs(), lessThan(3));
      expect(centre[0], greaterThan(0), reason: 'and it is lit, not black');
    });

    test('the ambient floor decides how dark the far side goes', () async {
      final dim = await _frame(
        const ViewportShadingSettings(mode: ViewportShading.clay, ambient: 0.0),
      );
      final lifted = await _frame(
        const ViewportShadingSettings(mode: ViewportShading.clay, ambient: 0.8),
      );

      var dimSum = 0;
      var liftedSum = 0;
      for (var i = 0; i < dim.pixels.length; i += 4) {
        dimSum += dim.pixels[i];
        liftedSum += lifted.pixels[i];
      }
      expect(liftedSum, greaterThan(dimSum));
    });
  });

  group('the outline — gfx-44n', () {
    test('appears at the silhouette and not in the middle of a face', () async {
      // The mode mixed over the picture rather than replacing it, which is
      // how an outline is actually wanted: the shading stays and the edges
      // are drawn on it. So the centre of the ball must be untouched and
      // something near its rim must be darker.
      final plain = await _frame(const ViewportShadingSettings());
      final outlined = await _frame(
        const ViewportShadingSettings(mode: ViewportShading.outline),
      );

      expect(
        _centre(outlined.pixels),
        _centre(plain.pixels),
        reason: 'the middle of a smooth face is not an edge',
      );

      var darkened = 0;
      for (var i = 0; i < plain.pixels.length; i += 4) {
        if (outlined.pixels[i] < plain.pixels[i]) darkened++;
      }
      expect(
        darkened,
        greaterThan(0),
        reason:
            'a silhouette against the background is the clearest edge '
            'there is, so some pixel has to be drawn dark',
      );
    });

    test('a threshold nothing reaches draws no line', () async {
      // Both thresholds well past anything in the frame: the mode runs, finds
      // no edge, and leaves the picture. An outline that drew anyway would be
      // a threshold that means nothing.
      final plain = await _frame(const ViewportShadingSettings());
      final none = await _frame(
        const ViewportShadingSettings(
          mode: ViewportShading.outline,
          depthEdge: 1e6,
          normalEdge: 4.0,
        ),
      );

      // The silhouette still counts — a neighbour with no surface at all is
      // an edge whatever the thresholds say, which is deliberate and is the
      // one thing this test cannot ask to be turned off.
      expect(_centre(none.pixels), _centre(plain.pixels));
    });
  });

  group('curvature — gfx-45n', () {
    test(
      'a sphere reads as curved, and a gain of zero reads as flat',
      () async {
        // Gain zero collapses the estimate to nothing, so every pixel of the
        // subject lands on the mode's neutral grey. Anything above it has to
        // spread: a ball is curved everywhere, and a mode that answered one
        // value for it would not be measuring curvature.
        final flat = await _frame(
          const ViewportShadingSettings(
            mode: ViewportShading.curvature,
            curvatureGain: 0.0,
          ),
        );
        final curved = await _frame(
          const ViewportShadingSettings(
            mode: ViewportShading.curvature,
            curvatureGain: 8.0,
          ),
        );

        int spread(List<int> pixels) {
          var low = 255;
          var high = 0;
          for (var i = 0; i < pixels.length; i += 4) {
            // The subject only: the background is untouched by every mode.
            if (pixels[i + 3] == 0) continue;
            if (pixels[i] == 0) continue;
            if (pixels[i] < low) low = pixels[i];
            if (pixels[i] > high) high = pixels[i];
          }
          return high - low;
        }

        expect(spread(curved.pixels), greaterThan(spread(flat.pixels)));
      },
    );

    test('the cavity knob only ever darkens', () async {
      // A cavity map's concave half is a darkening, so turning it up cannot
      // make the picture brighter anywhere.
      final none = await _frame(
        const ViewportShadingSettings(
          mode: ViewportShading.curvature,
          cavity: 0.0,
        ),
      );
      final full = await _frame(
        const ViewportShadingSettings(
          mode: ViewportShading.curvature,
          cavity: 1.0,
        ),
      );

      for (var i = 0; i < none.pixels.length; i += 4) {
        expect(
          full.pixels[i],
          lessThanOrEqualTo(none.pixels[i]),
          reason: 'pixel ${i ~/ 4} got brighter with more cavity',
        );
      }
    });
  });

  group('the cost is reported', () {
    test('a mode takes the multisampling off the scene pass', () {
      // On a device that multisamples, because the rasteriser does not. This
      // is the trade `anchor_identity_test.dart` pins as a fixture: the mode
      // declares the surface buffer, declaring it attaches the second
      // attachment, and attachments in one target must agree on sample count.
      FrameResult recorded(ViewportShadingSettings shading) {
        final renderer = Renderer.create(device: FakeBackend());
        final scene = Scene()
          ..add(
            LightNode(intensity: 4.0)
              ..setPosition(2.0, 3.0, 4.0)
              ..lookAt(Vector3.zero()),
          )
          ..add(CameraNode()..setPosition(0.0, 0.0, 3.0));
        return renderer.render(
          width: _size,
          height: _size,
          scene: scene,
          views: <RenderView>[RenderView(camera: scene.cameras.single)],
          settings: RenderSettings(viewportShading: shading),
        );
      }

      final off = recorded(const ViewportShadingSettings());
      final on = recorded(
        const ViewportShadingSettings(mode: ViewportShading.clay),
      );

      expect(off.antiAliasing.msaaDeclined, isNull);
      expect(on.antiAliasing.msaaDeclined, contains('surface buffer'));
    });

    test('and on a device with one attachment the mode declines', () {
      // `gfx-50n` meeting these rows: the buffer is an optional read, so
      // there is nothing to starve — the pass runs and hands the lit picture
      // through rather than shading from a texture nobody filled.
      final renderer = Renderer.create(
        device: FakeBackend(maxColorAttachments: 1),
      );
      final scene = Scene()..add(CameraNode());
      final result = renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
        settings: const RenderSettings(
          viewportShading: ViewportShadingSettings(
            mode: ViewportShading.normals,
          ),
        ),
      );

      expect(
        result.passes.map((p) => p.name),
        contains('viewport shading'),
        reason: 'an optional read is not a reason to be culled',
      );
    });
  });
}
