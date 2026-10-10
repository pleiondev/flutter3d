/// General buffers and query sets: `createBuffer`, `writeBuffer`, the three
/// ways a buffer is read back, and occlusion and timer queries.
///
/// **WebGL2 types a buffer at its first binding** — see [WebGlBuffer] — and
/// that rule decides more here than anything else: a buffer made for indices
/// is bound first to `ELEMENT_ARRAY_BUFFER`, everything else first to the
/// target its usage names, and every later binding in this file goes through
/// `COPY_READ_BUFFER` or `COPY_WRITE_BUFFER`, the two targets either kind may
/// be bound to.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_types.dart';

/// A buffer for [descriptor]'s usages holding [contents]. The usages WebGL2
/// cannot give a buffer at all were refused by the caller; what is refused
/// here is a combination this one buffer cannot hold.
StorageBuffer webglCreateBuffer(
  web.WebGL2RenderingContext gl,
  List<web.WebGLBuffer> persistentBuffers,
  Map<web.WebGLBuffer, int> bufferTargets,
  BufferDescriptor descriptor, {
  ByteData? contents,
}) {
  final usage = descriptor.usage;
  final length = descriptor.lengthInBytes;
  final elementArray = usage.contains(BufferUsage.index);
  if (elementArray &&
      (usage.contains(BufferUsage.vertex) ||
          usage.contains(BufferUsage.uniform))) {
    // One buffer for both is ordinary in WebGPU and impossible here: the
    // first binding types it for life (see [WebGlBuffer]), and the second
    // kind of binding would be an INVALID_OPERATION at every draw.
    throw UnsupportedError(
      'WebGL2 cannot make one buffer both index data and $usage: a buffer '
      'holds indices or other data for life there. Make two buffers.',
    );
  }
  if (contents != null && contents.lengthInBytes > length) {
    throw ArgumentError(
      'createBuffer: ${contents.lengthInBytes} bytes of contents do not fit '
      'a $length-byte buffer',
    );
  }
  final target = elementArray
      ? web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER
      : usage.contains(BufferUsage.vertex)
      ? web.WebGLRenderingContext.ARRAY_BUFFER
      : usage.contains(BufferUsage.uniform)
      ? web.WebGL2RenderingContext.UNIFORM_BUFFER
      : web.WebGL2RenderingContext.COPY_WRITE_BUFFER;
  final buffer = gl.createBuffer()!;
  persistentBuffers.add(buffer);
  bufferTargets[buffer] = target;
  gl
    ..bindBuffer(target, buffer)
    ..bufferData(
      target,
      length.toJS,
      usage.contains(BufferUsage.hostReadable)
          ? web.WebGL2RenderingContext.DYNAMIC_READ
          : web.WebGLRenderingContext.DYNAMIC_DRAW,
    );
  if (contents != null && contents.lengthInBytes > 0) {
    gl.bufferSubData(target, 0, _bytesOf(contents).toJS);
  }
  gl.bindBuffer(target, null);

  GeometryBuffer? view(BufferUsage as) => usage.contains(as)
      ? wrapGeometry(backend: buffer, offsetInBytes: 0, lengthInBytes: length)
      : null;
  return wrapStorageBuffer(
    backend: WebGlBuffer(buffer, elementArray: elementArray),
    lengthInBytes: length,
    hostReadable: usage.contains(BufferUsage.hostReadable),
    asIndices: view(BufferUsage.index),
    asVertices: view(BufferUsage.vertex),
    usage: usage,
  );
}

/// [buffer]'s own [WebGlBuffer], or an [ArgumentError] for a buffer this
/// backend did not make.
WebGlBuffer webglBufferOf(StorageBuffer buffer) {
  final backend = buffer.backend;
  if (backend is WebGlBuffer) return backend;
  throw ArgumentError.value(
    buffer,
    'buffer',
    'was not made by a WebGL2 device',
  );
}

/// A [RangeError] unless [offset] and [size] lie inside [buffer]; the size
/// they come to otherwise, [size] defaulting to the rest of the buffer.
int webglCheckRange(StorageBuffer buffer, int offset, int? size) {
  final length = size ?? buffer.lengthInBytes - offset;
  if (offset < 0 || length < 0 || offset + length > buffer.lengthInBytes) {
    throw RangeError(
      '$length bytes from $offset do not lie inside a '
      '${buffer.lengthInBytes}-byte buffer',
    );
  }
  return length;
}

