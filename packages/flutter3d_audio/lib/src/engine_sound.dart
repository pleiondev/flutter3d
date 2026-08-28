import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'audio_scene.dart';
import 'sound.dart';

/// One recording in a set that covers a range of some value.
///
/// [centre] is what the recording *is*: a loop of an engine at three quarters
/// of its revs has a centre of `0.75`. That is what makes the speed correction
/// below meaningful rather than arbitrary — asked for a value the band is not
/// centred on, it is played at the ratio between the two, which is exactly what
/// running an engine faster sounds like.
final class LoopBand {
  const LoopBand({required this.sound, required this.centre, this.width = 0.35})
    : assert(centre > 0.0),
      assert(width > 0.0);

  final SoundDef sound;

  /// The value this band was recorded at.
  final double centre;

  /// How far either side of [centre] it still contributes.
  ///
  /// Overlap is the point: two bands whose widths do not reach each other leave
  /// a hole where neither is heard, and two that meet exactly leave a seam
  /// where one stops and the other starts. Both are audible as a click part way
  /// up the rev range.
  final double width;
}

/// Several loops, crossfaded by one number.
///
/// The number is usually engine revs, and that is what this exists for: a car's
/// note is one or more recordings of an engine, played faster as it revs and
/// mixed so that the change from one recording to the next is not audible. A
/// single loop stretched across the whole range works and sounds like a siren
/// at the ends, which is why the shape here takes a list rather than a sound.
///
/// Deliberately not a racing class. "Crossfade a set of loops by a parameter"
/// is what a helicopter, a conveyor, a saw and a spaceship all want, and none
/// of them are this repository's business either.
///
/// ## Loudness across the blend
///
/// The weights are normalised, so the total is the same wherever the value
/// sits. Without that, the middle of a crossfade — where two bands are each at
/// half — is quieter than either end, and an engine gets a dip in the middle of
/// its range that reads as the sound cutting out.
final class BlendedLoop {
  BlendedLoop({required this.scene, required List<LoopBand> bands, Vector3? at})
    : bands = List<LoopBand>.unmodifiable(bands),
      _position = at?.clone() ?? Vector3.zero() {
    assert(bands.isNotEmpty);
    for (final band in this.bands) {
      assert(
        band.sound.loop,
        'a band that is not a loop stops part way up the rev range',
      );
      _emitters.add(scene.play(band.sound, _position)..gain = 0.0);
    }
    _weights = List<double>.filled(this.bands.length, 0.0);
  }

  final AudioScene scene;
  final List<LoopBand> bands;

  final Vector3 _position;
  final List<SoundEmitter> _emitters = <SoundEmitter>[];
  late final List<double> _weights;

  /// Where the sound is coming from, for anything that moves.
  Vector3 get position => _position;

  /// Mixes the bands for [value], overall as loud as [volume].
  ///
  /// [at] moves the source, for a car. Left out, it stays where it was.
  void update(double value, {double volume = 1.0, Vector3? at}) {
    if (at != null) {
      _position.setFrom(at);
      for (final emitter in _emitters) {
        emitter.position.setFrom(at);
      }
    }

    var total = 0.0;
    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      final distance = (value - band.centre).abs() / band.width;
      // A raised cosine rather than a straight ramp: the derivative is zero at
      // both ends, so a band arrives and leaves without a corner, and a corner
      // in a gain curve is a click.
      final weight = distance >= 1.0
          ? 0.0
          : 0.5 * (1.0 + math.cos(math.pi * distance));
      _weights[i] = weight;
      total += weight;
    }

    if (total <= 1e-9) {
      // Outside every band. The nearest one carries it alone rather than the
      // engine falling silent, which is what a value beyond the last band —
      // an over-rev, a stall — would otherwise sound like.
      var nearest = 0;
      for (var i = 1; i < bands.length; i++) {
        if ((value - bands[i].centre).abs() <
            (value - bands[nearest].centre).abs()) {
          nearest = i;
        }
      }
      for (var i = 0; i < bands.length; i++) {
        _weights[i] = i == nearest ? 1.0 : 0.0;
      }
      total = 1.0;
    }

    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      _emitters[i]
        ..gain = _weights[i] / total * volume
        // The ratio between what is wanted and what the band holds. An engine
        // recorded at half revs, asked for three quarters, is that recording
        // run half again as fast — which is what the real thing does.
        ..rate = (value / band.centre).clamp(0.25, 4.0);
    }
  }

  /// What the last [update] decided band [index] is worth.
  ///
  /// Read-only, and read rather than the backend's voices: a band mixed down to
  /// nothing is dropped by the voice allocator and has no voice at all, so
  /// counting voices would report a set of two as a set of one wherever the
  /// crossfade is not in the middle.
  double gainOf(int index) => _emitters[index].gain;

  /// And how fast it is being played.
  double rateOf(int index) => _emitters[index].rate;

  /// Ends every band. The loops run until this is called.
  void stop() {
    for (final emitter in _emitters) {
      emitter.stop();
    }
  }
}
