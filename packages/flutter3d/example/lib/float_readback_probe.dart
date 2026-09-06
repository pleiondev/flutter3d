/// Whether a float render target can be read back into Dart, measured on a
/// live GPU.
///
/// **A measurement, not a feature.** `GraphicsDevice.readback` promises the
/// same bytes on three backends and so admits only eight-bit RGBA, and
/// `readback.dart` says why: a half-float target read through
/// `readPixels(RGBA, UNSIGNED_BYTE)` is an error on WebGL2 that hands back a
/// black picture, while flutter_gpu would convert and answer with the picture.
/// That reasoning settled what the contract admits. It never settled what the
/// hardware can do, and the two have been quietly treated as the same fact
/// ever since — which matters now, because a simulation that lives in a float
/// texture is only half a feature if the CPU cannot see the result.
///
/// Reading the engine's sources says the pipe may already fit. Impeller maps
/// `kR32G32B32A32Float` to `kRGBA_F32_SkColorType`, and `ImageByteFormat`
/// `rawExtendedRgba128` is encoded from that same colour type — both ends
/// agree on binary32 with no eight-bit crossing between them. But two hazards
/// sit in the middle and neither is visible from the source alone. The image
/// the encoder wraps is tagged `kPremul_SkAlphaType` while
/// `rawExtendedRgba128` is documented as *straight* alpha, so the copy is
/// entitled to divide the colour channels by the alpha channel — and a
/// simulation storing inverse mass in `w` is not storing an alpha, so that
/// division would be silent corruption rather than a wrong picture. The second
/// is range: nothing in the API says a clear value outside `[0, 1]` survives.
///
/// So this asks the GPU. It clears a float target to values chosen to make
/// both hazards visible — components above one, below zero, and an alpha of a
/// half and of zero — reads the target back through the extended format and
/// through the eight-bit one, and reports what came out. Where the numbers
/// disagree with what went in it names the arrangement that would explain
/// them, because "wrong" is not a finding and "divided by alpha" is.
///
/// Written against flutter_gpu directly rather than through the HAL, for the
/// reason `surface_probe.dart` gives: the question is what the API grants, and
/// going through the backend would put its own bookkeeping on both sides of
/// the answer. Nothing in the engine or the backend calls this.
/// `float_readback_probe_main.dart` runs it. The verdict belongs in the plan
/// this was cut from, and — if the answer is yes — in `readback.dart`, whose
/// refusal would then be a choice rather than a limit.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

/// What one clear was read back as, and what that reading implies.
final class FloatReadbackCase {
  /// Records a case. [extended] is null when the read handed back nothing.
  const FloatReadbackCase({
    required this.format,
    required this.wrote,
    required this.extended,
    required this.eightBit,
    required this.verdict,
  });

  /// The pixel format of the target that was cleared.
  final gpu.PixelFormat format;

  /// The clear value, which is what a correct read hands back.
  final vm.Vector4 wrote;

  /// The first pixel as `rawExtendedRgba128` read it, or null on a failed read.
  final List<double>? extended;

  /// The first pixel as `rawRgba` read it: four bytes, for contrast.
  final List<int>? eightBit;

  /// What the numbers say, in one line.
  final String verdict;

  /// Whether this case answers "the float value survived".
  bool get ok => verdict.startsWith('ok');
}

/// Everything the probe found, ready to print.
final class FloatReadbackReport {
  /// Builds a report over [cases].
  FloatReadbackReport(this.cases);

  /// Each clear that was measured, in the order measured.
  final List<FloatReadbackCase> cases;

  /// How many cases did not read back what was written.
  int get failures => cases.where((FloatReadbackCase c) => !c.ok).length;

  /// The report as lines, one case per block.
  List<String> get lines => <String>[
    'float readback probe',
    '',
    for (final FloatReadbackCase c in cases) ...<String>[
      '${_formatName(c.format)}  wrote ${_vec(c.wrote)}',
      '  rawExtendedRgba128 -> ${c.extended == null ? 'nothing' : _list(c.extended!)}',
      '  rawRgba            -> ${c.eightBit ?? 'nothing'}',
      '  ${c.verdict}',
      '',
    ],
    'failures: $failures of ${cases.length}',
  ];
}

String _formatName(gpu.PixelFormat f) =>
    f.toString().replaceFirst('PixelFormat.', '').padRight(22);

String _vec(vm.Vector4 v) => '[${v.x}, ${v.y}, ${v.z}, ${v.w}]';

String _list(List<double> v) =>
    '[${v.map((double d) => d.toStringAsPrecision(7)).join(', ')}]';

/// Runs the probe once it is on screen and hands the report to [onDone].
class FloatReadbackProbe extends StatefulWidget {
  /// Builds the probe.
  const FloatReadbackProbe({required this.onDone, super.key});

  /// Told once, with everything measured.
  final void Function(FloatReadbackReport report) onDone;

  @override
  State<FloatReadbackProbe> createState() => _FloatReadbackProbeState();
}