/// A [StateError] for a buffer a mapping still holds — the contract keeps a
/// mapped buffer out of every pass, and this backend says so at the call.
void webglRefuseMapped(WebGlBuffer buffer, String what) {
  if (!buffer.mapped) return;
  throw StateError('$what: the buffer is mapped; unmap it first');
}

/// `bufferSubData` into [target] at [offset], through `COPY_WRITE_BUFFER`.
void webglWriteBuffer(
  web.WebGL2RenderingContext gl,
  StorageBuffer target,
  int offset,
  ByteData bytes,
) {
  final buffer = webglBufferOf(target);
  webglRefuseMapped(buffer, 'writeBuffer');
  if (offset < 0 || offset + bytes.lengthInBytes > target.lengthInBytes) {
    throw ArgumentError(
      'writeBuffer: $offset + ${bytes.lengthInBytes} does not fit inside a '
      '${target.lengthInBytes}-byte buffer',
    );
  }
  gl
    ..bindBuffer(web.WebGL2RenderingContext.COPY_WRITE_BUFFER, buffer.buffer)
    ..bufferSubData(
      web.WebGL2RenderingContext.COPY_WRITE_BUFFER,
      offset,
      _bytesOf(bytes).toJS,
    )
    ..bindBuffer(web.WebGL2RenderingContext.COPY_WRITE_BUFFER, null);
}

/// `getBufferSubData`, which stalls until every command before it is done —
/// `GraphicsDevice.readBufferSync`, and the second half of every other read.
ByteData webglReadBufferNow(
  web.WebGL2RenderingContext gl,
  StorageBuffer source, {
  int offsetInBytes = 0,
  int? sizeInBytes,
}) {
  final buffer = webglBufferOf(source);
  if (!source.hostReadable) {
    throw ArgumentError.value(source, 'buffer', 'is not hostReadable');
  }
  final size = webglCheckRange(source, offsetInBytes, sizeInBytes);
  // Filled on the JS side and copied back, as `WebGlDevice.readback` does:
  // under dart2wasm `toJS` is a copy, and a Dart list handed across comes
  // back as the zeros it was made with.
  final js = Uint8List(size).toJS;
  gl
    ..bindBuffer(web.WebGL2RenderingContext.COPY_READ_BUFFER, buffer.buffer)
    ..getBufferSubData(
      web.WebGL2RenderingContext.COPY_READ_BUFFER,
      offsetInBytes,
      js,
    )
    ..bindBuffer(web.WebGL2RenderingContext.COPY_READ_BUFFER, null);
  return ByteData.sublistView(Uint8List.fromList(js.toDart));
}

/// Waits, without blocking the thread, until the GPU has finished every
/// command issued before this call.
///
/// A fence, flushed so it is sent rather than left until the browser next
/// composites, and polled on a timer — `clientWaitSync` with a timeout would
/// block the one thread this engine runs on. Bounded, because a fence on a
/// lost context never signals.
Future<void> webglFinishedSoFar(web.WebGL2RenderingContext gl) async {
  final sync = gl.fenceSync(
    web.WebGL2RenderingContext.SYNC_GPU_COMMANDS_COMPLETE,
    0,
  );
  if (sync == null) throw StateError('the context refused a fence');
  gl.flush();
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (true) {
      final status = gl.clientWaitSync(sync, 0, 0);
      if (status == web.WebGL2RenderingContext.ALREADY_SIGNALED ||
          status == web.WebGL2RenderingContext.CONDITION_SATISFIED) {
        return;
      }
      if (status == web.WebGL2RenderingContext.WAIT_FAILED) {
        throw StateError('the fence failed');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('the fence did not signal in two seconds');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  } finally {
    gl.deleteSync(sync);
  }
}

/// A mapping of a buffer range: a copy of its bytes, since WebGL2 maps
/// nothing into host memory, written back by [unmap] for [MapMode.write].
final class WebGlMapping extends MappedBuffer {
  WebGlMapping(
    this._gl,
    this._buffer,
    this.bytes, {
    required this.offsetInBytes,
    required this.mode,
  });

  final web.WebGL2RenderingContext _gl;
  final WebGlBuffer _buffer;
  final int offsetInBytes;
  final MapMode mode;

  @override
  final ByteData bytes;

  @override
  void unmap() {
    if (!_buffer.mapped) throw StateError('this mapping was already unmapped');
    _buffer.mapped = false;
    if (mode != MapMode.write) return;
    _gl
      ..bindBuffer(web.WebGL2RenderingContext.COPY_WRITE_BUFFER, _buffer.buffer)
      ..bufferSubData(
        web.WebGL2RenderingContext.COPY_WRITE_BUFFER,
        offsetInBytes,
        _bytesOf(bytes).toJS,
      )
      ..bindBuffer(web.WebGL2RenderingContext.COPY_WRITE_BUFFER, null);
  }
}

/// [bytes] as the `Uint8List` view the GL calls take.
Uint8List _bytesOf(ByteData bytes) =>
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);

