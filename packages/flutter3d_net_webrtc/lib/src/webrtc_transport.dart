import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// A [PeerWire] over a real WebRTC data channel — [RollbackSession]'s frames
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
/// One side must call [openOffering] and the other [openAnswering] — a data
/// channel is opened by whichever side calls [openOffering], and
/// [RollbackSession] does not care which peer that is, only that exactly one of
/// them does.
final class WebRtcTransport extends PeerWire {
  WebRtcTransport._(this._peerConnection, this._signaling);

  final RTCPeerConnection _peerConnection;
  final PeerWire _signaling;
  RTCDataChannel? _dataChannel;
  final _readyCompleter = Completer<void>();

  /// Completes once the data channel has actually opened — [send] before
  /// this is a message [flutter_webrtc] itself will refuse, the same way
  /// writing to a socket before it connects would be.
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
      signaling.send(<String, Object?>{
        'kind': 'ice',
        'candidate': value,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
  }

  /// The offering side: opens the data channel, sends an SDP offer over
  /// [signaling], and finishes the handshake once an answer and the far
  /// side's ICE candidates arrive on it.
  static Future<WebRtcTransport> openOffering(PeerWire signaling) async {
    final connection = await _openConnection();
    final transport = WebRtcTransport._(connection, signaling);
    _wireSignalling(connection, signaling);

    final channel = await connection.createDataChannel(
      'net-01',
      RTCDataChannelInit()..ordered = false,
    );
    transport._bindDataChannel(channel);

    signaling.listen(transport._onSignallingMessage);

    final offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    signaling.send(<String, Object?>{'kind': 'offer', 'sdp': offer.sdp});

    return transport;
  }

  /// The answering side: waits for an offer on [signaling], accepts the
  /// data channel the offering side opened, and answers.
  static Future<WebRtcTransport> openAnswering(PeerWire signaling) async {
    final connection = await _openConnection();
    final transport = WebRtcTransport._(connection, signaling);
    _wireSignalling(connection, signaling);

    connection.onDataChannel = transport._bindDataChannel;
    signaling.listen(transport._onSignallingMessage);

    return transport;
  }

  void _bindDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    };
    channel.onMessage = (message) {
      if (message.isBinary) {
        deliverBytes(message.binary);
        return;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(message.text);
      } on FormatException {
        return;
      }
      if (decoded is Map<String, Object?>) deliver(decoded);
    };
  }

  Future<void> _onSignallingMessage(Map<String, Object?> message) async {
    switch (message['kind']) {
      case 'offer':
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(message['sdp']! as String, 'offer'),
        );
        final answer = await _peerConnection.createAnswer();
        await _peerConnection.setLocalDescription(answer);
        _signaling.send(<String, Object?>{'kind': 'answer', 'sdp': answer.sdp});
      case 'answer':
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(message['sdp']! as String, 'answer'),
        );
      case 'ice':
        await _peerConnection.addCandidate(
          RTCIceCandidate(
            message['candidate']! as String,
            message['sdpMid'] as String?,
            message['sdpMLineIndex'] as int?,
          ),
        );
    }
  }

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) {
    final channel = _dataChannel;
    if (channel == null) {
      throw StateError('send called before the data channel was created');
    }
    channel.send(RTCDataChannelMessage(jsonEncode(message)));
  }

  /// A binary message on the data channel, as it is: no base64, no JSON.
  /// The far side delivers it to its byte listeners whether it overrides
  /// this or not.
  @override
  void sendBytes(Uint8List bytes, {bool reliable = true}) {
    final channel = _dataChannel;
    if (channel == null) {
      throw StateError('sendBytes called before the data channel was created');
    }
    channel.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  /// Tears down the data channel and the peer connection. Safe to call more
  /// than once.
  @override
  Future<void> close() async {
    await _dataChannel?.close();
    await _peerConnection.close();
  }
}
