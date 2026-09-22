/// The platform half of `ux-47` where there is no filesystem to watch.
///
/// **A browser cannot do this and should say so rather than pretend.** A
/// picked file arrives as bytes and the page never learns where it came
/// from; there is no path to watch, no notification when it changes, and no
/// system editor to hand it to. The File System Access API's own handles do
/// offer a re-read, but only for a file this page itself picked and only
/// while permission holds — which is a different feature with a different
/// consent story, not this one quietly working on the web too.
///
/// So the watch is a stream that never fires, the read answers null, and
/// "open in editor" answers false. Everything above this reads those as "no
/// hot-swap here", which is the truth.
library;

import 'dart:async';
import 'dart:typed_data';

import 'linked_materials.dart' show LinkedMaterialHost;

/// The same settle window the desktop half names, so nothing importing this
/// has to ask which platform it is on to find the constant.
const Duration kLinkedMaterialSettle = Duration(milliseconds: 120);

LinkedMaterialHost linkedMaterialHost() => (
  watch: (String path) => const Stream<void>.empty(),
  read: (String path) async => null,
  openInEditor: (String path) async => false,
);

/// Named so the two halves export the same shape.
typedef LinkedBytes = Uint8List;
