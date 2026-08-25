import 'package:vector_math/vector_math.dart';

import 'key_ease.dart';
import 'particle.dart';

/// One point on a [ParticleGradient].
final class GradientKey {
  const GradientKey(this.at, this.color, {this.ease = KeyEase.linear});

  /// Where in the particle's life this key sits, in `[0, 1]`.
  final double at;

  /// Linear RGB with alpha as brightness, matching [Particle.color].
  final Vector4 color;

  final KeyEase ease;
}

/// A colour over a particle's life.
///
/// Separate from [ParticleCurve] rather than a curve of four channels: four
/// independent curves let the channels' keys fall at different points, which is
/// how a colour ramp ends up with a grey frame in the middle that nobody put
/// there. A gradient's keys are keys of the whole colour.
final class ParticleGradient {
  ParticleGradient(this.keys)
      : assert(keys.isNotEmpty, 'a gradient with no keys has no colour'),
        assert(_isSorted(keys), 'gradient keys must be ordered by `at`');

  ParticleGradient.constant(Vector4 color)
      : this(<GradientKey>[GradientKey(0.0, color)]);

  ParticleGradient.linear(Vector4 from, Vector4 to)
      : this(<GradientKey>[GradientKey(0.0, from), GradientKey(1.0, to)]);

  final List<GradientKey> keys;

  static bool _isSorted(List<GradientKey> keys) {
    for (var i = 1; i < keys.length; i++) {
      if (keys[i].at < keys[i - 1].at) return false;
    }
    return true;
  }

  /// Writes the colour at [t] into [out], allocating nothing.
  ///
  /// Into an output parameter because this is called per particle per step and
  /// returning a fresh [Vector4] would allocate once per particle per frame —
  /// at a few thousand particles that is the difference between a garbage
  /// collection nobody notices and one that shows up as a hitch.
  void sampleInto(Vector4 out, double t) {
    final last = keys.length - 1;
    if (t <= keys[0].at) {
      out.setFrom(keys[0].color);
      return;
    }
    if (t >= keys[last].at) {
      out.setFrom(keys[last].color);
      return;
    }

    for (var i = 0; i < last; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      if (t > b.at) continue;
      final span = b.at - a.at;
      if (span <= 0.0) {
        out.setFrom(b.color);
        return;
      }
      final k = easeShape((t - a.at) / span, a.ease);
      out.setValues(
        a.color.x + (b.color.x - a.color.x) * k,
        a.color.y + (b.color.y - a.color.y) * k,
        a.color.z + (b.color.z - a.color.z) * k,
        a.color.w + (b.color.w - a.color.w) * k,
      );
      return;
    }
    out.setFrom(keys[last].color);
  }
}
