import 'dart:math' as math;
import 'dart:typed_data';

/// Where a voice's low-pass sits: open, or dulled by a wall, and never where
/// the filter stops being a filter.
///
/// **SoLoud runs a voice's filters at that voice's own rate**: the file's
/// sample rate times the speed it is played at. A cutoff above half of that
/// is past the Nyquist frequency, where the biquad's coefficients leave the
/// unit circle and the filter feeds itself until it overflows. The backend
/// opened every source at 16 kHz, which a 44.1 kHz file at full speed can
/// carry and a 22.05 kHz one cannot: River Sortie's whole bank is 22.05 kHz,
/// its engine came out as a scream and every one-shot as nothing.

/// The most open cutoff for a voice of [sampleRate] played at [rate]: the
/// wanted [open] frequency, or nine tenths of the voice's Nyquist frequency
/// if that is lower.
double openCutoff({
  required int sampleRate,
  required double rate,

  /// The wanted cutoff, in hertz.
  double open = 16000.0,
}) => math.min(open, 0.45 * sampleRate * math.max(rate, 0.01));

/// The cutoff for a voice muffled by [muffle], from 0 (clear) to 1 (heard
/// through a wall), between [open] and [wall].
///
/// Geometric, because hearing is: half way in the ratio is half way in pitch,
/// where half way in hertz would be nearly open. A voice whose open cutoff is
/// already below [wall] is left at it.
double muffledCutoff(double open, double muffle, {double wall = 600.0}) {
  if (open <= wall) return open;
  return open * math.pow(wall / open, muffle.clamp(0.0, 1.0));
}

/// The sample rate a RIFF WAVE file says it has, or null for anything that
/// is not one: the one header a sound bank's usual format carries in a fixed
/// place.
int? wavSampleRate(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final data = ByteData.sublistView(bytes);
  bool tag(int at, String name) =>
      String.fromCharCodes(bytes.sublist(at, at + 4)) == name;
  if (!tag(0, 'RIFF') || !tag(8, 'WAVE')) return null;
  // Chunks follow one another; `fmt ` is usually first but need not be.
  var at = 12;
  while (at + 8 <= bytes.length) {
    final size = data.getUint32(at + 4, Endian.little);
    if (tag(at, 'fmt ')) {
      if (at + 16 > bytes.length) return null;
      final rate = data.getUint32(at + 12, Endian.little);
      return rate > 0 ? rate : null;
    }
    at += 8 + size + (size & 1);
  }
  return null;
}
