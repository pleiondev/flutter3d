/// The one long sound, and the bus that had a slider and nothing behind it.
///
///     flutter test test/music_test.dart
///
/// **A setting that does nothing is worse than an absent one.** The mixer has
/// carried a `music` bus with a volume slider since sound was added, and
/// nothing ever played on it — so a player who moved that slider learned that
/// the settings screen lies.
///
/// What is checked here is the *file*, because that is what can go wrong
/// without anybody noticing: a regeneration that clips, or comes out three
/// seconds long, or stops joining itself at the loop point. The generator
/// prints those numbers too, and a number printed by the thing that produced it
/// is not evidence.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/sounds.dart';

/// A mono 16-bit WAV, as its header says it is and as its samples are.
final class _Wav {
  _Wav(String path) {
    final bytes = File(path).readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    // RIFF/WAVE, then chunks. Walked rather than assumed at a fixed offset:
    // every writer lays them out slightly differently.
    var at = 12;
    while (at + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(at, at + 4));
      final size = data.getUint32(at + 4, Endian.little);
      if (id == 'fmt ') {
        channels = data.getUint16(at + 10, Endian.little);
        rate = data.getUint32(at + 12, Endian.little);
        bits = data.getUint16(at + 22, Endian.little);
      } else if (id == 'data') {
        samples = Int16List.sublistView(
          Uint8List.sublistView(bytes, at + 8, at + 8 + size),
        );
      }
      at += 8 + size + (size.isOdd ? 1 : 0);
    }
  }

  late final int channels;
  late final int rate;
  late final int bits;
  late final Int16List samples;

  double get seconds => samples.length / rate;
  int get peak =>
      samples.fold(0, (int most, int s) => s.abs() > most ? s.abs() : most);
}

void main() {
  final music = _Wav('assets/sounds/music.wav');

  test('the music bus has something on it', () {
    // The def, because an asset path with a typo in it is silence that nothing
    // else in this file would catch.
    expect(Sounds.music.bus, AudioBus.music);
    expect(Sounds.music.loop, isTrue);
    expect(Sounds.music.maxInstances, 1,
        reason: 'a looping sound played twice is a flanger');
    expect(Sounds.music.attenuation, isA<NoAttenuation>(),
        reason: 'the track is not in the level, it is the level');
    expect(File(Sounds.music.asset).existsSync(), isTrue);
    expect(Sounds.all, contains(Sounds.music),
        reason: 'not in the bank, so never preloaded');
  });

  test('and it is a loop of a sensible length', () {
    expect(music.channels, 1);
    expect(music.rate, 44100);
    expect(music.bits, 16);
    // Eight bars at ninety. Long enough not to be a jingle, short enough that
    // the file is under two megabytes.
    expect(music.seconds, closeTo(21.33, 0.1));
  });

  test('it plays under the game rather than over it', () {
    // About eighteen decibels under full scale. The music slider should be for
    // turning it up.
    expect(music.peak, lessThan(6000),
        reason: 'mixed loud enough to bury the footsteps');
    expect(music.peak, greaterThan(1500), reason: 'inaudible');
  });

  test('and it joins itself, so the loop does not click', () {
    // **The claim the generator is built around**, checked on the shipped file
    // rather than taken from the generator's own print. Every oscillator's
    // frequency is rounded to a whole number of cycles inside the loop, so the
    // waveform is exactly periodic and the last sample meets the first with no
    // step in value or in slope. A step here is a broadband snap the ear finds
    // instantly and then cannot stop hearing.
    final first = music.samples.first;
    final last = music.samples.last;
    final step = (last - first).abs();

    expect(step, lessThan(music.peak ~/ 20),
        reason: 'the seam steps by $step against a peak of ${music.peak}');

    // And the slope, because a waveform can meet itself in value and still
    // corner: a V at the seam is as audible as a step.
    final slopeIn = music.samples[1] - first;
    final slopeOut = last - music.samples[music.samples.length - 2];
    expect((slopeIn - slopeOut).abs(), lessThan(music.peak ~/ 20));
  });
}
