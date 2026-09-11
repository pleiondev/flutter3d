/// When an editor should write a recovery copy of its document, and what to
/// offer when a stale one is found.
///
/// **Pure functions only — a timer, an atomic write and a "recover?" dialog
/// are `ui-18`'s, in the app.** Keeping the decision here rather than beside
/// the timer is what lets `shouldSave` be driven by `FakeAsync` instead of a
/// real clock, and what lets `recoveryPathFor`/[decideRecovery] be tested
/// without a filesystem at all — see each function's own tests for exactly
/// that.
library;

import 'dart:convert';

/// How often an autosave is allowed to happen.
///
/// **Two independent gates, not one number.** [debounce] answers "has editing
/// gone quiet", so a drag or a fast run of commands does not write mid-motion;
/// [minInterval] answers "has it been long enough since the last write", so a
/// session of continuous small edits — each one going quiet for a moment —
/// does not autosave every couple of seconds regardless. Both have to pass.
final class AutosavePolicy {
  const AutosavePolicy({
    this.debounce = const Duration(seconds: 2),
    this.minInterval = const Duration(seconds: 15),
  });

  /// How long the document must have gone unedited before a save fires.
  final Duration debounce;

  /// The shortest gap allowed between two autosaves, however busy editing is.
  final Duration minInterval;
}

/// Whether right now is a moment [AutosavePolicy] says to write.
///
/// **Every fact it needs is a parameter — no clock read here.** A caller in
/// the app reads its own timer and `ModelHistory.isDirty`/`isDirty`'s own
/// bookkeeping and hands the answer in, which is what makes the boundary
/// cases (exactly at [AutosavePolicy.debounce], exactly at
/// [AutosavePolicy.minInterval]) something a test states directly instead of
/// something `FakeAsync` has to be nudged into landing on.
///
/// A clean document never saves: nothing has changed since the file already
/// on disk, so a write would cost an atomic rename to produce a byte-for-byte
/// copy of what is already there.
bool shouldSave(
  AutosavePolicy policy, {
  required bool isDirty,
  required DateTime now,
  required DateTime lastEditAt,
  DateTime? lastSavedAt,
}) {
  if (!isDirty) return false;
  if (now.difference(lastEditAt) < policy.debounce) return false;
  if (lastSavedAt != null && now.difference(lastSavedAt) < policy.minInterval) {
    return false;
  }
  return true;
}

/// The storage key an autosave for the project opened from [path] belongs
/// under.
///
/// **Deterministic from [path], not random, so reopening the same file finds
/// its own autosave** rather than starting a new trail every launch — the
/// whole point of a recovery copy. A path is hashed rather than used
/// verbatim because it can carry characters a storage key cannot (`/`, `:`,
/// length limits on some backends), and because the exact path is not
/// something an autosave key needs to be reversible from.
///
/// [path] is null for a project that has never been saved anywhere — a fresh
/// document has nothing on disk to derive a stable key from, so [sessionId]
/// stands in: a value the caller mints once when the project is created and
/// keeps for as long as that one unsaved document exists. Two different new
/// documents must not collide on the id in the way two openings of one saved
/// file are supposed to.
String recoveryPathFor(String? path, {required String sessionId}) {
  final key = path == null ? 'session:$sessionId' : 'path:$path';
  return 'autosave/${_fnv1a64(key)}';
}

/// FNV-1a, 64-bit, over the UTF-8 bytes of [value].
///
/// Not for anything adversarial — a stable, cross-platform identifier is all
/// this is for, and the whole point of picking a named, specified algorithm
/// over `String.hashCode` is that the latter is not guaranteed stable across
/// Dart versions, which a recovery key spanning app restarts cannot risk.
String _fnv1a64(String value) {
  const prime = 0x100000001b3;
  const mask64 = 0xFFFFFFFFFFFFFFFF;
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash = (hash ^ byte) & mask64;
    hash = (hash * prime) & mask64;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// What opening a project should do when a newer autosave exists for it.
enum RecoveryDecision {
  /// Nothing to offer: there is no autosave, or the file on disk is at least
  /// as new. Open the file as normal, without asking.
  openSaved,

  /// An autosave is strictly newer than the file — ask before choosing
  /// either, since the two disagree about what the document should be.
  offerAutosave,
}

/// Chooses [RecoveryDecision] by comparing when the project was last written
/// ([savedAt], null for a path that has never been saved) against when its
/// autosave was last written ([autosaveAt], null when none exists).
///
/// **Strictly newer, not merely different**, so two writes landing at the
/// same recorded time — an autosave immediately followed by an explicit save,
/// both stamped by a clock with second resolution — favour the file nobody
/// has to be asked about.
RecoveryDecision decideRecovery({DateTime? savedAt, DateTime? autosaveAt}) {
  if (autosaveAt == null) return RecoveryDecision.openSaved;
  if (savedAt == null) return RecoveryDecision.offerAutosave;
  return autosaveAt.isAfter(savedAt)
      ? RecoveryDecision.offerAutosave
      : RecoveryDecision.openSaved;
}
