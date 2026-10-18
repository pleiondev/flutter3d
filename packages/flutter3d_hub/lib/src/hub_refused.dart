import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

import 'hub_reference.dart';

/// Why the hub, or the client on its behalf, would not hand over a model —
/// [HubRefusedException.reason].
///
/// **An open set**: a later minor of the protocol may name a reason this
/// version does not, so a `switch` over it ends with a wildcard. [name] is
/// the wire name a server answers with, and [byName] reads one back.
final class HubRefusal {
  const HubRefusal._(this.name);

  /// No model has this UUID, or the model has no such version.
  static const HubRefusal notFound = HubRefusal._('notFound');

  /// The version exists and its author or the hub took it out of
  /// circulation. Versions are immutable and never deleted, so a withdrawn
  /// one is still named, and a client can say which it was.
  static const HubRefusal withdrawn = HubRefusal._('withdrawn');

  /// The bytes do not match the reference's `sha256`, or the hash the server
  /// announced for them: a tampered file, a broken mirror or a cache gone
  /// bad. Never loaded.
  static const HubRefusal hashMismatch = HubRefusal._('hashMismatch');

  /// The hub could not be reached and no cached copy would do: no network,
  /// a cache policy that forbids it, or a build with no client in it.
  static const HubRefusal offline = HubRefusal._('offline');

  /// The file is larger than the cache policy's `maxBytes`.
  static const HubRefusal tooLarge = HubRefusal._('tooLarge');

  /// The server speaks another major of the protocol, or answered with
  /// something the protocol does not allow.
  static const HubRefusal protocol = HubRefusal._('protocol');

  /// Every reason this version names.
  static const List<HubRefusal> values = <HubRefusal>[
    notFound,
    withdrawn,
    hashMismatch,
    offline,
    tooLarge,
    protocol,
  ];

  /// The reason called [name], or null when this version names none.
  static HubRefusal? byName(String name) {
    for (final reason in values) {
      if (reason.name == name) return reason;
    }
    return null;
  }

  /// The reason's wire name, as a server answers with it and a log spells it.
  final String name;

  @override
  String toString() => 'HubRefusal.$name';
}

/// The hub would not hand over a model, or a client refused what it handed
/// over.
///
/// A [ResourceException]: the model is something outside the program that
/// the engine needed and did not get.
final class HubRefusedException extends ResourceException {
  /// A refusal for [reason], with [detail] saying what happened in a
  /// sentence; [reference] is the model asked for, where there was one.
  const HubRefusedException(
    this.reason, {
    this.reference,
    this.detail = '',
    this.cause,
  });

  /// Why, as a reason a caller can act on.
  final HubRefusal reason;

  /// The model asked for; null for a refusal that names none, such as a
  /// server that speaks another major of the protocol.
  final HubReference? reference;

  /// What happened, as a sentence; empty when there is nothing to add to
  /// the reason.
  final String detail;

  @override
  final Object? cause;

  @override
  String get message {
    final what = reference == null ? 'The hub' : 'The hub model $reference';
    final why = switch (reason) {
      HubRefusal.notFound => 'was not found',
      HubRefusal.withdrawn => 'was withdrawn',
      HubRefusal.hashMismatch => 'does not match its checksum',
      HubRefusal.offline => 'could not be reached',
      HubRefusal.tooLarge => 'is larger than the cache policy allows',
      HubRefusal.protocol => 'did not answer in a protocol this client speaks',
      // A reason a later minor names: its wire name is what can be said.
      _ => 'was refused (${reason.name})',
    };
    return '$what $why${detail.isEmpty ? '.' : ': $detail'}';
  }

  @override
  String toString() => cause == null
      ? 'HubRefusedException: $message'
      : 'HubRefusedException: $message (caused by $cause)';
}
