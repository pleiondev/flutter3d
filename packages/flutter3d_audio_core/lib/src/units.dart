/// # The units the audio model is written in
///
/// One table, so that a number handed from a game to the mixer, from the
/// mixer to a spatial renderer and from there to a backend means the same
/// thing at every hop. It is the engine's units contract applied to sound:
///
/// | Quantity           | Unit                               | Where            |
/// |--------------------|------------------------------------|------------------|
/// | distance, position | metres, Y up, right-handed         | emitters, curves |
/// | velocity           | metres per second                  | doppler          |
/// | time               | seconds                            | blends, ducking  |
/// | frequency          | hertz                              | filters          |
/// | angle              | radians                            | azimuth          |
/// | gain               | linear amplitude, 1 is unchanged   | voices, sliders  |
/// | level              | decibels, `20 · log10(gain)`       | snapshots, ducks |
///
/// **Gain and level are kept apart on purpose.** A volume slider and a
/// voice's gain are linear because that is what a backend multiplies by. A
/// snapshot or a ducking rule speaks in decibels because that is what a
/// mixing desk shows and what adds: two snapshots each taking 6 dB off a bus
/// take 12 dB off it, where two halvings multiplied would have to be
/// explained. The conversion happens once, in [decibelsToGain], at the
/// moment a level becomes a gain.
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart'
    show standardSpeedOfSound;

/// How fast sound travels in air at 20 °C, in metres per second. What a
/// doppler shift is computed against unless a renderer is told otherwise.
///
/// The world's number, read from `standardSpeedOfSound`, not one of audio's
/// own: a world whose air is not a room's hands the renderer its own speed,
/// from its air's temperature (`EqualPowerPanner.inWorld`,
/// `WorldProperties.speedOfSound`).
const double speedOfSoundInAir = standardSpeedOfSound;

/// The level, in decibels, at and below which a gain is taken as silence.
///
/// A floor rather than negative infinity so that a level can be blended: a
/// snapshot fading a bus to −96 dB passes through every level on the way,
/// where one fading to −∞ would be silent from its first frame.
const double silenceDecibels = -96.0;

/// The linear gain of [decibels]: `10 ^ (decibels / 20)`, and exactly zero
/// at or below [silenceDecibels]. Nought decibels is exactly one.
double decibelsToGain(double decibels) {
  if (decibels <= silenceDecibels) return 0.0;
  if (decibels == 0.0) return 1.0;
  return math.pow(10.0, decibels / 20.0).toDouble();
}
