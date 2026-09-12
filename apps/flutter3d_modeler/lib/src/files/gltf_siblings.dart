/// Turning a `.gltf`'s own external buffers and images into one self-
/// contained file, so the single-file path every decoder already has is the
/// only one that ever has to exist — `ui-36n`'s own row: `.gltf` with a
/// sibling `.bin` opens nowhere near a file system to read it from, on the
/// web most of all.
///
/// **A rewrite, not a second code path through the decoder.** `flutter3d_
/// formats`'s own `resolveBuffers`/`_decodeImages` already read a `data:`
/// URI, a GLB binary chunk, or a resolver's own answer — three forms, and a
/// caller who wants a fourth ("here is the file this relative path names")
/// would be widening a decoder three packages away for one application's own
/// picker. Embedding sibling bytes as `data:` URIs before the bytes ever
/// reach `decodeModel` needs none of that: the decoder sees exactly the file
/// shape it already reads, and `AssetSource._Bytes.resolveUri` in
/// `opening.dart` — which throws for anything but a `data:` URI — never has
/// to answer for a sibling at all, because nothing named one survives past
/// this file.
///
/// **The media type in a `data:` URI is not read back.** `decodeDataUri`'s
/// own doc comment says as much — glTF spins through several
/// (`application/octet-stream`, `application/gltf-buffer`, `image/png`) and
/// only the base64 payload after the comma is ever used — so every sibling
/// here is embedded under the same one, `application/octet-stream`, whether
/// it is the `.bin` or a texture. Detecting a real MIME type would be
/// answering a question nothing downstream asks.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The relative URIs [gltfBytes] names in `buffers`/`images`, decoded — the
/// files a caller has to find and hand to [embedGltfSiblings] before this
/// `.gltf` can be opened anywhere without its own directory beside it.
///
/// A `data:` URI already carries its own bytes and needs nothing found;
/// only what is left is a real gap. Malformed JSON, or a `.glb`'s own binary
/// framing, answers with the empty set rather than throwing — this exists to
/// ask "is there anything to go and find", and the decoder itself is still
/// the one place a truly broken file gets to say why it refuses.
Set<String> gltfSiblingUris(Uint8List gltfBytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(gltfBytes));
  } catch (_) {
    return const <String>{};
  }
  if (json is! Map) return const <String>{};

  final uris = <String>{};
  for (final key in <String>['buffers', 'images']) {
    final list = json[key];
    if (list is! List) continue;
    for (final entry in list) {
      if (entry is! Map) continue;
      final uri = entry['uri'];
      if (uri is String && !uri.startsWith('data:')) {
        uris.add(Uri.decodeComponent(uri));
      }
    }
  }
  return uris;
}

/// [gltfBytes] with every `buffers`/`images` entry whose own URI matches a
/// key in [siblingsByName] rewritten to a `data:` URI carrying those bytes.
///
/// Matched by the URI's own last path segment against [siblingsByName]'s own
/// keys — a `.gltf` that names `textures/base.png` is matched by a sibling
/// named `base.png`, since a file picker hands back flat names with no
/// folder a browser or a sandboxed dialogue can reconstruct. A URI this
/// finds no match for is left exactly as it was: the decoder's own existing
/// refusal (fatal for a missing buffer, a warning for a missing image) is
/// what a genuinely absent sibling should still get, not a silent one from
/// here.
///
/// Bytes back unchanged, not a copy of the original object, when [gltfBytes]
/// is not JSON at all — a `.glb` handed here by mistake has nothing this can
/// rewrite, and decoding it is `decodeModel`'s own job to refuse or accept.
Uint8List embedGltfSiblings(
  Uint8List gltfBytes,
  Map<String, Uint8List> siblingsByName,
) {
  if (siblingsByName.isEmpty) return gltfBytes;

  final Object? json;
  try {
    json = jsonDecode(utf8.decode(gltfBytes));
  } catch (_) {
    return gltfBytes;
  }
  if (json is! Map<String, Object?>) return gltfBytes;

  var changed = false;
  for (final key in <String>['buffers', 'images']) {
    final list = json[key];
    if (list is! List) continue;
    for (final entry in list) {
      if (entry is! Map<String, Object?>) continue;
      final uri = entry['uri'];
      if (uri is! String || uri.startsWith('data:')) continue;
      final baseName = Uri.decodeComponent(uri).split('/').last;
      final bytes = siblingsByName[baseName];
      if (bytes == null) continue;
      entry['uri'] = 'data:application/octet-stream;base64,'
          '${base64Encode(bytes)}';
      changed = true;
    }
  }
  if (!changed) return gltfBytes;
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}
