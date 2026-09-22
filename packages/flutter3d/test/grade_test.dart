/// `gfx-27n`: lift, gamma and gain, and a white balance that is not the
/// temperature knob beside it.
///
///     flutter test test/grade_test.dart
///
/// **What these three are for, and why `contrast` was not enough.** Contrast
/// and saturation move the whole picture at once. Lift, gamma and gain each
/// move one end of it: lift adds, so the shadows rise and white stays; gain
/// multiplies, so the highlights move and black stays; gamma is the exponent
/// between them, so the midtones move and both ends stay. That is the
/// property each test below holds — the range it moves *and* the range it
/// leaves — because a grade that moved everything would be contrast wearing
/// three names.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A ramp from black to white, composited through [look].
///
/// Straight through the composite with the tone curve off, so what comes back
/// is the grade and nothing else — a curve would be a second opinion about
/// every value the grade moved.
Future<List<int>> _ramp(LookSettings look, {int width = 256}) async {
  final device = CpuDevice(
    width: width,
    height: 1,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final pixels = Float32List(width * 4);
  for (var x = 0; x < width; x++) {
    final value = x / (width - 1);
    pixels[x * 4] = value;
    pixels[x * 4 + 1] = value;
    pixels[x * 4 + 2] = value;
    pixels[x * 4 + 3] = 1.0;
  }
  final hdr = device.createTextureFromPixels(
    width: width,
    height: 1,
    format: TextureFormat.r32g32b32a32Float,
    pixels: pixels.buffer.asByteData(),
  )!;

  final frame = renderer.renderPost(
    hdr: hdr,
    settings: RenderSettings(
      tonemap: false,
      exposure: 1.0,
      bloom: const BloomSettings(enabled: false),
      look: look,
    ),
  );
  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var x = 0; x < width; x++) bytes!.getUint8(x * 4)];
}

void main() {
  test('every default is an exact identity', () async {
    // The promise forty-four goldens rest on. Neutral for these three is
    // (0,0,0) added, (1,1,1) as an exponent and (1,1,1) multiplied, and the
    // composite has to take all three without moving a byte.
    final plain = await _ramp(const LookSettings());
    final spelled = await _ramp(
      LookSettings(
        lift: Vector3.zero(),
        gamma: Vector3(1.0, 1.0, 1.0),
        gain: Vector3(1.0, 1.0, 1.0),
      ),
    );
    expect(spelled, plain);
  });

  group('each range moves its own end', () {
    test('lift raises black and leaves white', () async {
      final plain = await _ramp(const LookSettings());
      final lifted = await _ramp(LookSettings(lift: Vector3(0.1, 0.1, 0.1)));

      expect(
        lifted.first,
        greaterThan(plain.first + 20),
        reason: 'lift is what moves the shadows',
      );
      expect(
        lifted.last,
        plain.last,
        reason:
            'and white is where lift is supposed to leave it — it adds, '
            'and the encode clamps, so the top of the ramp cannot move',
      );
    });

    test('gain moves white and leaves black', () async {
      final plain = await _ramp(const LookSettings());
      final gained = await _ramp(LookSettings(gain: Vector3(0.5, 0.5, 0.5)));

      expect(
        gained.first,
        plain.first,
        reason: 'gain multiplies, so black by anything is still black',
      );
      expect(
        gained.last,
        lessThan(plain.last - 20),
        reason: 'and the highlights are what it is for',
      );
    });

    test('gamma moves the midtones and leaves both ends', () async {
      final plain = await _ramp(const LookSettings());
      final curved = await _ramp(LookSettings(gamma: Vector3(0.5, 0.5, 0.5)));

      expect(curved.first, plain.first, reason: 'zero to any power is zero');
      expect(curved.last, plain.last, reason: 'and one to any power is one');
      final middle = plain.length ~/ 2;
      expect(
        (curved[middle] - plain[middle]).abs(),
        greaterThan(20),
        reason: 'the middle is the whole of what an exponent moves',
      );
    });
  });

  test('a grade is per channel, which is why it is a colour', () async {
    // One number per stage could not say "warm highlights over cool shadows",
    // and that is the reason these are vectors rather than scalars.
    final warm = await _ramp(LookSettings(gain: Vector3(1.0, 0.8, 0.6)));
    final plain = await _ramp(const LookSettings());
    expect(warm.last, plain.last, reason: 'red was left at one');
  });

  group('white balance is the correction, temperature is the look', () {
    test('both are present, and neither is the other', () async {
      // `temperature` is documented as a gain on red against blue; this is
      // the pair a camera offers. They are separate settings on purpose, and
      // a test that only had one of them would not notice if the other
      // stopped being applied.
      const neutral = LookSettings();
      expect(neutral.temperature, 0.0);
      expect(neutral.whiteBalance, 0.0);
      expect(neutral.tint, 0.0);

      final plain = await _ramp(neutral);
      final balanced = await _ramp(const LookSettings(whiteBalance: 0.5));
      final warmed = await _ramp(const LookSettings(temperature: 0.5));

      expect(balanced, isNot(plain));
      expect(warmed, isNot(plain));
      expect(
        balanced,
        isNot(warmed),
        reason:
            'if these drew the same frame, one of them is not being '
            'applied and the settings are lying about what they do',
      );
    });

    test('a tint changes the hue without raising the level', () async {
      // It takes its green out of red and blue rather than adding light,
      // which is what keeps a tint from doubling as an exposure knob.
      final plain = await _ramp(const LookSettings());
      final tinted = await _ramp(const LookSettings(tint: 0.4));

      final middle = plain.length ~/ 2;
      expect(
        tinted[middle],
        lessThan(plain[middle]),
        reason: 'red is what a green tint takes from',
      );
    });
  });
}
