/// `renderSheet`: a contact sheet of four named views in one picture —
/// `mcp-07n`'s own row. "An agent more often needs the whole silhouette
/// than one view," and four small pictures read in one tool call cost less
/// than four round trips through [renderProject] would.
///
/// **No labels yet — a real, named gap, not a silent one.** This row's own
/// one-liner asks for "four views in one picture with labels," but nothing
/// in this workspace draws text into a raster with no `dart:ui` behind it:
/// every label an agent reads today comes from a widget tree, and a bitmap
/// font is its own small project, not a corner of this one. The acceptance
/// text itself only checks "a 2×2 sheet; each quarter is the same frame
/// `render` gives for its own view," which this delivers exactly — literally
/// the same [renderProject], called once per quadrant. Labelling the sheet
/// is real future work, not folded in here under the row's own harder
/// wording.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show GraphicsDevice;
import 'package:flutter3d_core/formats.dart'
    show Rgba8Image, decodeImagePure, encodeCompressedPng;

import 'project.dart';
import 'render_project.dart';

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
Future<Uint8List> renderSheet({
  required ModelProject project,
  int width = 512,
  int height = 512,
  RenderShading shading = RenderShading.material,
  Set<int> selection = const <int>{},
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
  }
  return encodeCompressedPng(sheetWidth, sheetHeight, pixels);
}