// ---------------------------------------------------------------- queries

/// `EXT_disjoint_timer_query_webgl2`'s `TIMESTAMP_EXT`.
const int webglTimestampTarget =
    web.EXT_disjoint_timer_query_webgl2.TIMESTAMP_EXT;

/// Its `GPU_DISJOINT_EXT`: true when something — a power state change, a
/// context switch — made every timer result since the last read
/// meaningless.
const int webglGpuDisjoint =
    web.EXT_disjoint_timer_query_webgl2.GPU_DISJOINT_EXT;

/// A query set of [count] GL query objects.
QuerySet webglCreateQuerySet(
  web.WebGL2RenderingContext gl,
  QueryType type,
  int count,
) {
  if (count < 1) {
    throw ArgumentError.value(count, 'count', 'a query set holds at least one');
  }
  return wrapQuerySet(
    backend: WebGlQuerySet(<web.WebGLQuery?>[
      for (var i = 0; i < count; i++) gl.createQuery(),
    ]),
    type: type,
    count: count,
  );
}

/// [querySet]'s own [WebGlQuerySet], or an [ArgumentError].
WebGlQuerySet webglQueriesOf(QuerySet querySet) {
  final backend = querySet.backend;
  if (backend is WebGlQuerySet) return backend;
  throw ArgumentError.value(
    querySet,
    'querySet',
    'was not made by a WebGL2 device',
  );
}

/// The results of [count] queries from [first]: zero or one for an
/// occlusion query — `ANY_SAMPLES_PASSED` answers whether anything passed,
/// which is all the contract promises of a non-zero count — and
/// nanoseconds for a timestamp.
///
/// **Polled across turns, and it has to be.** WebGL2 makes a query's result
/// available no earlier than the next time the page returns to the event
/// loop, whatever the GPU has done, so a loop in one turn would wait
/// forever.
Future<List<int>> webglReadQueryResults(
  web.WebGL2RenderingContext gl,
  QuerySet querySet, {
  int first = 0,
  int? count,
}) async {
  final queries = webglQueriesOf(querySet);
  final n = count ?? querySet.count - first;
  if (first < 0 || n < 0 || first + n > querySet.count) {
    throw RangeError(
      '$n queries from $first do not lie inside a set of ${querySet.count}',
    );
  }
  gl.flush();
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  final results = <int>[];
  for (var i = first; i < first + n; i++) {
    final query = queries.queries[i];
    if (!queries.written.contains(i) || query == null) {
      results.add(0);
      continue;
    }
    while (!_truthy(
      gl.getQueryParameter(
        query,
        web.WebGL2RenderingContext.QUERY_RESULT_AVAILABLE,
      ),
    )) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('query $i of $querySet was not answered in time');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    results.add(
      _integer(
        gl.getQueryParameter(query, web.WebGL2RenderingContext.QUERY_RESULT),
      ),
    );
  }
  if (querySet.type == QueryType.timestamp &&
      _truthy(gl.getParameter(webglGpuDisjoint))) {
    throw StateError(
      'the GPU timer was disjoint while these timestamps were taken — a '
      'power or context change made them meaningless. Take them again.',
    );
  }
  return results;
}

/// Deletes [querySet]'s GL objects.
void webglReleaseQuerySet(web.WebGL2RenderingContext gl, QuerySet querySet) {
  final queries = webglQueriesOf(querySet);
  for (final query in queries.queries) {
    gl.deleteQuery(query);
  }
  queries.queries.fillRange(0, queries.queries.length, null);
  queries.written.clear();
}

bool _truthy(JSAny? value) {
  if (value == null) return false;
  if (value.isA<JSBoolean>()) return (value as JSBoolean).toDart;
  if (value.isA<JSNumber>()) return (value as JSNumber).toDartDouble != 0;
  return false;
}

int _integer(JSAny? value) {
  if (value == null) return 0;
  if (value.isA<JSBoolean>()) return (value as JSBoolean).toDart ? 1 : 0;
  if (value.isA<JSNumber>()) return (value as JSNumber).toDartDouble.round();
  return 0;
}
