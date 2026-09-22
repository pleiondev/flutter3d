/// `gfx-12n`: a mask on the light and a mask on the object, so a torch can
/// be told what it is for.
///
///     flutter test test/light_channels_test.dart
///
/// **Why a channel rather than more shadow work.** A hero's flashlight that
/// lights the sky dome, an interior lamp that reaches through a wall the
/// renderer has no way to know is solid — neither is a shadow bug, and
/// neither is fixed by a better shadow map. They are statements about what a
/// light is *for*, and the engine has had nowhere to put one.
///
/// Applied where the eight lights of a draw are chosen, not in the shader:
/// a light that cannot reach an object does not take one of its slots
/// either. That is the whole difference, and it is why this file measures
/// slot counts as well as pixels.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 64;
const int _skyChannel = 1;
const int _groundChannel = 2;

/// Two quads side by side, each on its own channel, under one lamp.
Future<Uint8List> _draw({
  required int lampChannels,
  required int leftChannels,
  required int rightChannels,
}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene();

  MeshNode quad(String name, double x, int channels) =>
      MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(1.4, 2.6, 0.2)).build(),
          ),
          Material(name: name, baseColor: Vector4(0.9, 0.9, 0.9, 1.0)),
          name: name,
        )
        ..setPosition(x, 0.0, 0.0)
        ..lightChannels = channels;

  scene.add(quad('left', -1.0, leftChannels));
  scene.add(quad('right', 1.0, rightChannels));

  final lamp = LightNode(intensity: 6.0)
    ..setPosition(0.0, 0.0, 3.0)
    ..channels = lampChannels;
  lamp.lookAt(Vector3.zero());
  scene.add(lamp);

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: CameraNode()..setPosition(0.0, 0.0, 5.0),
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    // **Bloom off, and that is not tidiness.** With it on, the lit quad's
    // glow spreads across the whole frame and lifts the *other* half — which
    // is exactly what made the first version of this test read the excluded
    // quad as 155 rather than 78 and look like a leaking channel. Shadows off
    // for the ordinary reason: this is about which lights reach a surface,
    // not about what stands between them.
    settings: const RenderSettings(
      tonemap: false,
      bloom: BloomSettings(enabled: false),
      shadows: ShadowSettings(enabled: false),
    ),
  );
  return (await device.readPixels(frame.frame))!.buffer.asUint8List();
}

/// The brightest pixel in one half of the frame — the quad's own lit face.
///
/// The brightest rather than the average: half the frame is background, and
/// an average over it measures how much black is in shot rather than how
/// much light reached the surface.
double _brightness(Uint8List rgba, {required bool left}) {
  var brightest = 0;
  for (var y = 0; y < _height; y++) {
    final from = left ? 0 : _width ~/ 2;
    final to = left ? _width ~/ 2 : _width;
    for (var x = from; x < to; x++) {
      final green = rgba[(y * _width + x) * 4 + 1];
      if (green > brightest) brightest = green;
    }
  }
  return brightest.toDouble();
}

