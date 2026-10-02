import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'photo_shelf.dart';

/// Photos handed to the browser: the system share sheet where the browser
/// offers one for files, a download everywhere else.
///
/// **The pieces become `Blob` parts as they arrive**, so the PNG is assembled
/// by the browser outside the Dart heap and is never one buffer here.
///
/// **The share sheet may refuse, and that is not a failure.** Browsers only
/// open it inside a user gesture, and a large capture can outlast the
/// gesture that started it; a refusal for that reason, like a player
/// cancelling the sheet, falls back to the download, so the picture is kept
/// either way.
final class BrowserPhotoShelf implements PhotoShelf {
  BrowserPhotoShelf({this.share = true});

  /// Whether to try the share sheet at all before downloading.
  final bool share;

  @override
  Future<PhotoSaving> open(String name) async => _BlobSaving(name, share);
}

final class _BlobSaving implements PhotoSaving {
  _BlobSaving(this.name, this.share);

  final String name;
  final bool share;
  final List<web.BlobPart> _parts = <web.BlobPart>[];

  @override
  void add(Uint8List bytes) => _parts.add(bytes.toJS);

  @override
  Future<PhotoSaved> close() async {
    try {
      final file = web.File(
        _parts.toJS,
        name,
        web.FilePropertyBag(type: 'image/png'),
      );
      _parts.clear();
      if (share) {
        final data = web.ShareData(files: <web.File>[file].toJS);
        try {
          if (web.window.navigator.canShare(data)) {
            await web.window.navigator.share(data).toDart;
            return PhotoSaved(
              kept: true,
              shared: true,
              where: name,
              message: 'Shared $name.',
            );
          }
        } catch (_) {
          // Cancelled, or the gesture ran out while the picture was drawn:
          // the download below keeps it all the same.
        }
      }
      final url = web.URL.createObjectURL(file);
      (web.document.createElement('a') as web.HTMLAnchorElement)
        ..href = url
        ..download = name
        ..click();
      web.URL.revokeObjectURL(url);
      return PhotoSaved(kept: true, where: name, message: 'Downloaded $name.');
    } catch (error) {
      return PhotoSaved(
        kept: false,
        message: 'The browser would not take $name: $error',
      );
    }
  }

  @override
  Future<void> abandon() async => _parts.clear();
}

/// The shelf a browser build gets.
PhotoShelf defaultPhotoShelf(String appName) => BrowserPhotoShelf();
