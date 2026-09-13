/// [resizeRgba], [toPowerOfTwo] and [FitTexturesToProfile] — `mat-29`'s own
/// row: resizing a decoded texture, and a project's own images down to a
/// profile's budget, without ever asking what decoded them.
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';

import 'image_dimensions.dart';
import 'project.dart';
import 'texture_budget.dart';

/// Which algorithm [resizeRgba] samples with.
enum ResizeFilter {
  /// Every output pixel is the plain average of the source pixels its own
  /// box covers — the filter that makes a flat 2×2 checker collapse to a
  /// flat grey rather than to whichever corner a nearest-pixel sample
  /// happened to land on. The one to ask for when shrinking, since it is
  /// answering "what does this area look like averaged," which growing an
  /// image has no source area to average.
  box,

  /// Every output pixel interpolates the four nearest source pixels —
  /// smooth in both directions, the one to ask for when the image is
  /// growing and there is no area to average, only points to sit between.
  bilinear,
}

/// [rgba] ([width]×[height], four bytes a pixel) resampled to
/// [newWidth]×[newHeight] by [filter].
Uint8List resizeRgba(
  Uint8List rgba,
  int width,
  int height,
  int newWidth,
  int newHeight, {
  ResizeFilter filter = ResizeFilter.bilinear,
}) {
  if (width == newWidth && height == newHeight) {
    return Uint8List.fromList(rgba);
  }
  return switch (filter) {
    ResizeFilter.box => _resizeBox(rgba, width, height, newWidth, newHeight),
    ResizeFilter.bilinear => _resizeBilinear(
      rgba,
      width,
      height,
      newWidth,
      newHeight,
    ),
  };
}

Uint8List _resizeBox(
  Uint8List rgba,
  int width,
  int height,
  int newWidth,
  int newHeight,
) {
  final out = Uint8List(newWidth * newHeight * 4);
  for (var oy = 0; oy < newHeight; oy++) {
    final sy0 = oy * height ~/ newHeight;
    final sy1 = ((oy + 1) * height / newHeight).ceil().clamp(sy0 + 1, height);
    for (var ox = 0; ox < newWidth; ox++) {
      final sx0 = ox * width ~/ newWidth;
      final sx1 = ((ox + 1) * width / newWidth).ceil().clamp(sx0 + 1, width);
      final sums = <int>[0, 0, 0, 0];
      var count = 0;
      for (var sy = sy0; sy < sy1; sy++) {
        for (var sx = sx0; sx < sx1; sx++) {
          final at = (sy * width + sx) * 4;
          sums[0] += rgba[at];
          sums[1] += rgba[at + 1];
          sums[2] += rgba[at + 2];
          sums[3] += rgba[at + 3];
          count++;
        }
      }
      final at = (oy * newWidth + ox) * 4;
      out[at] = sums[0] ~/ count;
      out[at + 1] = sums[1] ~/ count;
      out[at + 2] = sums[2] ~/ count;
      out[at + 3] = sums[3] ~/ count;
    }
  }
  return out;
}

Uint8List _resizeBilinear(
  Uint8List rgba,
  int width,
  int height,
  int newWidth,
  int newHeight,
) {
  final out = Uint8List(newWidth * newHeight * 4);
  int sample(int x, int y, int channel) =>
      rgba[(y.clamp(0, height - 1) * width + x.clamp(0, width - 1)) * 4 +
          channel];
  for (var oy = 0; oy < newHeight; oy++) {
    final sy = (oy + 0.5) * height / newHeight - 0.5;
    final y0 = sy.floor();
    final fy = sy - y0;
    for (var ox = 0; ox < newWidth; ox++) {
      final sx = (ox + 0.5) * width / newWidth - 0.5;
      final x0 = sx.floor();
      final fx = sx - x0;
      final at = (oy * newWidth + ox) * 4;
      for (var c = 0; c < 4; c++) {
        final top =
            sample(x0, y0, c) * (1 - fx) + sample(x0 + 1, y0, c) * fx;
        final bottom =
            sample(x0, y0 + 1, c) * (1 - fx) +
            sample(x0 + 1, y0 + 1, c) * fx;
        out[at + c] = (top * (1 - fy) + bottom * fy).round().clamp(0, 255);
      }
    }
  }
  return out;
}

/// [n] rounded to the nearest power of two, ties going to the higher one —
/// a texture unit that wants power-of-two dimensions cares about the
/// nearer size, not which side of it [n] happened to fall.
int toPowerOfTwo(int n) {
  if (n <= 1) return 1;
  var upper = 1;
  while (upper < n) {
    upper *= 2;
  }
  final lower = upper ~/ 2;
  return (n - lower) < (upper - n) ? lower : upper;
}

/// [project]'s own images, each clamped independently on width and height
/// to `profile.textures.maxSide` — not scaled to fit a box keeping its own
/// proportions, clamped axis by axis, so a 1000×600 image against a
/// 512px budget becomes 512×512 rather than 512×307. Images already
/// within budget, and any this package's own [decodePng] cannot read, are
/// carried over unchanged.
///
/// **Never mutates [project]; always answers a new one.** The row's own
/// "с сохранением источника" (keeping the source): a project's images stay
/// full resolution always, and this is the shrink an export path calls on
/// a copy when its own "shrink at export" option is on, not something
/// that happens to the open project itself.
///
/// [budget] defaults to [project]'s own [ProjectProfile.textures] — a
/// caller with a profile already set on the project, the ordinary case.
/// `mcp-09n`'s own `makeGameReady(profile)` is the one that passes a
/// different [TextureBudget] explicitly: an agent asking for "mobile"
/// textures on a project whose own profile is still "desktop" is not
/// asking to change the project's profile, only to fit its images to a
/// budget for this one call.
// The row's own text names this `FitTexturesToProfile`, capitalised unlike
// its two neighbours (`resizeRgba`, `toPowerOfTwo`) in the same row; kept
// literal since `verify_plan.dart` reads names off that text, not off
// Dart's own naming convention.
// ignore: non_constant_identifier_names
ModelProject FitTexturesToProfile(ModelProject project, {TextureBudget? budget}) {
  final effectiveBudget = budget ?? project.profile.textures;
  var changed = false;
  final resized = <EncodedImage>[
    for (final image in project.images)
      _fitOne(
        image,
        effectiveBudget.maxSide,
        (bool didResize) => changed |= didResize,
      ),
  ];
  if (!changed) return project;
  return ModelProject(
    profile: project.profile,
    objects: project.objects,
    materials: project.materials,
    images: resized,
    nextId: project.nextId,
    skeletons: project.skeletons,
    clips: project.clips,
    lighting: project.lighting,
  );
}

EncodedImage _fitOne(EncodedImage image, int maxSide, void Function(bool) mark) {
  final dimensions = imageDimensions(image.bytes);
  if (dimensions == null ||
      (dimensions.width <= maxSide && dimensions.height <= maxSide)) {
    mark(false);
    return image;
  }
  final decoded = decodePng(image.bytes);
  if (decoded == null) {
    mark(false); // not a format this package can decode — carried over as-is
    return image;
  }
  final newWidth = decoded.width > maxSide ? maxSide : decoded.width;
  final newHeight = decoded.height > maxSide ? maxSide : decoded.height;
  final resized = resizeRgba(
    decoded.rgba,
    decoded.width,
    decoded.height,
    newWidth,
    newHeight,
    filter: ResizeFilter.box,
  );
  mark(true);
  return EncodedImage(
    bytes: encodeCompressedPng(newWidth, newHeight, resized),
    name: image.name,
    mimeType: 'image/png',
    sourceUri: image.sourceUri,
  );
}