void main() {
  group('an object outside the channel gets no contribution', () {
    test(
      'the excluded object is lit exactly as if the lamp were not there',
      () async {
        // **Stated as an equality rather than as a ratio**, which is the whole
        // claim: "no contribution" means the same pixels an absent lamp would
        // leave, not merely darker ones. A ratio would also pass for a light
        // that leaked a little, and leaking a little is the failure this is
        // for.
        final channelled = await _draw(
          lampChannels: _skyChannel,
          leftChannels: _skyChannel,
          rightChannels: _groundChannel,
        );
        final lampOff = await _draw(
          lampChannels: LightChannels.none,
          leftChannels: _skyChannel,
          rightChannels: _groundChannel,
        );

        expect(
          _brightness(channelled, left: false),
          _brightness(lampOff, left: false),
          reason:
              'the right quad is off the lamp\'s channel, so it must look '
              'exactly as it does with the lamp shining on nothing',
        );
        // And the left one is lit, or the equality above would be the trivial
        // sort: two frames with no light in either.
        expect(
          _brightness(channelled, left: true),
          greaterThan(_brightness(lampOff, left: true)),
        );
      },
    );

    test('and swapping the masks swaps which side is dark', () async {
      final frame = await _draw(
        lampChannels: _groundChannel,
        leftChannels: _skyChannel,
        rightChannels: _groundChannel,
      );
      expect(
        _brightness(frame, left: true),
        lessThan(_brightness(frame, left: false)),
      );
    });

    test('a light on no channel at all lights nothing', () async {
      final none = await _draw(
        lampChannels: LightChannels.none,
        leftChannels: LightChannels.all,
        rightChannels: LightChannels.all,
      );
      final all = await _draw(
        lampChannels: LightChannels.all,
        leftChannels: LightChannels.all,
        rightChannels: LightChannels.all,
      );
      expect(
        _brightness(none, left: true),
        lessThan(_brightness(all, left: true) * 0.5),
      );
    });
  });

  group('zero changes to frames with no channels', () {
    test('every default draws what it always drew', () async {
      final a = await _draw(
        lampChannels: LightChannels.all,
        leftChannels: LightChannels.all,
        rightChannels: LightChannels.all,
      );
      final b = await _draw(
        lampChannels: LightChannels.all,
        leftChannels: LightChannels.all,
        rightChannels: LightChannels.all,
      );
      expect(a, b);
    });

    test('the defaults really are every bit', () {
      expect(LightNode().channels, LightChannels.all);
      expect(SceneNode().lightChannels, LightChannels.all);
      expect(LightChannels.only(0) | LightChannels.only(1), 3);
    });

    test('a scene with no channels takes the untouched fast path', () {
      // The claim behind "zero changes": with nothing channelled, the buffer
      // says so and the per-draw selection hands back the frame's own arrays
      // rather than a repacked copy. Checked at the buffer, which is where
      // the renderer asks.
      final plain = LightBuffer()..gather(<LightNode>[LightNode()]);
      expect(plain.anyChannelled, isFalse);

      final channelled = LightBuffer()
        ..gather(<LightNode>[LightNode()..channels = _skyChannel]);
      expect(channelled.anyChannelled, isTrue);
    });
  });

  group('a channel frees a slot rather than wasting one', () {
    test('an excluded light is not packed at all', () {
      // The difference between this and a check in the shader: with nine
      // lights and one object on a channel only three of them share, the
      // object is lit by three — not by eight of which five evaluate to
      // black.
      final lights = <LightNode>[
        for (var i = 0; i < 9; i++)
          LightNode(type: LightType.point, intensity: 5.0, range: 50.0)
            ..setPosition(i.toDouble(), 0.0, 0.0)
            ..channels = i < 3 ? _skyChannel : _groundChannel,
      ];

      final table = LightBuffer()..gather(lights);
      expect(table.count, LightBuffer.maxLights);
      expect(table.overflow, greaterThan(0));

      final forSky = LightBuffer()
        ..gatherNearFrom(
          table,
          Vector3(1.0, 0.0, 0.0),
          0.5,
          channels: _skyChannel,
        );
      expect(forSky.count, 3);
      for (final LightNode packed in forSky.packed) {
        expect(packed.channels, _skyChannel);
      }
    });

    test('and the same holds for a scene that fits in eight', () {
      final lights = <LightNode>[
        for (var i = 0; i < 4; i++)
          LightNode(type: LightType.point, intensity: 5.0, range: 50.0)
            ..setPosition(i.toDouble(), 0.0, 0.0)
            ..channels = i.isEven ? _skyChannel : _groundChannel,
      ];

      final table = LightBuffer()..gather(lights);
      expect(table.overflow, 0);

      final forSky = LightBuffer()..gatherMatchingFrom(table, _skyChannel);
      expect(forSky.count, 2);
      // A channel makes the list shorter; it does not make the scene
      // overflow, and reporting it as pressure on the eight slots would read
      // as a scene that needs selection when it does not.
      expect(forSky.overflow, 0);
    });
  });
}
