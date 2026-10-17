/// A Flutter widget, drawn once, as a texture a material can sample.
///
/// The other direction across the boundary [SceneSurface] sits on: that one
/// hands a rendered frame to Flutter, this one hands a widget to the renderer.
/// A sign beside a road, a screen on a wall, a map on a table — anything whose
/// artwork is easier to write as widgets than to author as an image.
///
/// ## Off the tree, deliberately
///
/// The obvious way to get a widget's pixels is to put it in the tree inside a
/// `RepaintBoundary` and call `toImage` on that boundary's render object. That
/// works, and it costs the widget a place on screen: it has to be laid out
/// somewhere, so it ends up behind an `Offstage` or a zero-opacity stack that
/// every frame walks past, and its size is whatever the layout gives it rather
/// than the resolution the texture wants.
///
/// This builds its own one-widget pipeline instead — a [RenderView] with a
/// [BuildOwner] and a [PipelineOwner] of its own, rendering at exactly the size
/// asked for, at exactly the moment asked. Nothing about it reaches the
/// application's tree, so a caller does not have to find somewhere to hide it.
///
/// ## What it costs
///
/// On Impeller, nothing but the raster: the device is
/// `PlatformTextures<ui.Image>`, and flutter_gpu's `Texture.fromImage` wraps
/// the image's own GPU texture with no copy at all. Elsewhere a round trip:
/// [ui.Image.toByteData] brings the pixels back to the host and
/// [GraphicsDevice.createTextureFromPixels] sends them out again, the price
/// of a texture every backend can sample. Either way it is charged per
/// [draw], not per frame; `textureFromImage` picks the road.
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
// `RenderView` here is Flutter's, the root of a render tree; the engine's
// camera onto a viewport is `CameraView`, so the two never meet.
import 'package:flutter3d/flutter3d.dart';

import 'platform_texture.dart';
import 'widget_surface_pipeline.dart' show unmountWidgetTree;

/// Draws widgets into textures on one device.
///
/// Holds nothing between calls but the device: each [draw] builds its pipeline,
/// uses it, and lets it go. Keeping one alive between draws would mean keeping
/// a [BuildOwner] and its element tree alive too, which is a caching decision a
/// caller who draws twice a second should make and a caller who draws once
/// should not pay for.
final class WidgetTexture {
  const WidgetTexture(this.device);

  /// Where the pixels end up.
  final GraphicsDevice device;

  /// Rasterises [widget] at [width] by [height] and uploads it.
  ///
  /// [pixelRatio] is what a device pixel is worth to the widget. It is *not*
  /// the screen's: the size above is already in texture pixels, so the default
  /// of one draws text at the size the widget asks for. Pass more to author a
  /// sign at a comfortable logical size and get a sharper texture out of it.
  ///
  /// Null when the device refuses the upload — the same answer, for the same
  /// reason, [GraphicsDevice.createTextureFromPixels] gives.
  ///
  /// **A binding must be running.** This uses the same rasteriser the
  /// application draws with; there is no offscreen path that does not.
  Future<TextureHandle?> draw(
    Widget widget, {
    required int width,
    required int height,
    double pixelRatio = 1.0,
  }) async {
    final image = await rasterise(
      widget,
      width: width,
      height: height,
      pixelRatio: pixelRatio,
    );
    try {
      return await textureFromImage(device, image);
    } finally {
      // Copied, the image is a second picture nobody needs; wrapped, the
      // texture keeps the storage alive on its own.
      image.dispose();
    }
  }

  /// The widget as a [ui.Image], for a caller that wants the image itself.
  ///
  /// Separate from [draw] because the two answer different questions and one of
  /// them needs no device: a test that checks what a sign says can compare
  /// pixels without opening a backend at all.
  ///
  /// The caller owns the image and disposes it.
  static Future<ui.Image> rasterise(
    Widget widget, {
    required int width,
    required int height,
    double pixelRatio = 1.0,
  }) async {
    final boundary = RenderRepaintBoundary();
    final logical = Size(width / pixelRatio, height / pixelRatio);

    // A view of its own, so layout happens against the size the texture wants
    // rather than against whatever window the application has. `devicePixelRatio`
    // is what turns the logical size back into the pixel size asked for.
    final owner = PipelineOwner();
    final view = RenderView(
      view: WidgetsBinding.instance.platformDispatcher.views.first,
      configuration: ViewConfiguration(
        physicalConstraints: BoxConstraints.tight(logical * pixelRatio),
        logicalConstraints: BoxConstraints.tight(logical),
        devicePixelRatio: pixelRatio,
      ),
      child: boundary,
    );
    owner.rootNode = view;
    view.prepareInitialFrame();

    final build = BuildOwner(focusManager: FocusManager());
    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          // The widget is told the size it is being drawn at, so a layout
          // that reads `MediaQuery` gets an answer about its texture rather
          // than about the window behind it.
          data: MediaQueryData(size: logical, devicePixelRatio: pixelRatio),
          child: widget,
        ),
      ),
    ).attachToRenderTree(build);

    // One pass of the pipeline the framework runs every frame, by hand and in
    // the same order: build, then layout, then paint.
    build.buildScope(element);
    build.finalizeTree();
    owner.flushLayout();
    owner.flushCompositingBits();
    owner.flushPaint();

    try {
      return await boundary.toImage(pixelRatio: pixelRatio);
    } finally {
      // Unmounts the element tree this built, so the widgets it made are not
      // left holding tickers, listeners or images after their picture is taken.
      // `finalizeTree` on its own disposes only what was already deactivated,
      // which here is nothing — see [unmountWidgetTree].
      unmountWidgetTree(build, element, boundary);
    }
  }
}
