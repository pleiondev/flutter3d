/// Photo mode's picture: a frame of any size, drawn in tiles, finished and
/// handed out a strip at a time — `N8`.
///
/// **Strips rather than a frame, because "any resolution" is a promise about
/// memory.** A 16384 × 16384 picture is a gigabyte of RGBA, which a phone does
/// not have and a browser tab will not be given. Drawn a row of tiles at a
/// time and handed to a sink that writes it out — `PngStripWriter` in
/// `flutter3d_cpu` is the one this was written for — the most this holds is
/// one row of tiles, whatever the size of the picture.
///
/// **Everything that knows where the frame's edge is happens here, over the
/// whole frame, and not in the tiles.** A tile does not know it is a tile: its
/// composite would darken its own corners for a vignette and lay its own grain
/// from its own origin, and the stitched picture would have a vignette per
/// tile. So those two are taken out of the tiles' settings and put back by
/// [PhotoFinish], which mirrors the composite's arithmetic at the frame's own
/// pixel coordinates.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import '../../formats/srgb.dart';
import '../scene/camera_node.dart';
import '../scene/projection.dart';
import '../scene/scene.dart';
import 'render_view.dart';
import 'renderer.dart';

/// A look a player picks in photo mode.
///
/// **A change to the game's own [LookSettings] rather than a pass of its
/// own**, so every filter is drawn by the composite every backend already has
/// and the CPU backend already mirrors — four backends agreeing about a filter
/// costs nothing new. The colour parts work per pixel and so survive tiling as
/// they are; the vignette and the grain do not, and [PhotoFinish] puts them
/// back over the whole frame.
///
/// **Composed onto the game's look, not put in its place**: a game graded
/// cold for a night level stays cold under [warm], only less so. Contrast and
/// saturation multiply, temperature and tint add, the vignette and the grain
/// take the larger of the two, a gain multiplies channel by channel, and a
/// lift replaces the game's because two lifts do not compose into anything a
/// person chose.
final class PhotoFilter {
  const PhotoFilter({
    required this.name,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.vignette = 0.0,
    this.grain = 0.0,
    this.lift,
    this.gain,
  });

  /// What a menu calls it; also how a game saves which one was last picked.
  final String name;

  final double contrast;
  final double saturation;
  final double temperature;
  final double tint;
  final double vignette;
  final double grain;
  final vm.Vector3? lift;
  final vm.Vector3? gain;

  static const PhotoFilter none = PhotoFilter(name: 'none');
  static const PhotoFilter vivid = PhotoFilter(
    name: 'vivid',
    contrast: 1.15,
    saturation: 1.35,
  );
  static const PhotoFilter warm = PhotoFilter(
    name: 'warm',
    temperature: 0.35,
    saturation: 1.05,
  );
  static const PhotoFilter cool = PhotoFilter(
    name: 'cool',
    temperature: -0.35,
    tint: -0.05,
  );
  static const PhotoFilter mono = PhotoFilter(
    name: 'mono',
    saturation: 0.0,
    contrast: 1.1,
  );

  /// Mono with a brown gain — the print rather than the negative.
  static final PhotoFilter sepia = PhotoFilter(
    name: 'sepia',
    saturation: 0.0,
    contrast: 0.95,
    gain: vm.Vector3(1.08, 0.96, 0.78),
    lift: vm.Vector3(0.03, 0.02, 0.0),
    vignette: 0.25,
  );
  static const PhotoFilter noir = PhotoFilter(
    name: 'noir',
    saturation: 0.0,
    contrast: 1.45,
    vignette: 0.55,
    grain: 0.04,
  );
  static final PhotoFilter faded = PhotoFilter(
    name: 'faded',
    contrast: 0.85,
    saturation: 0.75,
    lift: vm.Vector3.all(0.06),
  );

  /// The order a menu shows them in.
  static final List<PhotoFilter> all = <PhotoFilter>[
    none,
    vivid,
    warm,
    cool,
    mono,
    sepia,
    noir,
    faded,
  ];

