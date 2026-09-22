/// [PaintLayer]/[PaintStack]: a stack of paintable layers over one texture,
/// composited with a fixed set of blend modes — `pro-pt-01`'s own shape.
///
/// **Five modes and no others**, the plan's own list: [BlendMode.normal],
/// [BlendMode.multiply], [BlendMode.add], [BlendMode.overlay],
/// [BlendMode.screen] — the same "fixed set, compiler-checked" choice
/// `TextureGraph` (`mat-10`) already made over a node kind, made here over a
/// blend formula instead.
///
/// **Tiled in 64×64 squares, and copy-on-write per tile.** A [PaintLayer]
/// holds a sparse [Map] from tile coordinate to [PaintTile], and a
/// [PaintTile] is immutable once painted — [PaintLayer.paintTile] returns a
/// *new* layer whose map is a fresh copy, but every tile that new layer did
/// not touch keeps the very [PaintTile] instance the original layer already
/// had. A stroke that dirties three tiles of a 4K canvas therefore copies
/// three tiles, not the sixty-two others sitting beside them — the same
/// reason `EditMesh`'s own history does not deep-copy a mesh on every
/// command.
///
/// **Straight alpha, and no linear-light conversion.** A pixel is four bytes,
/// 0..255, uncorrelated with how a display or a PNG encodes them; blending
/// is defined directly on these bytes read as 0..1 fractions. `mat-11`'s own
/// `bakeTextureGraph` decodes through the sRGB EOTF before compositing
/// because it is baking a *displayed* image; this is a paint stack over
/// whatever is already in memory, one layer below where that correction
/// belongs, and adding it here would be a second, disagreeing place to make
/// the same decision.
///
/// **What this file does not do.** Painting a stroke into a tile
/// (`PaintStrokeCommand`), pushing the flattened result to a GPU texture
/// with `overwriteTexture`, mip regeneration and AO/curvature masks are
/// `pro-pt-03`'s own row, which depends on this one; nothing here reads a
/// device or a mesh. `pro-pt-01`'s own acceptance is two lines — known
/// numbers per blend mode, and that layer order matters — and this file
/// stops at proving exactly those.
library;

import 'dart:typed_data';

/// The edge length of one [PaintTile], in pixels.
const int paintTileSize = 64;

/// The blend mode a [PaintLayer] composites with — the plan's own five and
/// no others.
///
/// **A value class rather than an enum.** `tool/structure.dart`'s own rule
/// treats an enum in a published package as either a closed external format
/// (glTF's alpha modes, its wrap modes) or machinery with a reviewed
/// exemption; this is neither — it is a fixed algorithmic set the same way
/// [LightingModel] is a fixed set of shaders, and that row's own answer is
/// the shape used here: a `final class` with named `const` instances, the
/// blend formula itself carried as a field rather than read off a `switch`.
final class BlendMode {
  const BlendMode._(this.name, this._blendChannel);

  /// Shown in a status line or a test failure; not read by anything that
  /// changes behavior on it.
  final String name;

  final double Function(double top, double bottom) _blendChannel;

  /// This mode's own color math, [top] blended over [bottom], both 0..1 —
  /// the part that differs between modes. Alpha itself is composited the
  /// same way regardless of mode; see [PaintStack._over].
  double blendChannel(double top, double bottom) => _blendChannel(top, bottom);

  static double _normal(double top, double bottom) => top;
  static double _multiply(double top, double bottom) => top * bottom;
  static double _add(double top, double bottom) {
    final sum = top + bottom;
    return sum > 1 ? 1 : sum;
  }

  static double _screen(double top, double bottom) =>
      1 - (1 - top) * (1 - bottom);
  static double _overlay(double top, double bottom) =>
      bottom < 0.5 ? 2 * top * bottom : 1 - 2 * (1 - top) * (1 - bottom);

  /// Plain alpha compositing: this layer's own color, mixed in by its own
  /// alpha over what is beneath it.
  static const BlendMode normal = BlendMode._('normal', _normal);

  /// `top * bottom`, per channel.
  static const BlendMode multiply = BlendMode._('multiply', _multiply);

  /// `top + bottom`, clamped to 1, per channel.
  static const BlendMode add = BlendMode._('add', _add);

  /// `bottom < 0.5 ? 2*top*bottom : 1 - 2*(1-top)*(1-bottom)`, per channel —
  /// multiply where the base is dark, screen where it is light.
  static const BlendMode overlay = BlendMode._('overlay', _overlay);

