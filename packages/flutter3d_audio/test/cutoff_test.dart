/// Where a voice's low-pass sits, and that it stays a filter there.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_audio/src/cutoff.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether SoLoud's biquad low-pass at [frequency] is stable when run at
/// [sampleRate]: its poles inside the unit circle. The coefficients are
/// `BiquadResonantFilterInstance::calcBQRParams`, with its default resonance.
bool _stable(double frequency, double sampleRate, {double resonance = 2.0}) {
  final omega = 2.0 * math.pi * frequency / sampleRate;
  final alpha = math.sin(omega) / (2.0 * resonance);
  final scalar = 1.0 / (1.0 + alpha);
  final b1 = -2.0 * math.cos(omega) * scalar;
  final b2 = (1.0 - alpha) * scalar;
  // A second-order recursion y = x - b1·y1 - b2·y2 is stable exactly when
  // |b2| < 1 and |b1| < 1 + b2.
  return b2.abs() < 1.0 && b1.abs() < 1.0 + b2;
}

/// A minimal RIFF WAVE header of [sampleRate], with a chunk before `fmt `.
Uint8List _wav(int sampleRate, {bool junkFirst = false}) {
  final b = BytesBuilder();
  void tag(String s) => b.add(s.codeUnits);
  void u32(int v) =>
      b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) =>
      b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  tag('RIFF');
  u32(0);
  tag('WAVE');
  if (junkFirst) {
    tag('JUNK');
    u32(3);
    b.add(<int>[0, 0, 0, 0]); // three bytes and the pad byte
  }
  tag('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  return b.toBytes();
}

void main() {
  test('the old open cutoff was past the Nyquist of a 22 kHz file', () {
    // What River Sortie's bank met: every voice at 22.05 kHz, the filter
    // opened at 16 kHz, and SoLoud running it at the voice's own rate.
    expect(_stable(16000.0, 22050.0), isFalse);
    expect(_stable(16000.0, 44100.0), isTrue);
  });

  test('the open cutoff is a filter at every speed a game plays at', () {
    for (final sampleRate in <int>[8000, 11025, 22050, 44100, 48000]) {
      for (final rate in <double>[0.25, 0.5, 0.75, 1.0, 1.5, 2.0]) {
        final cutoff = openCutoff(sampleRate: sampleRate, rate: rate);
        expect(
          _stable(cutoff, sampleRate * rate),
          isTrue,
          reason: '$sampleRate Hz at $rate: $cutoff Hz',
        );
      }
    }
    // A file with room above sixteen kilohertz keeps its highs.
    expect(openCutoff(sampleRate: 48000, rate: 1.0), 16000.0);
  });

  test('a muffle dulls from the open cutoff towards the wall', () {
    expect(muffledCutoff(16000.0, 0.0), 16000.0);
    expect(muffledCutoff(16000.0, 1.0), closeTo(600.0, 1e-9));
    expect(
      muffledCutoff(16000.0, 0.5),
      closeTo(math.sqrt(16000.0 * 600.0), 1e-6),
      reason: 'half way in pitch',
    );
    expect(muffledCutoff(400.0, 1.0), 400.0, reason: 'never opened past it');
  });

  test('a WAV says its sample rate, and anything else does not', () {
    expect(wavSampleRate(_wav(22050)), 22050);
    expect(wavSampleRate(_wav(48000, junkFirst: true)), 48000);
    expect(
      wavSampleRate(Uint8List.fromList('ID3 not a wave'.codeUnits)),
      isNull,
    );
    expect(wavSampleRate(Uint8List(4)), isNull);
  });
}