  /// The filter called [name], or [none] for a name no filter has — a saved
  /// choice from a build that had a filter this one does not.
  static PhotoFilter named(String name) =>
      all.firstWhere((filter) => filter.name == name, orElse: () => none);

  /// [look] with this filter on it, for the live view.
  LookSettings applyTo(LookSettings look) => look.copyWith(
    contrast: look.contrast * contrast,
    saturation: look.saturation * saturation,
    temperature: (look.temperature + temperature).clamp(-1.0, 1.0),
    tint: (look.tint + tint).clamp(-1.0, 1.0),
    vignette: math.max(look.vignette, vignette),
    grain: math.max(look.grain, grain),
    lift: lift ?? look.lift,
    gain: switch ((look.gain, gain)) {
      (final a?, final b?) => vm.Vector3(a.x * b.x, a.y * b.y, a.z * b.z),
      (final a, final b) => b ?? a,
    },
  );
}

/// The vignette and the grain, put over a finished frame at its own
/// coordinates.
///
/// **The composite's arithmetic, moved after the encode.** The composite
/// darkens linear light by `1 − vignette · r` and then encodes; here the
/// encoded byte is decoded, darkened by the same factor and encoded again,
/// which is the same picture to within the rounding of one extra trip through
/// eight bits. The grain is the composite's own hash of the pixel's position,
/// added after the encode as the composite adds it — at the frame's position
/// rather than the tile's, which is the whole reason this exists.
final class PhotoFinish {
  PhotoFinish({
    required this.width,
    required this.height,
    required this.vignette,
    required this.roundness,
    required this.grain,
  });

  /// What [look] asks of the frame's edges, for a frame [width] × [height].
  factory PhotoFinish.of(LookSettings look, int width, int height) =>
      PhotoFinish(
        width: width,
        height: height,
        vignette: look.vignette.clamp(0.0, 1.0),
        roundness: look.vignetteRoundness.clamp(0.0, 1.0),
        grain: math.max(look.grain, 0.0),
      );

  final int width;
  final int height;
  final double vignette;
  final double roundness;
  final double grain;

  bool get isNeutral => vignette == 0.0 && grain == 0.0;

  static final Float64List _decode = Float64List.fromList(
    List<double>.generate(256, (i) => srgbToLinear(i / 255.0)),
  );

  /// Applies itself to [rows] rows of RGBA starting at frame row [top].
  void apply(Uint8List rgba, int top, int rows) {
    if (isNeutral) return;
    final aspect = width / height;
    final stretch = 1.0 + (aspect - 1.0) * roundness;
    for (var row = 0; row < rows; row++) {
      final y = top + row;
      final fy = (y + 0.5) / height - 0.5;
      for (var x = 0; x < width; x++) {
        final at = (row * width + x) * 4;
        final fx = ((x + 0.5) / width - 0.5) * stretch;
        final r = math.min(math.sqrt(fx * fx + fy * fy) * 1.41421356, 1.0);
        final keep = 1.0 - vignette * r;
        final noise = grain == 0.0
            ? 0.0
            : (_hash(x + 0.5, y + 0.5) - 0.5) * grain;
        for (var c = 0; c < 3; c++) {
          final encoded = vignette == 0.0
              ? rgba[at + c] / 255.0
              : linearToSrgb(_decode[rgba[at + c]] * keep);
          rgba[at + c] = ((encoded + noise).clamp(0.0, 1.0) * 255.0).round();
        }
      }
    }
  }

  /// `Hash` from `composite.frag`, as the software backend writes it.
  static double _hash(double x, double y) {
    final t = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
    return t - t.floorToDouble();
  }
}

