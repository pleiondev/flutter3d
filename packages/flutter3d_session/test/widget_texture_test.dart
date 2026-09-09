import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter3d_session/flutter3d_session.dart';

/// The colour at a pixel, as four bytes.
Future<List<int>> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = (y * image.width + x) * 4;
  return <int>[
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
    data.getUint8(offset + 3),
  ];
}

void main() {
  // The rasteriser is the application's, so there has to be one. This is the
  // binding the docstring on [WidgetTexture.draw] says a caller needs.
  TestWidgetsFlutterBinding.ensureInitialized();

  // `rasterise` is tested rather than `draw`: the upload half needs a device,
  // and what is worth pinning here is that a widget nobody put in a tree comes
  // out as the picture it describes, at the size that was asked for.
  test('a widget nobody mounted is drawn at the size asked for', () async {
    final image = await WidgetTexture.rasterise(
      const ColoredBox(color: Color(0xFF3366CC)),
      width: 64,
      height: 32,
    );
    addTearDown(image.dispose);

    expect(image.width, 64);
    expect(image.height, 32);
    expect(await _pixel(image, 32, 16), <int>[0x33, 0x66, 0xCC, 0xFF]);
  });

  test('layout reaches the corners of the texture', () async {
    // A row of two halves. If the widget were laid out against anything other
    // than the requested size — the window, say — the seam would not land in
    // the middle and one of these two reads would be the other colour.
    final image = await WidgetTexture.rasterise(
      const Row(
        // Stretch, because the default centres and hands the children loose
        // vertical constraints — under which a childless `ColoredBox` is zero
        // high and paints nothing. True of any Flutter layout; worth saying
        // here because the first version of this test did not.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: ColoredBox(color: Color(0xFFFF0000))),
          Expanded(child: ColoredBox(color: Color(0xFF00FF00))),
        ],
      ),
      width: 40,
      height: 10,
    );
    addTearDown(image.dispose);

    expect(await _pixel(image, 2, 5), <int>[0xFF, 0x00, 0x00, 0xFF]);
    expect(await _pixel(image, 37, 5), <int>[0x00, 0xFF, 0x00, 0xFF]);
  });

  test('a pixel ratio buys pixels, not a bigger layout', () async {
    // Same widget, same logical layout, twice the pixels: the seam stays in
    // the middle and the image is twice as wide.
    final image = await WidgetTexture.rasterise(
      const Row(
        // Stretch, because the default centres and hands the children loose
        // vertical constraints — under which a childless `ColoredBox` is zero
        // high and paints nothing. True of any Flutter layout; worth saying
        // here because the first version of this test did not.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: ColoredBox(color: Color(0xFFFF0000))),
          Expanded(child: ColoredBox(color: Color(0xFF00FF00))),
        ],
      ),
      width: 80,
      height: 20,
      pixelRatio: 2.0,
    );
    addTearDown(image.dispose);

    expect(image.width, 80);
    expect(await _pixel(image, 4, 10), <int>[0xFF, 0x00, 0x00, 0xFF]);
    expect(await _pixel(image, 75, 10), <int>[0x00, 0xFF, 0x00, 0xFF]);
  });

  test('text renders rather than throwing for want of a Directionality', () async {
    // The adapter supplies one. A caller writing a sign should not have to.
    final image = await WidgetTexture.rasterise(
      const Center(
        child: Text(
          'PIT',
          style: TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
        ),
      ),
      width: 48,
      height: 24,
    );
    addTearDown(image.dispose);

    expect(image.width, 48);
  });
}
