/// `renderSheet`: a contact sheet of four named views in one picture —
/// `mcp-07n`'s own row. "An agent more often needs the whole silhouette
/// than one view," and four small pictures read in one tool call cost less
/// than four round trips through [renderProject] would.
///
/// **The labels arrived late, and this is what they cost.** This row's own
/// one-liner asked for "four views in one picture with labels" and shipped
/// without them, because nothing in this workspace drew text into a raster
/// with no `dart:ui` behind it — every label an agent read came from a
/// widget tree. `tiny_font.dart` is that missing piece: a 5×7 bitmap font
/// and a nested loop over RGBA bytes. Each quadrant now carries the name of
/// the view it is, in the corner, white over a one-pixel black shadow so it
/// reads on a light render and a dark one alike.
///
/// The acceptance text — "a 2×2 sheet; each quarter is the same frame
/// `render` gives for its own view" — is still checkable exactly, because
/// [renderSheet] takes `labels: false` and the test that makes that claim
/// passes it. A sheet is not pixel-identical to four renders *and* labelled;
/// saying so and giving the caller the switch is better than quietly
/// weakening the older claim.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show GraphicsDevice;
import 'package:flutter3d_core/formats.dart'
    show Rgba8Image, decodeImagePure, encodeCompressedPng;

import 'project.dart';
import 'render_project.dart';
import 'tiny_font.dart';

/// The four views a sheet renders, one per quadrant, left-to-right then
/// top-to-bottom: front and right make the top row, top and iso the bottom —
/// three orthographic views plus the one perspective view, the same
/// "silhouette from every side" a person reaches for on a real drafting
/// sheet.
const List<RenderProjectView> renderSheetViews = <RenderProjectView>[
  RenderProjectView.front,
  RenderProjectView.right,
  RenderProjectView.top,
  RenderProjectView.iso,
];

/// [project], as a 2×[renderSheetViews.length ~/ 2] grid of PNG bytes.
///
/// [width]/[height] are the whole sheet's own size; each quadrant renders at
/// half of each, rounded down — an odd [width] or [height] loses at most one
/// pixel off the sheet's own right or bottom edge rather than off any tile.
/// [RenderRefusal] surfaces from whichever quadrant [renderProject] refuses
/// first, at the half-size it was actually asked to draw.
///
/// [labels] writes each view's own name into its quadrant. Pass `false` for
/// a sheet whose quadrants are byte-for-byte what [renderProject] returns.
Future<Uint8List> renderSheet({
  required ModelProject project,
  int width = 512,
  int height = 512,
  RenderShading shading = RenderShading.material,
  Set<int> selection = const <int>{},
  int? weightsJoint,
  bool labels = true,
  required GraphicsDevice Function(int width, int height) deviceFactory,
}) async {
  final tileWidth = width ~/ 2;
  final tileHeight = height ~/ 2;

  final tiles = <Rgba8Image>[];
  for (final RenderProjectView view in renderSheetViews) {
    final png = await renderProject(
      RenderRequest(
        project: project,
        view: view,
        width: tileWidth,
        height: tileHeight,
        shading: shading,
        selection: selection,
        weightsJoint: weightsJoint,
      ),
      deviceFactory: deviceFactory,
    );
    tiles.add((await decodeImagePure(png))!);
  }

  final sheetWidth = tileWidth * 2;
  final sheetHeight = tileHeight * 2;
  final pixels = Uint8List(sheetWidth * sheetHeight * 4);
  for (var i = 0; i < tiles.length; i++) {
    final tile = tiles[i];
    final originX = (i % 2) * tileWidth;
    final originY = (i ~/ 2) * tileHeight;
    for (var y = 0; y < tile.height; y++) {
      final srcStart = y * tile.width * 4;
      final dstStart = ((originY + y) * sheetWidth + originX) * 4;
      pixels.setRange(
        dstStart,
        dstStart + tile.width * 4,
        tile.pixels,
        srcStart,
      );
    }

    if (!labels) continue;
    // One pixel of scale per sixty-four of tile, so a 128-pixel thumbnail
    // gets legible text rather than a smear, and a 1024-pixel sheet gets a
    // caption rather than a watermark. The inset matches the scale for the
    // same reason: a margin measured in pixels looks like a mistake at one
    // size or the other.
    final scale = (tileHeight ~/ 64).clamp(1, 4);
    final inset = 3 * scale;
    drawTinyTextWithShadow(
      pixels,
      width: sheetWidth,
      height: sheetHeight,
      x: originX + inset,
      y: originY + tileHeight - inset - tinyFontHeight * scale,
      text: renderSheetViews[i].name,
      scale: scale,
    );
  }
  return encodeCompressedPng(sheetWidth, sheetHeight, pixels);
}