/// What a capture did to the game's settings, and why.
///
/// **Said rather than done quietly.** Each of these is a real difference
/// between the picture on screen and the picture saved, and a player who
/// notices one deserves a sentence rather than a bug report.
final class PhotoCaptureReport {
  const PhotoCaptureReport({
    required this.width,
    required this.height,
    required this.tilesX,
    required this.tilesY,
    required this.margin,
    required this.exposure,
    required this.setAside,
  });

  final int width;
  final int height;
  final int tilesX;
  final int tilesY;

  /// Pixels of picture drawn round each tile and cropped away.
  final int margin;

  /// The exposure every tile was drawn at.
  final double exposure;

  /// One sentence per setting the capture could not carry over.
  final List<String> setAside;
}

const String _noTemporal =
    'temporal anti-aliasing is off: it resolves over frames a still tile '
    'does not have';
const String _noMotionBlur =
    'motion blur is off: the camera moved since the world stopped, and that '
    'is not motion in the picture';
const String _noAberration =
    'chromatic aberration is left out: it is centred on each tile, and no '
    'whole-frame version is written yet';
const String _noScale =
    'render scale and upscaling are off: the picture is drawn at its own size';
const String _noExtended =
    'the extended-range output is written as standard range';

/// The settings every tile of a photo is drawn with, and what had to change.
///
/// [exposure] is the one the game last drew with — `Renderer.exposure` — so
/// the picture is as bright as the screen was. A meter running per tile would
/// expose a tile of sky darker than a tile of shadow and the seams would show.
({RenderSettings tile, LookSettings look, List<String> setAside}) photoSettings(
  RenderSettings settings,
  PhotoFilter filter,
  double exposure,
) {
  final look = filter.applyTo(settings.look);
  final held =
      'auto exposure is held at ${exposure.toStringAsFixed(3)}, the value on '
      'screen, so every tile is exposed alike';
  final setAside = <String>[
    if (settings.autoExposure.enabled) held,
    if (settings.antiAlias.temporal.enabled) _noTemporal,
    if (settings.motionBlur.enabled) _noMotionBlur,
    if (look.chromaticAberration > 0.0) _noAberration,
    if (settings.renderScale != 1.0 || settings.spatialUpscale.enabled)
      _noScale,
    if (settings.outputTransform != OutputTransform.sdr) _noExtended,
  ];
  final tile = settings.copyWith(
    exposure: exposure,
    autoExposure: const AutoExposureSettings(),
    antiAlias: settings.antiAlias.copyWith(temporal: const TemporalSettings()),
    motionBlur: settings.motionBlur.copyWith(enabled: false),
    renderScale: 1.0,
    spatialUpscale: const SpatialUpscaleSettings(),
    outputTransform: OutputTransform.sdr,
    look: look.copyWith(vignette: 0.0, grain: 0.0, chromaticAberration: 0.0),
  );
  return (tile: tile, look: look, setAside: setAside);
}

