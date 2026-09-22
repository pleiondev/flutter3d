import 'dart:async';
import 'dart:convert';

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// A [NetTransport] over a real WebRTC data channel — [NetSession]'s frames
/// travel peer to peer once this finishes connecting, and [signalling]
/// carries only the handful of messages that set that up.
///
/// **[signalling] is any [NetTransport], most often a [WebSocketTransport]
/// pointed at `net-02`'s relay.** That is the whole of the relay's role
/// once a [WebRtcTransport] is in use: an offer, an answer, and each side's
/// ICE candidates as they are found — after [ready] completes, nothing
/// this class sends or receives touches [signalling] again, which is the
/// difference net-02's own doc draws between this transport and
/// [WebSocketTransport]'s fallback, where the relay carries every frame for
/// as long as the room stays open.
///
/// One side must call [createOffer] and the other [awaitOffer] — a data
/// channel is opened by whichever side calls [createOffer], and
/// [NetSession] does not care which peer that is, only that exactly one of
/// them does.
final class WebRtcTransport implements NetTransport {
  WebRtcTransport._(this._peerConnection, this._signalling);

  final RTCPeerConnection _peerConnection;
  final NetTransport _signalling;
  RTCDataChannel? _dataChannel;
  void Function(Map<String, Object?> message)? _listener;
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
    NetTransport signalling,
  ) {
    connection.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null) return;
      signalling.send(<String, Object?>{
        'kind': 'ice',
        'candidate': value,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
  }

  /// The offering side: opens the data channel, sends an SDP offer over
  /// [signalling], and finishes the handshake once an answer and the far
  /// side's ICE candidates arrive on it.
  static Future<WebRtcTransport> createOffer(NetTransport signalling) async {
    final connection = await _openConnection();
    final transport = WebRtcTransport._(connection, signalling);
    _wireSignalling(connection, signalling);

    final channel = await connection.createDataChannel(
      'net-01',
      RTCDataChannelInit()..ordered = false,
    );
    transport._bindDataChannel(channel);

    signalling.listen(transport._onSignallingMessage);

    final offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    signalling.send(<String, Object?>{'kind': 'offer', 'sdp': offer.sdp});

    return transport;
  }

  /// The answering side: waits for an offer on [signalling], accepts the
  /// data channel the offering side opened, and answers.
  static Future<WebRtcTransport> awaitOffer(NetTransport signalling) async {
    final connection = await _openConnection();
    final transport = WebRtcTransport._(connection, signalling);
    _wireSignalling(connection, signalling);

    connection.onDataChannel = transport._bindDataChannel;
    signalling.listen(transport._onSignallingMessage);

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
      if (message.isBinary) return;
      final decoded = jsonDecode(message.text);
      if (decoded is Map<String, Object?>) _listener?.call(decoded);
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
        _signalling.send(<String, Object?>{
          'kind': 'answer',
          'sdp': answer.sdp,
        });
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
  void send(Map<String, Object?> message) {
    final channel = _dataChannel;
    if (channel == null) {
      throw StateError('send called before the data channel was created');
    }
    channel.send(RTCDataChannelMessage(jsonEncode(message)));
  }

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      _listener = onMessage;

  /// Tears down the data channel and the peer connection. Safe to call more
  /// than once.
  Future<void> close() async {
    await _dataChannel?.close();
    await _peerConnection.close();
  }
}