class _FloatReadbackProbeState extends State<FloatReadbackProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    // Both float formats the engine already declares, because the cheap one is
    // the one a simulation would reach for first and it has its own answer:
    // half cannot hold 1000.5 exactly, so a mismatch there is precision and
    // not a broken pipe, and the verdict has to be able to say which.
    const List<gpu.PixelFormat> formats = <gpu.PixelFormat>[
      gpu.PixelFormat.r32g32b32a32Float,
      gpu.PixelFormat.r16g16b16a16Float,
    ];

    // Chosen so that every hazard shows as a different number. Above one and
    // below zero catch a clamp; alpha of a half catches an unpremultiply, and
    // catches it loudly because the colour channels are not near it; alpha of
    // zero is where an unpremultiply cannot even pretend, and either zeroes
    // the pixel or hands back infinities.
    final List<vm.Vector4> clears = <vm.Vector4>[
      vm.Vector4(2.5, -1.25, 1000.5, 0.5),
      vm.Vector4(0.75, -0.5, 3.25, 0.0),
      vm.Vector4(0.25, 0.5, 0.75, 1.0),
    ];

    final cases = <FloatReadbackCase>[];
    for (final gpu.PixelFormat format in formats) {
      for (final vm.Vector4 clear in clears) {
        cases.add(await _measure(format, clear));
      }
    }
    widget.onDone(FloatReadbackReport(cases));
  }

  Future<FloatReadbackCase> _measure(
    gpu.PixelFormat format,
    vm.Vector4 clear,
  ) async {
    // Four by four rather than one by one: a single pixel would not show a row
    // stride getting in the way, and the read is cheap either way.
    final gpu.Texture texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      4,
      4,
      format: format,
    );

    final gpu.CommandBuffer buffer = gpu.gpuContext.createCommandBuffer();
    // A pass with no draws in it, which is how the conformance checks clear a
    // target too: the clear is the load action, and the draw would only add a
    // shader this has no reason to need.
    buffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: texture, clearValue: clear),
      ),
    );

    final submitted = Completer<bool>();
    buffer.submit(completionCallback: submitted.complete);
    if (!await submitted.future) {
      return FloatReadbackCase(
        format: format,
        wrote: clear,
        extended: null,
        eightBit: null,
        verdict: 'failed: the GPU refused the command buffer',
      );
    }

    final List<double>? extended = await _readExtended(texture);
    final List<int>? eightBit = await _readEightBit(texture);
    return FloatReadbackCase(
      format: format,
      wrote: clear,
      extended: extended,
      eightBit: eightBit,
      verdict: _verdictOf(format, clear, extended),
    );
  }

  Future<List<double>?> _readExtended(gpu.Texture texture) async {
    final ui.Image image = texture.asImage();
    try {
      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawExtendedRgba128,
      );
      if (bytes == null) return null;
      final Float32List floats = bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
      return floats.take(4).toList(growable: false);
    } catch (_) {
      // A throw is an answer too — it means the format is refused rather than
      // converted, which is the outcome `readback.dart` assumed all along.
      return null;
    } finally {
      image.dispose();
    }
  }

  Future<List<int>?> _readEightBit(gpu.Texture texture) async {
    final ui.Image image = texture.asImage();
    try {
      final ByteData? bytes = await image.toByteData();
      if (bytes == null) return null;
      return <int>[for (int i = 0; i < 4; i++) bytes.getUint8(i)];
    } catch (_) {
      return null;
    } finally {
      image.dispose();
    }
  }

  /// Names what the numbers show, rather than only whether they match.
  String _verdictOf(
    gpu.PixelFormat format,
    vm.Vector4 wrote,
    List<double>? read,
  ) {
    if (read == null) return 'failed: the extended read handed back nothing';

    // Half carries about three decimal digits, so 1000.5 comes back as 1000
    // through no fault of the pipe. The tolerance is relative for that reason.
    final double tolerance = format == gpu.PixelFormat.r16g16b16a16Float
        ? 1e-2
        : 1e-5;
    bool near(double a, double b) =>
        (a - b).abs() <= tolerance * (b.abs() < 1 ? 1 : b.abs());

    final List<double> expected = <double>[wrote.x, wrote.y, wrote.z, wrote.w];
    if (List<int>.generate(
      4,
      (int i) => i,
    ).every((int i) => near(read[i], expected[i]))) {
      return 'ok: the value survived';
    }

    // The two arrangements worth naming, because each has a different
    // consequence for a simulation and a different fix.
    final double a = wrote.w;
    if (a != 0) {
      final List<double> unpremultiplied = <double>[
        wrote.x / a,
        wrote.y / a,
        wrote.z / a,
        a,
      ];
      if (List<int>.generate(
        4,
        (int i) => i,
      ).every((int i) => near(read[i], unpremultiplied[i]))) {
        return 'divided by alpha: the read unpremultiplies, so a fourth '
            'channel holding anything but an alpha is corrupted';
      }
    }

    final List<double> clamped = <double>[
      wrote.x.clamp(0.0, 1.0),
      wrote.y.clamp(0.0, 1.0),
      wrote.z.clamp(0.0, 1.0),
      wrote.w.clamp(0.0, 1.0),
    ];
    if (List<int>.generate(
      4,
      (int i) => i,
    ).every((int i) => near(read[i], clamped[i]))) {
      return 'clamped to [0, 1]: range is lost, precision is not';
    }

    return 'disagrees, and not by clamping or by alpha';
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
