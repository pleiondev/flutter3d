import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart' show PngStripWriter;
import 'package:vector_math/vector_math.dart';

export 'photo_shelf_native.dart'
    if (dart.library.js_interop) 'photo_shelf_web.dart';

/// Where photo mode puts a picture, and how it is passed on — `N8`.
///
/// **Opened, written to, closed, rather than handed a file**, because the file
/// is never whole in memory: `capturePhoto` makes a strip at a time and
/// `PngStripWriter` encodes it at once, so a shelf receives the PNG in pieces.
/// On a desktop the pieces go straight to disk; in a browser they become the
/// parts of a `Blob`, which the browser holds outside the Dart heap.
///
/// **Sharing is the shelf's call, not the game's.** In a phone's browser the
/// shelf offers the system share sheet with the file in it; on a desktop it
/// saves to the Pictures folder and says where. A game that wants the native
/// share sheet on Android or iOS implements this with the plugin it already
/// uses — this package does not pull one in for every game that has no use
/// for it.
abstract interface class PhotoShelf {
  /// A place for a PNG called [name], which includes its extension.
  Future<PhotoSaving> open(String name);
}

/// One picture on its way to a shelf.
abstract interface class PhotoSaving {
  /// The next bytes of the file, in order.
  void add(Uint8List bytes);

  /// Ends the file and passes it on. **Never throws**: a disk that is full
  /// and a share sheet the player cancelled are both answers.
  Future<PhotoSaved> close();

  /// Gives up on the file and leaves nothing half-written behind.
  Future<void> abandon();
}

/// What happened to a picture.
final class PhotoSaved {
  const PhotoSaved({
    required this.kept,
    required this.message,
    this.where,
    this.shared = false,
  });

  /// Whether the picture exists somewhere the player can find it.
  final bool kept;

  /// One sentence for the screen: where it went, or why it did not.
  final String message;

  /// A path or a file name, when there is one to show.
  final String? where;

  /// Whether it went to a share sheet rather than only to a folder.
  final bool shared;
}

/// A picture taken: what the capture did, and where the file went.
final class PhotoTaken {
  const PhotoTaken({required this.report, required this.saved});

  /// Null when the capture itself failed; [saved] says how.
  final PhotoCaptureReport? report;
  final PhotoSaved saved;
}

/// Draws [scene] through [camera] at [width] × [height] and puts it on
/// [shelf] as [name].
///
/// The whole of photo mode's last step in one call: `capturePhoto` for the
/// tiles, `PngStripWriter` for the file, [shelf] for where it goes. A capture
/// that fails part way abandons the file rather than leaving the first half
/// of a picture in the player's Pictures folder, and the failure comes back
/// as a [PhotoSaved] that says so.
Future<PhotoTaken> takePhoto({
  required Renderer renderer,
  required Scene scene,
  required CameraNode camera,
  required int width,
  required int height,
  required PhotoShelf shelf,
  required String name,
  RenderSettings settings = const RenderSettings(),
  PhotoFilter filter = PhotoFilter.none,
  Vector4? clearColor,
  int tileWidth = 1024,
  int tileHeight = 1024,
  void Function(double progress)? onProgress,
}) async {
  final saving = await shelf.open(name);
  try {
    final png = PngStripWriter(width: width, height: height, sink: saving.add);
    final report = await capturePhoto(
      renderer: renderer,
      scene: scene,
      camera: camera,
      width: width,
      height: height,
      settings: settings,
      filter: filter,
      clearColor: clearColor,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      onProgress: onProgress,
      onRows: (rgba, top, rows) => png.addRows(rgba, rows),
    );
    png.close();
    return PhotoTaken(report: report, saved: await saving.close());
  } catch (error) {
    await saving.abandon();
    return PhotoTaken(
      report: null,
      saved: PhotoSaved(
        kept: false,
        message: 'The picture was not taken: $error',
      ),
    );
  }
}
