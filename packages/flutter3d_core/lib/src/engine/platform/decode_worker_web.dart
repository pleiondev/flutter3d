/// The page's side of the decode worker: starting it, sending it work, and
/// answering its reads. Browser only; see `WebDecodeWorker`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

import '../assets/web_decode_worker.dart';
import '../render/panorama_faces.dart';
import 'decode_worker_wire.dart';

/// How long a worker has to say it is ready before decodes run in place.
const Duration _readyWithin = Duration(seconds: 10);

/// [request], whose file the page read as [bytes], decoded by the worker;
/// null where it is to be decoded in place, with
/// `WebDecodeWorker.inPlaceReason` saying why.
Future<ModelDocument?> decodeModelOnWorker(
  ModelLoadRequest request,
  Uint8List bytes,
) async {
  if (request.decoders.isNotEmpty) {
    return _inPlace(
      'the request carries an application decoder, which runs in the '
      "page's program and not the worker's",
    );
  }
  if (wireFormat(request.format.name) != request.format) {
    return _inPlace('the worker does not know the format ${request.format}');
  }
  if (request.format == ModelFormat.f3d || isF3dFile(bytes)) {
    // Read as views over the bytes in no time; there is nothing to move.
    return _inPlace('an .f3d is read where it is, in no time');
  }
  final worker = await _worker();
  if (worker == null) return null;
  final reply = await worker.run(
    (int job) => wireModelJob(job, request, bytes),
    read: (String uri) => request.source.resolveUri(AssetRequest(uri)),
  );
  if (reply == null) return null;
  return F3dDocument.parse(wireBytes(reply, 'f3d')!);
}

/// A panorama's faces and chain worked out by the worker, from a Radiance
/// file [hdr] or from RGBA8 [pixels]: a record holding them, or null in it
/// where the worker found no panorama; null where it is to be done in place.
Future<(PanoramaFaces?,)?> panoramaOnWorker({
  Uint8List? hdr,
  ByteData? pixels,
  int width = 0,
  int height = 0,
  required int size,
  required int levels,
}) async {
  final worker = await _worker();
  if (worker == null) return null;
  final reply = await worker.run(
    (int job) => wireObject(<String, JSAny?>{
      'type': DecodeWorkerMessage.panorama.toJS,
      'job': job.toJS,
      'size': size.toJS,
      'levels': levels.toJS,
      if (hdr != null) 'hdr': hdr.toJS,
      if (pixels != null) ...<String, JSAny?>{
        'pixels': Uint8List.sublistView(pixels).toJS,
        'width': width.toJS,
        'height': height.toJS,
      },
    }),
  );
  if (reply == null) return null;
  return (readWirePanorama(reply),);
}

Null _inPlace(String reason) {
  webDecodeWorkerState.inPlaceReason = reason;
  return null;
}

_Worker? _running;

/// The worker for the script `WebDecodeWorker.use` named, started on the
/// first decode and ready; null, with the reason said, where there is none.
Future<_Worker?> _worker() async {
  final state = webDecodeWorkerState;
  final script = state.script;
  var worker = _running;
  if (worker != null && worker.generation != state.generation) {
    worker.terminate();
    worker = _running = null;
  }
  if (script == null) {
    return _inPlace(
      'no decode worker: WebDecodeWorker.use was not given a script',
    );
  }
  worker ??= _running = _Worker.start(script, state.generation);
  final refusal = await worker.ready;
  if (refusal != null) return _inPlace(refusal);
  return worker;
}

/// One running worker and the jobs out on it.
final class _Worker {
  _Worker._(this.generation, this._worker, this.ready);

  /// Starts the script at [script], or a worker already refused where the
  /// browser will not.
  factory _Worker.start(Uri script, int generation) {
    final readiness = Completer<String?>();
    final constructor = globalContext['Worker'];
    if (constructor == null || !constructor.isA<JSFunction>()) {
      readiness.complete('this browser has no Web Worker');
      return _Worker._(generation, null, readiness.future);
    }
    final JSObject worker;
    try {
      worker = (constructor as JSFunction).callAsConstructor<JSObject>(
        script.toString().toJS,
      );
    } on Object catch (error) {
      // A content security policy without `worker-src` for it, or a page
      // the browser will not start a worker from.
      readiness.complete('the browser would not start $script ($error)');
      return _Worker._(generation, null, readiness.future);
    }
    final started = _Worker._(generation, worker, readiness.future);
    started._readiness = readiness;
    worker
      ..callMethod<JSAny?>(
        'addEventListener'.toJS,
        'message'.toJS,
        ((JSObject event) {
          started._receive(event['data']! as JSObject);
        }).toJS,
      )
      ..callMethod<JSAny?>(
        'addEventListener'.toJS,
        'error'.toJS,
        ((JSObject event) {
          final message = wireString(event, 'message');
          started._fail(
            'the decode worker at $script failed'
            '${message == null ? '' : ' ($message)'}',
          );
        }).toJS,
      );
    started._readyTimer = Timer(_readyWithin, () {
      started._fail('the decode worker at $script did not start in time');
    });
    return started;
  }

