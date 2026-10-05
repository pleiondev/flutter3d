import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

/// [request] decoded on an isolate of its own, its sibling files read here
/// and sent over a port.
Future<ModelDocument> decodeOnIsolate(
  ModelLoadRequest request,
  developer.TimelineTask task,
) async {
  task.instant('read');
  final primary = await request.source.read();
  final resolve = request.source.resolveUri;

  final requests = ReceivePort();
  final subscription = requests.listen((Object? message) async {
    final envelope = message! as List<Object?>;
    final uri = envelope[0]! as String;
    final reply = envelope[1]! as SendPort;
    try {
      reply.send(await resolve(AssetRequest(uri)));
    } catch (error) {
      // Errors cannot be thrown across a port, so they travel as a value and are
      // rethrown on the far side.
      reply.send(<Object?>['error', error.toString()]);
    }
  });

  final servicePort = requests.sendPort;
  try {
    task.instant('decode');
    return await Isolate.run(
      () => decodeModelBytes(request, primary, _portResolver(servicePort)),
    );
  } finally {
    await subscription.cancel();
    requests.close();
  }
}

/// A resolver that asks the spawning isolate to read a file.
AssetUriResolver _portResolver(SendPort servicePort) {
  return (request) async {
    // **The string, not the request.** What goes over the port is read by an
    // isolate that expects a path, and `send` takes `Object?` — so handing it
    // the whole object compiles, says nothing, and fails at the other end.
    final uri = request.uri;
    final reply = ReceivePort();
    try {
      servicePort.send(<Object?>[uri, reply.sendPort]);
      final response = await reply.first;
      if (response is Uint8List) return response;
      if (response is List && response.length == 2 && response[0] == 'error') {
        throw StateError('Could not read "$uri": ${response[1]}');
      }
      throw StateError('Unexpected reply reading "$uri": $response');
    } finally {
      reply.close();
    }
  };
}
