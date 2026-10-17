/// The decode worker's program: what `dart run flutter3d_core:decode_worker`
/// compiles into the script `WebDecodeWorker.use` names.
///
/// It runs in a Web Worker, with no page, no device and no Flutter: it reads
/// the bytes the page sends with the same decoders a native isolate runs,
/// and answers with what the page uploads. See `WebDecodeWorker` for the
/// whole of what it does and does not take.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

import '../render/panorama_faces.dart';
import 'decode_worker_wire.dart';

/// The worker's global scope.
@JS('self')
external JSObject get _scope;

void _post(JSObject message, [JSArray<JSAny?>? transfer]) {
  if (transfer == null) {
    _scope.callMethod<JSAny?>('postMessage'.toJS, message);
  } else {
    _scope.callMethod<JSAny?>('postMessage'.toJS, message, transfer);
  }
}

/// Sibling reads waiting on the page, by job and then by read.
final Map<int, Map<int, Completer<Uint8List>>> _reads =
    <int, Map<int, Completer<Uint8List>>>{};
int _nextRead = 0;

void main() {
  _scope.callMethod<JSAny?>(
    'addEventListener'.toJS,
    'message'.toJS,
    ((JSObject event) {
      unawaited(_receive(event['data']! as JSObject));
    }).toJS,
  );
  _post(
    wireObject(<String, JSAny?>{
      'type': DecodeWorkerMessage.ready.toJS,
      'protocol': decodeWorkerProtocol.toJS,
    }),
  );
}

Future<void> _receive(JSObject message) async {
  final job = wireInt(message, 'job');
  switch (wireType(message)) {
    case DecodeWorkerMessage.model:
      await _model(job, message);
    case DecodeWorkerMessage.panorama:
      _panorama(job, message);
    case DecodeWorkerMessage.read:
      final waiting = _reads[job]?.remove(wireInt(message, 'read'));
      if (waiting == null) return;
      final bytes = wireBytes(message, 'bytes');
      if (bytes != null) {
        waiting.complete(bytes);
      } else {
        waiting.completeError(
          StateError(wireString(message, 'error') ?? 'the page read nothing'),
          StackTrace.current,
        );
      }
    case final String other:
      // A page from another release; the protocol check at `ready` should
      // have kept it from sending this.
      _inPlace(job, 'the worker does not know a "$other" job');
  }
}

void _inPlace(int job, String reason) => _post(
  wireObject(<String, JSAny?>{
    'type': DecodeWorkerMessage.inPlace.toJS,
    'job': job.toJS,
    'reason': reason.toJS,
  }),
);

Future<void> _model(int job, JSObject message) async {
  final format = wireFormat(wireString(message, 'format')!);
  final objNormals = ObjNormals.byName(wireString(message, 'objNormals')!);
  final stlNormals = StlNormals.byName(wireString(message, 'stlNormals')!);
  if (format == null || objNormals == null || stlNormals == null) {
    _inPlace(job, 'the request names a format or an option it does not know');
    return;
  }
  final bytes = wireBytes(message, 'bytes')!;
  final source = _PageFile(wireString(message, 'key')!, bytes, job);
  final request = ModelLoadRequest(
    source: source,
    format: format,
    layout: readWireLayout(message['layout']! as JSArray<JSAny?>),
    objNormals: objNormals,
    stlNormals: stlNormals,
  );
  try {
    final document = await decodeModelBytes(request, bytes, source.resolveUri);
    final writer = F3dWriter(document);
    if (writer.warnings.isNotEmpty) {
      _inPlace(
        job,
        'its .f3d would not carry everything: ${writer.warnings.join('; ')}',
      );
      return;
    }
    final f3d = writer.write();
    _post(
      wireObject(<String, JSAny?>{
        'type': DecodeWorkerMessage.done.toJS,
        'job': job.toJS,
        'f3d': f3d.toJS,
      }),
      <JSAny?>[f3d.buffer.toJS].toJS,
    );
  } on Object catch (error) {
    // The page reads it again in place, so what it throws is the decoder's
    // own exception, typed, rather than a sentence from here.
    _inPlace(job, 'the worker could not read it ($error)');
  } finally {
    _reads.remove(job);
  }
}

void _panorama(int job, JSObject message) {
  final size = wireInt(message, 'size');
  final levels = wireInt(message, 'levels');
  try {
    final hdr = wireBytes(message, 'hdr');
    final faces = hdr != null
        ? hdrPanoramaFaces(hdr, size: size, levels: levels)
        : panoramaFaces(
            ByteData.sublistView(wireBytes(message, 'pixels')!),
            width: wireInt(message, 'width'),
            height: wireInt(message, 'height'),
            size: size,
            levels: levels,
          );
    if (faces == null) {
      _post(
        wireObject(<String, JSAny?>{
          'type': DecodeWorkerMessage.done.toJS,
          'job': job.toJS,
        }),
      );
      return;
    }
    _post(wirePanoramaDone(job, faces), wirePanoramaTransfer(faces));
  } on Object catch (error) {
    _inPlace(job, 'the worker could not convolve it ($error)');
  }
}

/// The file the page sent, whose siblings are asked for back.
final class _PageFile extends AssetSource {
  _PageFile(this.key, this._bytes, this._job);

  @override
  final String key;
  final Uint8List _bytes;
  final int _job;

  @override
  Future<Uint8List> read(AssetRead request) async => _bytes;

  @override
  AssetUriResolver get resolveUri => (AssetRequest request) {
    final read = _nextRead++;
    final waiting = Completer<Uint8List>();
    _reads.putIfAbsent(_job, () => <int, Completer<Uint8List>>{})[read] =
        waiting;
    _post(
      wireObject(<String, JSAny?>{
        'type': DecodeWorkerMessage.read.toJS,
        'job': _job.toJS,
        'read': read.toJS,
        'uri': request.uri.toJS,
      }),
    );
    return waiting.future;
  };
}
