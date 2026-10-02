/// A running game's VM service, reached from a desktop and from a browser.
library;

import 'dart:async';

import 'package:vm_service/vm_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connects to a VM service. A parameter of what attaches to a game, so a
/// test hands it a service of its own making.
typedef ConnectVmService = Future<VmService> Function(String uri);

/// The WebSocket address of a VM service, from whatever a person pasted: the
/// `http://` address a game prints on startup, the `ws://…/ws` one
/// `flutter run --machine` reports, with or without a trailing slash.
String vmServiceWebSocket(String uri) {
  final trimmed = uri.trim();
  final withScheme = trimmed
      .replaceFirst(RegExp('^http://'), 'ws://')
      .replaceFirst(RegExp('^https://'), 'wss://');
  return withScheme.endsWith('/ws')
      ? withScheme
      : '${withScheme.replaceFirst(RegExp(r'/$'), '')}/ws';
}

/// Connects to the VM service at [uri], in any of [vmServiceWebSocket]'s
/// spellings.
///
/// **Not `vmServiceConnectUri`.** That one opens a `dart:io` `WebSocket`,
/// which a browser does not have, and the web editor reaches a game through
/// nothing else; `WebSocketChannel` is the browser's socket there and
/// `dart:io`'s on a desktop, so both editors connect through the same lines.
Future<VmService> connectVmService(String uri) async {
  final address = vmServiceWebSocket(uri);
  final channel = WebSocketChannel.connect(Uri.parse(address));
  await channel.ready;
  final closed = Completer<void>();
  final incoming = StreamController<Object?>();
  channel.stream.listen(
    incoming.add,
    onError: incoming.addError,
    onDone: () {
      if (!closed.isCompleted) closed.complete();
      unawaited(incoming.close());
    },
  );
  return VmService(
    incoming.stream,
    channel.sink.add,
    disposeHandler: channel.sink.close,
    streamClosed: closed.future,
    wsUri: address,
  );
}
