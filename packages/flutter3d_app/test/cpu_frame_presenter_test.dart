/// `CpuFrame`: the software backend's own way onto the screen.
///
///     flutter test test/cpu_frame_presenter_test.dart
///
/// **The bug this file exists for.** The presenter decoded a texture only
/// when the *instance* changed, and the backend hands back the same
/// `CpuTexture` every frame — a render target is a buffer it reuses, not a
/// megabyte it allocates sixty times a second. So the decode ran once and the
/// picture froze on the first frame ever drawn: the camera turned, the
/// document was replaced, and the widget went on showing startup. Nothing saw
/// it, because the two GPU backends present through their own path and every
/// pixel test in the repository reads the frame back from the device rather
/// than off the widget.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/src/cpu_frame_presenter.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart' show CpuTexture;
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show TextureFormat;
import 'package:flutter_test/flutter_test.dart';

/// Paints every pixel of [texture] one colour, the way a render into it does.
void _fill(CpuTexture texture, double r, double g, double b) {
  for (var at = 0; at < texture.pixels.length; at += 4) {
    texture.pixels[at] = r;
    texture.pixels[at + 1] = g;
    texture.pixels[at + 2] = b;
    texture.pixels[at + 3] = 1.0;
  }
}

/// The first pixel of whatever the widget is actually showing.
Future<List<int>> _shown(WidgetTester tester) async {
  final ui.Image image = tester.widget<RawImage>(find.byType(RawImage)).image!;
  final ByteData? bytes = await tester.runAsync<ByteData?>(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return bytes!.buffer.asUint8List().sublist(0, 4);
}

/// Pumps one frame's worth of the presenter and lets its decode land.
Future<void> _present(WidgetTester tester, CpuTexture texture) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CpuFrame(
        texture: texture,
        fit: BoxFit.fill,
        quality: FilterQuality.none,
      ),
    ),
  );
  // `decodeImageFromPixels` is real asynchronous work: it only completes
  // while the binding lets the real event loop run.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

void main() {
  testWidgets('a repainted texture reaches the screen, though the backend '
      'hands back the same one', (WidgetTester tester) async {
    final CpuTexture texture = CpuTexture(2, 2, TextureFormat.r8g8b8a8UNormInt);
    _fill(texture, 1.0, 0.0, 0.0);
    await _present(tester, texture);
    final List<int> first = await _shown(tester);
    expect(first.sublist(0, 3), <int>[255, 0, 0]);

    // The next frame: the renderer writes into the same buffer, which is
    // exactly what it does every frame.
    _fill(texture, 0.0, 1.0, 0.0);
    await _present(tester, texture);

    // Mutation: decode only when the texture instance changes — which is
    // what this did. The second frame is never decoded, the widget keeps
    // showing the first, and every picture the software backend draws is the
    // one it drew when it started.
    expect((await _shown(tester)).sublist(0, 3), <int>[0, 255, 0]);
  });
}
