import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';

/// The folder at [path], as a shelf: each frame a file in it, made when the
/// first frame is written.
PhotoShelf reelShelf(String path) =>
    FilePhotoShelf(appName: 'reel', directory: Directory(path));
