/// A `.glb` taken apart into a `.gltf`, its `.bin` and its textures: "Download
/// as .gltf".
///
/// **Written from the GLB, not from the document.** The engine's writer
/// promises one self-contained file, and everything it puts in one is what a
/// `.gltf` beside a `.bin` holds too: the same JSON, with the buffer named by
/// a file instead of the binary chunk, and each image moved out to a file of
/// its own. So this is a rearrangement of bytes the writer already checked,
/// not a second glTF writer that could disagree with the first.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart' show GlbContainer;

/// [glb] as files, the `.gltf` first: `<baseName>.gltf`, `<baseName>.bin`,
/// and `textures/<n>.<ext>` for each image.
///
/// When the binary chunk can be laid out again safely — one buffer, no
/// buffer view that carries an extension of its own — the image bytes are
/// left out of the `.bin`, so a texture is not shipped twice. Otherwise the
/// `.bin` is the binary chunk as it was, and the images are still written
/// beside it.
List<(String, Uint8List)> splitGlb(Uint8List glb, {required String baseName}) {
  final container = GlbContainer.parse(glb);
  final json = _copy(container.json);
  final binary = container.binaryChunk;
  final images = _list(json['images']);
  final views = _list(json['bufferViews']);
  final buffers = _list(json['buffers']);

  final textures = <(String, Uint8List)>[];
  final imageViews = <int>{};
  for (final (index, image) in images.indexed) {
    final view = image['bufferView'];
    if (view is! int || binary == null || view < 0 || view >= views.length) {
      continue;
    }
    final bytes = _viewBytes(views[view], binary);
    if (bytes == null) continue;
    final path = 'textures/$index${_extensionOf(image['mimeType'])}';
    textures.add((path, bytes));
    imageViews.add(view);
    image
      ..remove('bufferView')
      ..['uri'] = path;
  }

  final canCompact =
      buffers.length == 1 &&
      imageViews.isNotEmpty &&
      views.every((view) => view['extensions'] == null);
  final Uint8List bin;
  if (binary == null) {
    bin = Uint8List(0);
  } else if (canCompact) {
    bin = _withoutViews(json, views, imageViews, binary);
  } else {
    bin = binary;
  }

  if (buffers.isNotEmpty && binary != null) {
    buffers.first
      ..['uri'] = '$baseName.bin'
      ..['byteLength'] = bin.length;
  }

  final text = const JsonEncoder.withIndent('  ').convert(json);
  return <(String, Uint8List)>[
    ('$baseName.gltf', Uint8List.fromList(utf8.encode(text))),
    if (binary != null && buffers.isNotEmpty) ('$baseName.bin', bin),
    ...textures,
  ];
}

/// The binary chunk again without the buffer views in [dropped], every other
/// view moved to its new offset and every index into `bufferViews` renumbered.
Uint8List _withoutViews(
  Map<String, Object?> json,
  List<Map<String, Object?>> views,
  Set<int> dropped,
  Uint8List binary,
) {
  final out = BytesBuilder(copy: false);
  final renumbered = <int, int>{};
  final kept = <Map<String, Object?>>[];
  for (final (index, view) in views.indexed) {
    if (dropped.contains(index)) continue;
    final bytes = _viewBytes(view, binary) ?? Uint8List(0);
    // Every view starts on a four-byte boundary, which is what an accessor
    // of any component type needs.
    final padding = (4 - out.length % 4) % 4;
    if (padding > 0) out.add(Uint8List(padding));
    view['byteOffset'] = out.length;
    out.add(bytes);
    renumbered[index] = kept.length;
    kept.add(view);
  }
  json['bufferViews'] = kept;

  void renumber(Map<String, Object?> holder) {
    final view = holder['bufferView'];
    if (view is int && renumbered[view] != null) {
      holder['bufferView'] = renumbered[view];
    }
  }

  for (final accessor in _list(json['accessors'])) {
    renumber(accessor);
    final sparse = accessor['sparse'];
    if (sparse is Map<String, Object?>) {
      for (final part in [sparse['indices'], sparse['values']]) {
        if (part is Map<String, Object?>) renumber(part);
      }
    }
  }
  for (final image in _list(json['images'])) {
    renumber(image);
  }
  return out.toBytes();
}

Uint8List? _viewBytes(Map<String, Object?> view, Uint8List binary) {
  final offset = (view['byteOffset'] as num?)?.toInt() ?? 0;
  final length = (view['byteLength'] as num?)?.toInt();
  if (length == null || offset < 0 || offset + length > binary.length) {
    return null;
  }
  return Uint8List.fromList(
    Uint8List.sublistView(binary, offset, offset + length),
  );
}

String _extensionOf(Object? mimeType) => switch (mimeType) {
  'image/png' => '.png',
  'image/jpeg' => '.jpg',
  'image/webp' => '.webp',
  'image/ktx2' => '.ktx2',
  _ => '.bin',
};

List<Map<String, Object?>> _list(Object? value) => value is List
    ? value.whereType<Map<String, Object?>>().toList()
    : const <Map<String, Object?>>[];

/// A deep copy, so the parsed container is not edited in place.
Map<String, Object?> _copy(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;