  final int generation;
  final JSObject? _worker;

  /// Null once the worker said it is ready; the reason where it will not be.
  final Future<String?> ready;
  Completer<String?>? _readiness;
  Timer? _readyTimer;
  bool _wasReady = false;

  final Map<int, _Job> _jobs = <int, _Job>{};
  int _nextJob = 0;

  /// Sends the message [make] builds for a new job, answering the worker's
  /// sibling reads with [read]; the worker's `done` reply, or null where it
  /// sent the job back to be done in place.
  Future<JSObject?> run(
    JSObject Function(int job) make, {
    Future<Uint8List> Function(String uri)? read,
  }) {
    final job = _nextJob++;
    final pending = _Job(read);
    _jobs[job] = pending;
    _worker!.callMethod<JSAny?>('postMessage'.toJS, make(job));
    return pending.reply.future;
  }

  void _receive(JSObject message) {
    switch (wireType(message)) {
      case DecodeWorkerMessage.ready:
        _readyTimer?.cancel();
        _wasReady = true;
        final protocol = wireInt(message, 'protocol');
        _readiness?.complete(
          protocol == decodeWorkerProtocol
              ? null
              : 'the decode worker speaks protocol $protocol and this page '
                    '$decodeWorkerProtocol; compile it again from this release',
        );
        _readiness = null;
      case DecodeWorkerMessage.read:
        unawaited(_read(message));
      case DecodeWorkerMessage.done:
        final pending = _jobs.remove(wireInt(message, 'job'));
        if (pending == null) return;
        webDecodeWorkerState
          ..decoded += 1
          ..inPlaceReason = null;
        pending.reply.complete(message);
      case DecodeWorkerMessage.inPlace:
        _jobs
            .remove(wireInt(message, 'job'))
            ?.reply
            .complete(_inPlace(wireString(message, 'reason')!));
      case _:
        break;
    }
  }

  Future<void> _read(JSObject message) async {
    final job = wireInt(message, 'job');
    final read = _jobs[job]?.read;
    JSObject answer(Map<String, JSAny?> fields) => wireObject(<String, JSAny?>{
      'type': DecodeWorkerMessage.read.toJS,
      'job': job.toJS,
      'read': message['read'],
      ...fields,
    });
    final uri = wireString(message, 'uri')!;
    try {
      if (read == null) throw StateError('nothing reads files for this job');
      final bytes = await read(uri);
      _worker?.callMethod<JSAny?>(
        'postMessage'.toJS,
        answer(<String, JSAny?>{'bytes': bytes.toJS}),
      );
    } on Object catch (error) {
      _worker?.callMethod<JSAny?>(
        'postMessage'.toJS,
        answer(<String, JSAny?>{'error': 'Could not read "$uri": $error'.toJS}),
      );
    }
  }

  /// The worker is gone: every job out on it is done in place, and the next
  /// decode starts another.
  void _fail(String reason) {
    _readyTimer?.cancel();
    _readiness?.complete(reason);
    _readiness = null;
    for (final pending in _jobs.values) {
      pending.reply.complete(_inPlace(reason));
    }
    _jobs.clear();
    terminate();
    // One that never started stays, so every decode until the next
    // `WebDecodeWorker.use` hears the same reason rather than asking the
    // browser for the same script again; one that started and then failed
    // makes way for another.
    if (_wasReady && identical(_running, this)) _running = null;
  }

  void terminate() => _worker?.callMethod<JSAny?>('terminate'.toJS);
}

final class _Job {
  _Job(this.read);

  final Future<Uint8List> Function(String uri)? read;
  final Completer<JSObject?> reply = Completer<JSObject?>();
}
