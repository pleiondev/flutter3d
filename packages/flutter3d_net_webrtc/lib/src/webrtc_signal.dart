/// The handshake's words and the two data channels: what both sides of a
/// `WebRtcTransport` have to agree on before a single frame moves.
///
/// Kept apart from the transport, and pure, so a test reads the wire without
/// a native WebRTC binding, which `flutter test` does not have.
library;

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// The value under [PeerWire.engineKey] that marks a signalling message.
const String signalTag = 'signal';

/// The signalling protocol this build speaks, under `"v"`.
///
/// **A protocol number, matched exactly, not a file's version read up to.**
/// Two peers that disagree on the handshake cannot finish it, so a signal of
/// any other number fails the transport's `ready` with a sentence naming
/// both rather than being read, as the hello refuses another major.
const int signalProtocol = 1;

/// The label of the channel a reliable message travels on: ordered, and
/// retransmitted until it arrives, as `PeerSend.reliable` promises.
const String reliableChannelLabel = 'f3d.reliable';

/// The label of the channel an unreliable message travels on: unordered,
/// never retransmitted. A rollback's frames repeat the last few steps, so a
/// lost one costs nothing and a late one would only hold the next back.
const String unreliableChannelLabel = 'f3d.unreliable';

/// The two channels by label, as the offering side opens them.
Map<String, RTCDataChannelInit> dataChannelInits() =>
    <String, RTCDataChannelInit>{
      reliableChannelLabel: RTCDataChannelInit()..ordered = true,
      unreliableChannelLabel: UnreliableChannelInit(),
    };

/// The unreliable channel's init: unordered, no retransmission.
///
/// **A subclass, because `flutter_webrtc` drops a zero.** Its `toMap`
/// writes `maxRetransmits` only when it is above zero, so the 0 that makes
/// a channel unreliable never reached the native side and the channel came
/// up reliable. This writes it. The browser implementation reads the field
/// with the same test and has no map to override, so in a browser the
/// channel is unordered but still retransmits — a late frame there costs
/// latency, never correctness.
final class UnreliableChannelInit extends RTCDataChannelInit {
  /// An init with `ordered` false and `maxRetransmits` nought.
  UnreliableChannelInit() {
    ordered = false;
    maxRetransmits = 0;
  }

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{
    ...super.toMap(),
    'maxRetransmits': maxRetransmits,
  };
}

/// One signalling message, read.
///
/// [kind] is `offer`, `answer` or `ice`; an offer and an answer carry [sdp],
/// an ICE candidate [candidate], [sdpMid] and [sdpMLineIndex].
final class Signal {
  /// The offering side's session description, [sdp].
  const Signal.offer(String this.sdp)
    : kind = offerKind,
      candidate = null,
      sdpMid = null,
      sdpMLineIndex = null;

  /// The answering side's session description, [sdp], in reply to an
  /// offer.
  const Signal.answer(String this.sdp)
    : kind = answerKind,
      candidate = null,
      sdpMid = null,
      sdpMLineIndex = null;

  /// One ICE [candidate], with the media section it belongs to when the
  /// side that gathered it said.
  const Signal.ice(String this.candidate, {this.sdpMid, this.sdpMLineIndex})
    : kind = iceKind,
      sdp = null;

  /// The [kind] of a [Signal.offer], as the wire spells it.
  static const String offerKind = 'offer';

  /// The [kind] of a [Signal.answer], as the wire spells it.
  static const String answerKind = 'answer';

  /// The [kind] of a [Signal.ice], as the wire spells it.
  static const String iceKind = 'ice';

  /// Which of the three it is: [offerKind], [answerKind] or [iceKind].
  final String kind;

  /// The session description of an offer or an answer; null for an ICE
  /// candidate.
  final String? sdp;

  /// The ICE candidate line; null for an offer or an answer.
  final String? candidate;

  /// The media stream id the candidate belongs to; null for an offer, an
  /// answer, or a candidate that did not say.
  final String? sdpMid;

  /// The index from nought of the media section the candidate belongs to;
  /// null for an offer, an answer, or a candidate that did not say.
  final int? sdpMLineIndex;

  /// The message on the wire: `{"f3d": "signal", "v": 1, "kind": …, …}`.
  Map<String, Object?> toJson() => <String, Object?>{
    PeerWire.engineKey: signalTag,
    'v': signalProtocol,
    'kind': kind,
    if (sdp case final String sdp) 'sdp': sdp,
    if (candidate case final String candidate) 'candidate': candidate,
    if (kind == iceKind) 'sdpMid': sdpMid,
    if (kind == iceKind) 'sdpMLineIndex': sdpMLineIndex,
  };
}

/// What [readSignal] made of a message.
sealed class SignalRead {
  const SignalRead();
}

/// Not a signal at all: a game's message, or another of the engine's
/// protocols sharing the signalling wire. Left alone.
final class NotASignal extends SignalRead {
  /// The answer for a message that is not a signal.
  const NotASignal();
}

/// A signal of this version, read.
final class SignalOf extends SignalRead {
  /// The answer carrying [signal].
  const SignalOf(this.signal);

  /// The signal the message held, every field it needs present.
  final Signal signal;
}

/// A signal this build cannot use: another version, an unknown kind, or a
/// field missing or of the wrong type. [reason] says which.
final class SignalRefused extends SignalRead {
  /// The refusal, with [otherVersion] set when the version is what is
  /// wrong.
  const SignalRefused(this.reason, {this.otherVersion = false});

  /// Why it cannot be used, as a sentence fragment naming the version, the
  /// kind or the field (`an offer without an sdp`).
  final String reason;

  /// Whether the far side speaks another signalling version, which no
  /// later message can repair: the handshake fails rather than waits.
  final bool otherVersion;
}

/// Reads [message] as a signal, never throwing: a message from a peer is
/// input, and a cast that throws inside a stream listener is an unhandled
/// error in whichever zone opened the transport.
SignalRead readSignal(Map<String, Object?> message) {
  if (message[PeerWire.engineKey] != signalTag) return const NotASignal();
  final version = message['v'];
  if (version != signalProtocol) {
    return SignalRefused(
      'the far side signals at version $version, and this build at '
      '$signalProtocol',
      otherVersion: true,
    );
  }
  final kind = message['kind'];
  switch (kind) {
    case Signal.offerKind || Signal.answerKind:
      final sdp = message['sdp'];
      if (sdp is! String) return SignalRefused('an $kind without an sdp');
      return SignalOf(
        kind == Signal.offerKind ? Signal.offer(sdp) : Signal.answer(sdp),
      );
    case Signal.iceKind:
      final candidate = message['candidate'];
      final mid = message['sdpMid'];
      final line = message['sdpMLineIndex'];
      if (candidate is! String || (mid != null && mid is! String)) {
        return const SignalRefused('an ice candidate without its fields');
      }
      if (line != null && line is! int) {
        return const SignalRefused('an ice candidate with a fractional line');
      }
      return SignalOf(
        Signal.ice(
          candidate,
          sdpMid: mid as String?,
          sdpMLineIndex: line as int?,
        ),
      );
    default:
      return SignalRefused('a signal of kind "$kind", which this build lacks');
  }
}
