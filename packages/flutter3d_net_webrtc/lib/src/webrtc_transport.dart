import 'dart:async';
import 'dart:convert';

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'webrtc_signal.dart';

/// A [PeerWire] over real WebRTC data channels — [RollbackSession]'s frames
/// travel peer to peer once this finishes connecting, and [signaling]
/// carries only the handful of messages that set that up.
///
/// **[signaling] is any [PeerWire], most often a [WebSocketTransport]
/// pointed at `net-02`'s relay.** That is the whole of the relay's role
/// once a [WebRtcTransport] is in use: an offer, an answer, and each side's
/// ICE candidates as they are found — after [ready] completes, nothing
/// this class sends or receives touches [signaling] again, which is the
/// difference net-02's own doc draws between this transport and
/// [WebSocketTransport]'s fallback, where the relay carries every frame for
/// as long as the room stays open.
///
/// One side must call [openOffering] and the other [openAnswering] — the
/// data channels are opened by whichever side calls [openOffering], and
/// [RollbackSession] does not care which peer that is, only that exactly one of
/// them does.
///
/// **Two data channels, one per kind of delivery.** A [PeerSend] that is
/// reliable goes on an ordered channel that retransmits until it arrives
/// (`f3d.reliable`), so it arrives once and in order with the other reliable
/// ones, as [PeerWire] promises; an unreliable one goes on an unordered
/// channel that never retransmits (`f3d.unreliable`), so a lost rollback
/// frame does not hold back the ones after it. [ready] completes when both
/// are open.
///
/// **The handshake is versioned.** Each signalling message is
/// `{"f3d": "signal", "v": 1, "kind": "offer" | "answer" | "ice", …}`. A
/// signal of another version fails [ready] with a `StateError` naming both
/// versions, since two sides cannot finish a handshake they disagree on; a
/// malformed one is dropped; and a message without the tag is not this
/// transport's and is left to the wire's other listeners.
final class WebRtcTransport extends PeerWire {
  WebRtcTransport._(this._peerConnection, this._signaling);

  final RTCPeerConnection _peerConnection;
  final PeerWire _signaling;

  /// The channels by label: [reliableChannelLabel] and
  /// [unreliableChannelLabel].
  final Map<String, RTCDataChannel> _channels = <String, RTCDataChannel>{};
  final Set<String> _open = <String>{};
  final _readyCompleter = Completer<void>();

  /// Completes once both data channels have actually opened — [send] before
  /// this is a message [flutter_webrtc] itself will refuse, the same way
  /// writing to a socket before it connects would be. Fails with a
  /// `StateError` when the far side signals at another version.
  Future<void> get ready => _readyCompleter.future;

  static Future<RTCPeerConnection> _openConnection() =>
      createPeerConnection(<String, Object?>{
        'iceServers': <Map<String, Object?>>[
          // A public STUN server is enough to discover this side's own
          // reflexive address; a NAT neither side's candidates get through
          // needs a TURN relay instead — net-02's own doc names that as the
          // relay's other job, not this class's.
          <String, Object?>{'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

  static void _wireSignalling(
    RTCPeerConnection connection,
    PeerWire signaling,
  ) {
    connection.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null) return;
      signaling.send(
        PeerSend(
          message: Signal.ice(
            value,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
          ).toJson(),
        ),
      );
    };
  }

  /// The offering side: opens both data channels, sends an SDP offer over
  /// [signaling], and finishes the handshake once an answer and the far
  /// side's ICE candidates arrive on it.
  static Future<WebRtcTransport> openOffering(PeerWire signaling) async {
    final connection = await _openConnection();
    final transport = WebRtcTransport._(connection, signaling);
    _wireSignalling(connection, signaling);

    for (final MapEntry(key: label, value: init)
        in dataChannelInits().entries) {
      transport._bindDataChannel(
        await connection.createDataChannel(label, init),
      );
    }

    signaling.listen(transport._onSignallingMessage);

    final offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    signaling.send(PeerSend(message: Signal.offer(offer.sdp ?? '').toJson()));

    return transport;
  }

  /// The answering side: waits for an offer on [signaling], accepts the
  /// data channels the offering side opened, and answers.
  static Future<WebRtcTransport> openAnswering(PeerWire signaling) async {
    final connection = await _openConnection();
    final transport = WebRtcTransport._(connection, signaling);
    _wireSignalling(connection, signaling);

    connection.onDataChannel = transport._bindDataChannel;
    signaling.listen(transport._onSignallingMessage);

    return transport;
  }

  void _bindDataChannel(RTCDataChannel channel) {
    final label = channel.label;
    // A channel of another label is not one this transport opened: a later
    // build's third channel is left alone rather than taken for one of these.
    if (label == null || !dataChannelInits().containsKey(label)) return;
    _channels[label] = channel;
    channel.onDataChannelState = (state) {
      if (state != RTCDataChannelState.RTCDataChannelOpen) return;
      _open.add(label);
      if (_open.length == dataChannelInits().length &&
          !_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    };
    channel.onMessage = (message) {
      if (message.isBinary) {
        deliverBytes(PeerBytesDelivery(bytes: message.binary));
        return;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(message.text);
      } on FormatException {
        return;
      }
      if (decoded is Map<String, Object?>) {
        deliver(PeerDelivery(message: decoded));
      }
    };
  }

  Future<void> _onSignallingMessage(Map<String, Object?> message) async {
    final signal = switch (readSignal(message)) {
      NotASignal() => null,
      SignalRefused(:final reason, otherVersion: true) => _refuse(reason),
      SignalRefused() => null,
      SignalOf(:final signal) => signal,
    };
    if (signal == null) return;
    switch (signal.kind) {
      case Signal.offerKind:
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(signal.sdp, 'offer'),
        );
        final answer = await _peerConnection.createAnswer();
        await _peerConnection.setLocalDescription(answer);
        _signaling.send(
          PeerSend(message: Signal.answer(answer.sdp ?? '').toJson()),
        );
      case Signal.answerKind:
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(signal.sdp, 'answer'),
        );
      case Signal.iceKind:
        await _peerConnection.addCandidate(
          RTCIceCandidate(
            signal.candidate,
            signal.sdpMid,
            signal.sdpMLineIndex,
          ),
        );
    }
  }

  /// Fails [ready] for a handshake that cannot finish, and reads nothing.
  Signal? _refuse(String reason) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(StateError('WebRTC signalling: $reason.'));
    }
    return null;
  }

  RTCDataChannel _channelFor({required bool reliable, required String call}) {
    final channel =
        _channels[reliable ? reliableChannelLabel : unreliableChannelLabel];
    if (channel == null) {
      throw StateError('$call called before the data channels were created');
    }
    return channel;
  }

  /// [PeerSend.message] on the reliable channel or the unreliable one, as
  /// [PeerSend.reliable] asks.
  @override
  void send(PeerSend context) {
    _channelFor(
      reliable: context.reliable,
      call: 'send',
    ).send(RTCDataChannelMessage(jsonEncode(context.message)));
  }

  /// A binary message on the channel [PeerSendBytes.reliable] asks for, as
  /// it is: no base64, no JSON. The far side delivers it to its byte
  /// listeners whether it overrides this or not.
  @override
  void sendBytes(PeerSendBytes context) {
    _channelFor(
      reliable: context.reliable,
      call: 'sendBytes',
    ).send(RTCDataChannelMessage.fromBinary(context.bytes));
  }

  /// Tears down both data channels and the peer connection. Safe to call
  /// more than once.
  @override
  Future<void> close() async {
    for (final channel in _channels.values) {
      await channel.close();
    }
    await _peerConnection.close();
  }
}
