/// The messages between the page and the decode worker, which both sides
/// compile: the page in the application's program, the worker in its own.
///
/// Plain JavaScript objects of strings, numbers and typed arrays, so they
/// cross by the browser's structured clone, and the bytes a reply carries
/// cross by transfer.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';

import '../render/panorama_faces.dart';

/// The version of these messages. The worker says it in its first message,
/// and a page that does not read that version decodes in place: a script
/// compiled from another release of this package is not one to send to.
const int decodeWorkerProtocol = 1;

/// The kinds of message, as their `type` field spells them.
abstract final class DecodeWorkerMessage {
  /// Worker to page, once, first: `protocol`.
  static const String ready = 'ready';

  /// Page to worker: `job`, `bytes`, `key`, `format`, `layout`,
  /// `objNormals`, `stlNormals`.
  static const String model = 'model';

  /// Page to worker: `job`, `size`, `levels`, and either `hdr` or
  /// `pixels` with `width` and `height`.
  static const String panorama = 'panorama';

  /// Worker to page: `job`, `read`, `uri` — a model's sibling file. Page to
  /// worker: `job`, `read`, and `bytes` or `error`.
  static const String read = 'read';

  /// Worker to page: `job`, and `f3d` for a model or `size`, `faces` and
  /// `chain` for a panorama (none where the panorama is not one).
  static const String done = 'done';

  /// Worker to page: `job`, `reason` — the page decodes in place.
  static const String inPlace = 'inPlace';
}

/// A plain object with [fields].
JSObject wireObject(Map<String, JSAny?> fields) {
  final object = JSObject();
  for (final MapEntry(:key, :value) in fields.entries) {
    object[key] = value;
  }
  return object;
}

/// [object]'s `type`.
String wireType(JSObject object) => (object['type']! as JSString).toDart;

/// [object]'s [field] as an int.
int wireInt(JSObject object, String field) =>
    (object[field]! as JSNumber).toDartInt;

/// [object]'s [field] as a string, or null.
String? wireString(JSObject object, String field) =>
    (object[field] as JSString?)?.toDart;

/// [object]'s [field] as bytes, or null.
Uint8List? wireBytes(JSObject object, String field) =>
    (object[field] as JSUint8Array?)?.toDart;

/// What crosses for [layout]: each attribute's name and component count.
JSArray<JSAny?> wireLayout(VertexLayout layout) => <JSAny?>[
  for (final attribute in layout.attributes) ...<JSAny?>[
    attribute.name.toJS,
    attribute.componentCount.toJS,
  ],
].toJS;

/// [wireLayout] read back.
VertexLayout readWireLayout(JSArray<JSAny?> wire) {
  final flat = wire.toDart;
  return VertexLayout(<VertexAttribute>[
    for (var i = 0; i + 1 < flat.length; i += 2)
      VertexAttribute(
        (flat[i]! as JSString).toDart,
        (flat[i + 1]! as JSNumber).toDartInt,
      ),
  ]);
}

/// The model job for [request], whose file the page read as [bytes].
JSObject wireModelJob(int job, ModelLoadRequest request, Uint8List bytes) =>
    wireObject(<String, JSAny?>{
      'type': DecodeWorkerMessage.model.toJS,
      'job': job.toJS,
      'bytes': bytes.toJS,
      'key': request.source.key.toJS,
      'format': request.format.name.toJS,
      'layout': wireLayout(request.layout),
      'objNormals': request.objNormals.name.toJS,
      'stlNormals': request.stlNormals.name.toJS,
    });

/// The built-in format called [name], or null for one the worker's program
/// does not know.
ModelFormat? wireFormat(String name) {
  for (final format in ModelFormat.values) {
    if (format.name == name) return format;
  }
  return null;
}

/// What crosses for [faces]: the size and every level's six faces, as
/// typed arrays the reply transfers.
JSObject wirePanoramaDone(int job, PanoramaFaces faces) => wireObject(
  <String, JSAny?>{
    'type': DecodeWorkerMessage.done.toJS,
    'job': job.toJS,
    'size': faces.size.toJS,
    'faces': _wireFaces(faces.faces),
    'chain': <JSAny?>[for (final level in faces.chain) _wireFaces(level)].toJS,
  },
);

JSArray<JSAny?> _wireFaces(List<ByteData> faces) =>
    <JSAny?>[for (final face in faces) Uint8List.sublistView(face).toJS].toJS;

/// [wirePanoramaDone] read back; null where the worker found no panorama.
PanoramaFaces? readWirePanorama(JSObject done) {
  if (done['faces'] == null) return null;
  List<ByteData> faces(JSAny? wire) => <ByteData>[
    for (final face in (wire! as JSArray<JSAny?>).toDart)
      ByteData.sublistView((face! as JSUint8Array).toDart),
  ];
  return PanoramaFaces(
    size: wireInt(done, 'size'),
    faces: faces(done['faces']),
    chain: <List<ByteData>>[
      for (final level in (done['chain']! as JSArray<JSAny?>).toDart)
        faces(level),
    ],
  );
}

/// The buffers of the typed arrays in [faces], for a reply to transfer:
/// each once, and only one a face has to itself.
JSArray<JSAny?> wirePanoramaTransfer(PanoramaFaces faces) => <JSAny?>[
  for (final buffer in <ByteBuffer>{
    for (final level in <List<ByteData>>[faces.faces, ...faces.chain])
      for (final face in level)
        if (face.offsetInBytes == 0 &&
            face.lengthInBytes == face.buffer.lengthInBytes)
          face.buffer,
  })
    buffer.toJS,
].toJS;
