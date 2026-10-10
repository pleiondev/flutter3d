import 'package:flutter3d_app/flutter3d_app.dart';

/// A browser has no folder to write into: each frame is handed to the
/// browser as a download, as photo mode's pictures are, and [path] names
/// nothing.
PhotoShelf reelShelf(String path) => defaultPhotoShelf('reel');