/// Draws [scene] through [camera] at [width] × [height] and hands it to
/// [onRows] a row of tiles at a time, top to bottom, finished and opaque.
///
/// Each tile is [tileWidth] × [tileHeight] of the picture drawn with [margin]
/// pixels more on every side, through a [CropProjection] of [camera]'s own
/// projection; the margin is thrown away. **What the margin is for:** bloom,
/// ambient occlusion, depth of field and screen-space reflections read
/// neighbours, and at a tile's edge without one they read the clear colour —
/// a seam down the picture wherever a highlight sits near one. With a margin
/// wider than what they read, the neighbours are real. Bloom's widest levels
/// reach further than any margin, so a capture with bloom is close to the
/// screen rather than equal to it; `photo_capture_test.dart` measures how
/// close.
///
/// The camera's projection is borrowed for the capture and put back after it,
/// failure included. The renderer is the game's own: a photo is drawn on the
/// device that is already up, at the size the game asks, so nothing about it
/// needs a second device. **Nothing else may draw on it until this returns.**
/// A hardware readback can resolve a frame or two after the ask, and a game
/// frame drawn in between takes its targets from the same pool as the tile
/// waiting to be read — so a game stops redrawing its surface while a photo
/// is taken, which it is free to do with the world paused.
///
/// [onRows] gets `width × rows × 4` bytes for frame rows `top` to
/// `top + rows`, and is awaited before the next row of tiles is drawn, so a
/// sink writing to a disk holds this back rather than letting it run ahead.
Future<PhotoCaptureReport> capturePhoto({
  required Renderer renderer,
  required Scene scene,
  required CameraNode camera,
  required int width,
  required int height,
  required FutureOr<void> Function(Uint8List rgba, int top, int rows) onRows,
  RenderSettings settings = const RenderSettings(),
  PhotoFilter filter = PhotoFilter.none,
  vm.Vector4? clearColor,
  int layerMask = ~0,
  int tileWidth = 1024,
  int tileHeight = 1024,
  int margin = 32,
  void Function(double progress)? onProgress,
}) async {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('A photo of ${width}x$height has no pixels to draw.');
  }
  if (tileWidth <= 0 || tileHeight <= 0 || margin < 0) {
    throw ArgumentError(
      'Tiles of ${tileWidth}x$tileHeight with a margin of $margin cannot '
      'cover a picture; tiles need a size and a margin cannot be negative.',
    );
  }
  final tilesX = (width + tileWidth - 1) ~/ tileWidth;
  final tilesY = (height + tileHeight - 1) ~/ tileHeight;
  final chosen = photoSettings(settings, filter, renderer.exposure);
  final finish = PhotoFinish.of(chosen.look, width, height);
  final drawWidth = tileWidth + 2 * margin;
  final drawHeight = tileHeight + 2 * margin;

  final whole = camera.projection;
  try {
    for (var tileY = 0; tileY < tilesY; tileY++) {
      final top = tileY * tileHeight;
      final rows = math.min(tileHeight, height - top);
      final strip = Uint8List(width * rows * 4);
      for (var tileX = 0; tileX < tilesX; tileX++) {
        final left = tileX * tileWidth;
        final columns = math.min(tileWidth, width - left);
        camera.projection = CropProjection(
          whole,
          frameAspect: width / height,
          left: (left - margin) / width,
          right: (left + tileWidth + margin) / width,
          top: (top - margin) / height,
          bottom: (top + tileHeight + margin) / height,
        );
        final result = renderer.render(
          width: drawWidth,
          height: drawHeight,
          scene: scene,
          views: <RenderView>[
            RenderView(
              camera: camera,
              clearColor: clearColor,
              layerMask: layerMask,
              cut: true,
            ),
          ],
          settings: chosen.tile,
        );
        final pixels = await renderer.device.readPixels(result.frame);
        if (pixels == null) {
          throw StateError(
            'Tile $tileX,$tileY of the photo could not be read back from the '
            'device it was drawn on; nothing was written past row $top.',
          );
        }
        final tile = pixels.buffer.asUint8List(
          pixels.offsetInBytes,
          pixels.lengthInBytes,
        );
        for (var row = 0; row < rows; row++) {
          final from = ((row + margin) * drawWidth + margin) * 4;
          strip.setRange(
            (row * width + left) * 4,
            (row * width + left + columns) * 4,
            tile,
            from,
          );
        }
        onProgress?.call((tileY * tilesX + tileX + 1) / (tilesX * tilesY));
      }
      // Opaque: a saved photo with the sky see-through is a picture of the
      // viewer's background, and a clear colour's alpha was never a choice
      // about the picture.
      for (var i = 3; i < strip.length; i += 4) {
        strip[i] = 255;
      }
      finish.apply(strip, top, rows);
      await onRows(strip, top, rows);
    }
  } finally {
    camera.projection = whole;
  }
  return PhotoCaptureReport(
    width: width,
    height: height,
    tilesX: tilesX,
    tilesY: tilesY,
    margin: margin,
    exposure: renderer.exposure,
    setAside: chosen.setAside,
  );
}
