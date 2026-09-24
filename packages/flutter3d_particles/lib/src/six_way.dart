/// Six-way lit particles — `N6`: smoke that the scene's lights reach into.
///
/// A sprite is a picture of smoke lit from wherever the artist's light was, so
/// it stays lit from there whichever torch it drifts past. A six-way sheet is
/// six pictures of the same puff, each lit from one side — right, left, top,
/// bottom, back and front — and the stage mixes them by where each light
/// really is. That is enough for a puff to be bright on the side facing a lamp,
/// dark in its own shade, and to glow at its thin edges with a light behind it.
///
/// ## The layout
///
/// Two RGBA textures, sharing one flipbook grid:
///
///  * **positive** — r: lit from the right, g: from the top, b: from the back,
///    a: coverage;
///  * **negative** — r: lit from the left, g: from the bottom, b: from the
///    front, a: emission.
///
/// "Back" is the far side of the puff from the viewer. The responses are
/// unpremultiplied, light as it reads at full coverage. This is the layout
/// the six-way exports of EmberGen and Houdini write, and the one
/// `flutter3d_build`'s baker writes; [importSixWay] repacks any other.
///
/// **A cell's rows run bottom to top.** The quad's texture coordinate rises
/// along the camera's up (`ParticleSystem.writeQuads`), and a texture's first
/// row is at nought, so the first row of a cell is the bottom of the puff. An
/// image as it was authored has its top row first; [importSixWay] turns each
/// cell over, and leaves the order of the cells, which is the flipbook's, as it
/// was.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

/// A six-way sheet on the device, and what it emits and receives from every
/// side.
///
/// **Not for spinning particles.** The stage reads right and up as the
/// camera's, because a quad's own turn is not in its vertices; a particle
/// with a `rotation` turns its picture and not the light, so a puff spun a
/// quarter turn is lit as though its right were its top.
final class SixWayMaterial {
  SixWayMaterial({
    required this.positive,
    required this.negative,
    Vector3? emission,
    Vector3? ambient,
  }) : emission = emission ?? Vector3.zero(),
       ambient = ambient ?? Vector3.zero();

  /// Right, top, back and coverage. See the library's own comment.
  final TextureHandle positive;

  /// Left, bottom, front and emission.
  final TextureHandle negative;

  /// What the emission channel's full value emits: linear, and not tinted by
  /// the particle's colour, since the heat in a plume of smoke is not grey
  /// because the smoke is.
  final Vector3 emission;

  /// Light arriving evenly from every side, read through the mean of the six
  /// pictures.
  ///
  /// Here rather than taken from the scene. A contributor is handed the lights
  /// but not the scene they came from, and smoke that is the wrong shade in a
  /// dark room is easier to fix with a number beside the effect than by
  /// changing the room.
  final Vector3 ambient;
}

/// One channel of one source image: [image] counts from nought, [channel] is
/// r, g, b, a as nought to three.
typedef SixWayChannel = ({int image, int channel});

/// Where each of the eight six-way quantities is in a set of source images.
final class SixWayLayout {
  const SixWayLayout({
    required this.right,
    required this.left,
    required this.top,
    required this.bottom,
    required this.back,
    required this.front,
    required this.coverage,
    this.emission,
  });

  /// The engine's own layout — see the library's comment — as two images.
  /// Importing through it only turns the cells over.
  static const SixWayLayout positiveNegative = SixWayLayout(
    right: (image: 0, channel: 0),
    top: (image: 0, channel: 1),
    back: (image: 0, channel: 2),
    coverage: (image: 0, channel: 3),
    left: (image: 1, channel: 0),
    bottom: (image: 1, channel: 1),
    front: (image: 1, channel: 2),
    emission: (image: 1, channel: 3),
  );

  final SixWayChannel right;
  final SixWayChannel left;
  final SixWayChannel top;
  final SixWayChannel bottom;
  final SixWayChannel back;
  final SixWayChannel front;
  final SixWayChannel coverage;

  /// Null for a sheet with no emission, which then emits nothing.
  final SixWayChannel? emission;
}

/// Repacks RGBA8 [images] of [width] by [height], laid out by [layout], into
/// the engine's positive and negative textures.
///
/// [columns] and [rows] are the flipbook's grid, which is what turning each
/// cell over needs: a flip of the whole image would reverse the order of the
/// frames with them. [flipCells] false leaves the rows as they are, for a
/// sheet already written bottom to top — the baker's.
({Uint8List positive, Uint8List negative}) importSixWay({
  required List<Uint8List> images,
  required int width,
  required int height,
  int columns = 1,
  int rows = 1,
  SixWayLayout layout = SixWayLayout.positiveNegative,
  bool flipCells = true,
}) {
  final texels = width * height;
  for (final image in images) {
    if (image.length < texels * 4) {
      throw ArgumentError(
        'a ${width}x$height RGBA8 image is ${texels * 4} bytes, '
        'and one here is ${image.length}',
      );
    }
  }
  if (height % rows != 0) {
    throw ArgumentError('$height rows of pixels do not split into $rows cells');
  }
  final cellHeight = height ~/ rows;
  final positive = Uint8List(texels * 4);
  final negative = Uint8List(texels * 4);

  int read(SixWayChannel? from, int texel) =>
      from == null ? 0 : images[from.image][texel * 4 + from.channel];

  for (var y = 0; y < height; y++) {
    // The source row this destination row takes, turned over within its
    // cell and nowhere else.
    final within = y % cellHeight;
    final source = flipCells ? y - within + (cellHeight - 1 - within) : y;
    for (var x = 0; x < width; x++) {
      final from = source * width + x;
      final to = (y * width + x) * 4;
      positive
        ..[to] = read(layout.right, from)
        ..[to + 1] = read(layout.top, from)
        ..[to + 2] = read(layout.back, from)
        ..[to + 3] = read(layout.coverage, from);
      negative
        ..[to] = read(layout.left, from)
        ..[to + 1] = read(layout.bottom, from)
        ..[to + 2] = read(layout.front, from)
        ..[to + 3] = read(layout.emission, from);
    }
  }
  return (positive: positive, negative: negative);
}