  /// `1 - (1-top)*(1-bottom)`, per channel.
  static const BlendMode screen = BlendMode._('screen', _screen);

  /// Every mode this class defines, for a picker to offer.
  static const List<BlendMode> values = <BlendMode>[
    normal,
    multiply,
    add,
    overlay,
    screen,
  ];

  @override
  String toString() => 'BlendMode.$name';
}

/// One straight-alpha RGBA8 [paintTileSize]×[paintTileSize] tile.
///
/// Immutable: a coat of paint over one pixel of it is a new [PaintTile], not
/// a mutation of this one, which is the fact [PaintLayer.paintTile]'s own
/// copy-on-write rests on.
final class PaintTile {
  PaintTile(this.pixels)
    : assert(
        pixels.length == paintTileSize * paintTileSize * 4,
        'a tile is exactly $paintTileSize×$paintTileSize RGBA8',
      );

  /// Row-major, four bytes per pixel, straight (not premultiplied) alpha.
  final Uint8List pixels;
}

/// A fully transparent pixel, read wherever a [PaintLayer] has no tile.
const List<double> _transparent = <double>[0, 0, 0, 0];

/// One layer of a [PaintStack]: a sparse grid of [PaintTile]s and the
/// [BlendMode] it composites with.
final class PaintLayer {
  PaintLayer({
    required this.tilesX,
    required this.tilesY,
    this.blendMode = BlendMode.normal,
    Map<int, PaintTile>? tiles,
  }) : tiles = tiles == null
           ? <int, PaintTile>{}
           : Map<int, PaintTile>.of(tiles);

  /// How many tiles wide/tall this layer is. A tile not present in [tiles]
  /// is fully transparent, so a blank layer need not allocate any of them.
  final int tilesX;
  final int tilesY;

  final BlendMode blendMode;

  /// Keyed by `ty * tilesX + tx`. Read through [tileAt] rather than
  /// directly; the key encoding is this class's own business.
  final Map<int, PaintTile> tiles;

  int _index(int tx, int ty) => ty * tilesX + tx;

  /// The tile at ([tx], [ty]), or null if nothing has been painted there.
  PaintTile? tileAt(int tx, int ty) => tiles[_index(tx, ty)];

  /// A new layer with tile ([tx], [ty]) replaced by [pixels] and every other
  /// tile shared, by reference, with this one.
  ///
  /// **The whole of this row's copy-on-write claim lives in this one line:**
  /// `Map<int, PaintTile>.of(tiles)` copies the map — sixty-some references —
  /// not the [PaintTile]s it points at. A caller holding the original layer
  /// still sees its own [PaintTile] instances afterward, `identical` to the
  /// ones it saw before, because nothing here touched them.
  PaintLayer paintTile(int tx, int ty, Uint8List pixels) {
    final next = Map<int, PaintTile>.of(tiles);
    next[_index(tx, ty)] = PaintTile(pixels);
    return PaintLayer(
      tilesX: tilesX,
      tilesY: tilesY,
      blendMode: blendMode,
      tiles: next,
    );
  }
}

/// Which tiles differ between [before] and [after], as `(tx, ty)` pairs.
///
/// **What copy-on-write is for, read back.** `pro-pt-03`'s stroke replaces
/// the tiles it touched and shares the rest *by reference*, so `identical`
/// answers "did this tile change" without comparing sixteen kilobytes of
/// pixels — and that answer is exactly the rectangle a renderer has to
/// re-upload. Without it a stroke costs a whole texture decode and upload
/// per gesture, which is the difference between painting and waiting.
///
/// A tile present in one stack and absent from the other counts as changed:
/// absent is transparent, and a stroke that put paint where there was none
/// is the ordinary case.
List<(int, int)> dirtyTilesBetween(PaintStack? before, PaintStack? after) {
  if (after == null) return const <(int, int)>[];
  final out = <(int, int)>{};
  for (var i = 0; i < after.layers.length; i++) {
    final PaintLayer now = after.layers[i];
    final PaintLayer? was = before != null && i < before.layers.length
        ? before.layers[i]
        : null;
    for (var ty = 0; ty < now.tilesY; ty++) {
      for (var tx = 0; tx < now.tilesX; tx++) {
        final PaintTile? a = was?.tileAt(tx, ty);
        final PaintTile? b = now.tileAt(tx, ty);
        if (identical(a, b)) continue;
        if (a == null && b == null) continue;
        out.add((tx, ty));
      }
    }
  }
  final list = out.toList()
    ..sort(((int, int) a, (int, int) b) {
      final int byRow = a.$2.compareTo(b.$2);
      return byRow != 0 ? byRow : a.$1.compareTo(b.$1);
    });
  return list;
}

