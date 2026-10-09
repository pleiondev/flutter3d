/// Whether a player has said their runs may leave the machine.
library;

/// A player's answer to "may we send what you did in a level, to see where
/// levels are hard?", kept with when they gave it and to which wording.
///
/// **Not asked is not yes.** A game that never showed the question sends
/// nothing, and so does one whose question changed since the player answered:
/// [allows] wants a grant to the [policy] the game asks under now. A grant to
/// last year's wording is consent to last year's wording.
///
/// A game keeps this in its own settings document beside volumes and
/// bindings; [toJson] is the part of that document it owns.
final class TelemetryConsent {
  const TelemetryConsent.notAsked() : _yes = null, policy = null, at = null;

  TelemetryConsent.granted({required String this.policy, required this.at})
    : _yes = true;

  TelemetryConsent.declined({required String this.policy, required this.at})
    : _yes = false;

  /// Reads what [toJson] wrote. Anything it cannot read is not asked, never a
  /// grant: a settings file damaged in the one field that says yes must not
  /// say yes.
  factory TelemetryConsent.fromJson(Object? json) {
    if (json is! Map) return const TelemetryConsent.notAsked();
    final answer = json['answer'];
    final policy = json['policy'];
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (policy is! String || policy.isEmpty || at == null) {
      return const TelemetryConsent.notAsked();
    }
    return switch (answer) {
      'granted' => TelemetryConsent.granted(policy: policy, at: at),
      'declined' => TelemetryConsent.declined(policy: policy, at: at),
      _ => const TelemetryConsent.notAsked(),
    };
  }

  /// Yes, no, or null for never asked. A bool rather than an enum of three:
  /// there is no fourth answer to add, and a switch over three names would be
  /// a promise there never will be.
  final bool? _yes;

  /// Whether the player was asked at all.
  bool get wasAsked => _yes != null;

  /// Whether they said yes — to [policy], which may not be today's.
  bool get isGranted => _yes ?? false;

  /// The wording the player answered, by the name the game gives it —
  /// `'2026-10'`, `'v2'`.
  final String? policy;

  /// When they answered, in UTC.
  final DateTime? at;

  /// Whether a run may be sent under [currentPolicy].
  bool allows(String currentPolicy) => isGranted && policy == currentPolicy;

  Map<String, Object?> toJson() => <String, Object?>{
    'answer': switch (_yes) {
      true => 'granted',
      false => 'declined',
      null => 'notAsked',
    },
    if (policy != null) 'policy': policy,
    if (at != null) 'at': at!.toUtc().toIso8601String(),
  };
}