/// The texel rectangle [tiles] cover, or null when there are none —
/// `(x, y, width, height)`, clamped to a canvas of [canvas] texels a side.
(int, int, int, int)? dirtyRectOf(List<(int, int)> tiles, int canvas) {
  if (tiles.isEmpty) return null;
  var minX = canvas, minY = canvas, maxX = 0, maxY = 0;
  for (final (int tx, int ty) in tiles) {
    minX = tx * paintTileSize < minX ? tx * paintTileSize : minX;
    minY = ty * paintTileSize < minY ? ty * paintTileSize : minY;
    final int right = (tx + 1) * paintTileSize;
    final int bottom = (ty + 1) * paintTileSize;
    maxX = right > maxX ? right : maxX;
    maxY = bottom > maxY ? bottom : maxY;
  }
  maxX = maxX > canvas ? canvas : maxX;
  maxY = maxY > canvas ? canvas : maxY;
  return (minX, minY, maxX - minX, maxY - minY);
}

/// An ordered stack of [PaintLayer]s, bottom ([layers] index 0) to top.
final class PaintStack {
  const PaintStack(this.layers);

  final List<PaintLayer> layers;

  /// [top] composited over [bottom] by straight-alpha "over" — each color
  /// channel run through [mode]'s own [BlendMode.blendChannel] first, alpha
  /// composited the same way regardless of [mode], using [top]'s own alpha
  /// as coverage.
  static List<double> _over(
    BlendMode mode,
    List<double> top,
    List<double> bottom,
  ) {
    final topAlpha = top[3];
    final bottomAlpha = bottom[3];
    final outAlpha = topAlpha + bottomAlpha * (1 - topAlpha);
    if (outAlpha == 0) return _transparent;
    final out = List<double>.filled(4, 0);
    for (var c = 0; c < 3; c++) {
      final blended = mode.blendChannel(top[c], bottom[c]);
      final mixed =
          blended * topAlpha + bottom[c] * bottomAlpha * (1 - topAlpha);
      out[c] = mixed / outAlpha;
    }
    out[3] = outAlpha;
    return out;
  }

  static List<double> _read(PaintTile? tile, int x, int y) {
    if (tile == null) return _transparent;
    final base = (y * paintTileSize + x) * 4;
    return <double>[
      tile.pixels[base] / 255,
      tile.pixels[base + 1] / 255,
      tile.pixels[base + 2] / 255,
      tile.pixels[base + 3] / 255,
    ];
  }

  /// The straight-alpha RGBA8 pixel this stack shows at image coordinate
  /// ([x], [y]), every layer composited bottom to top.
  ///
  /// Not cached and not the fast path for a whole canvas — [flatten] is —
  /// but it is the one both share, so a test asking about one pixel and a
  /// test asking about a whole tile are asking the same code the same
  /// question.
  List<double> pixelAt(int x, int y) {
    final tx = x ~/ paintTileSize;
    final ty = y ~/ paintTileSize;
    final px = x % paintTileSize;
    final py = y % paintTileSize;
    var acc = _transparent;
    for (final layer in layers) {
      final top = _read(layer.tileAt(tx, ty), px, py);
      acc = _over(layer.blendMode, top, acc);
    }
    return acc;
  }

  /// The whole stack composited into one straight-alpha RGBA8 buffer, sized
  /// to the bottom layer's own tile grid (every layer in a stack is expected
  /// to share one grid; a layer with a different `tilesX`/`tilesY` is not a
  /// case this row's acceptance asks for).
  Uint8List flatten() {
    if (layers.isEmpty) return Uint8List(0);
    final tilesX = layers.first.tilesX;
    final tilesY = layers.first.tilesY;
    final width = tilesX * paintTileSize;
    final height = tilesY * paintTileSize;
    final out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = pixelAt(x, y);
        final base = (y * width + x) * 4;
        for (var c = 0; c < 4; c++) {
          final byte = (pixel[c] * 255).round();
          out[base + c] = byte > 255 ? 255 : (byte < 0 ? 0 : byte);
        }
      }
    }
    return out;
  }
}
