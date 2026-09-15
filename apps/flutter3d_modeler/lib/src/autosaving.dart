/// Writing a recovery copy of the open document, on a timer, in the
/// background.
///
/// **Everything that decides *whether* to write is `doc-17`'s — `shouldSave`,
/// `recoveryPathFor` — and lives with no timer or clock of its own.** This
/// file is the other half: a real `Timer` and a real `clock.now()`, which
/// is what lets a test drive both through `package:fake_async` instead of
/// waiting on a wall clock.
///
/// **Nothing here tracks a project's path yet.** `ModelerReady` carries none
/// — the start screen that would set one, `ui-15`, is not built — so every
/// session autosaves under one key for its own lifetime
/// (`recoveryPathFor(null, sessionId: ...)`), which is exactly the case that
/// signature exists for. Wiring a real path through is `ui-15`'s to finish,
/// not a reason to hold this back.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart' show clock;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'modeler_cubit.dart';

/// Watches a [ModelerCubit] and writes a recovery copy of its document to
/// [storage] whenever [AutosavePolicy] says to.
///
/// **Polls rather than reacting to every emission**, on a period shorter than
/// [AutosavePolicy.debounce] — every 500ms — because the cubit emits for
/// reasons that are not edits at all (`say`, `mode`, `tool`), and asking
/// `shouldSave` after every one of those would mean an editor idling in a
/// menu still ticks the clock this reads. Polling is cheap: [shouldSave] is a
/// handful of `DateTime` comparisons, and the write itself only happens when
/// it answers yes.
final class AutosaveController {
  AutosaveController({
    required this.cubit,
    required this.storage,
    required this.sessionId,
    this.policy = const AutosavePolicy(),
    this.issues,
    this.onIssue,
    this.onRecovered,
    Duration pollEvery = const Duration(milliseconds: 500),
  }) {
    _lastEditAt = clock.now();
    _subscription = cubit.stream.listen(_onState);
    _timer = Timer.periodic(pollEvery, (_) => _check());
  }

  final ModelerCubit cubit;
  final BinaryStorage storage;

  /// Minted once per ununsaved session — see the library doc comment on why
  /// there is no path to key this on instead.
  final String sessionId;

  final AutosavePolicy policy;

  /// Where [storage] reports *why* a write failed.
  ///
  /// [BinaryStorage.write] answers `false` and nothing else — "no such
  /// directory" and "the disk is full" are different days, and a person told
  /// only that autosave is not working has nowhere to go. Handing the same
  /// [IssueLog] to the storage and to this controller is what lets [onIssue]
  /// carry the sentence the storage actually wrote.
  final IssueLog? issues;

  /// Told once per failure, not once per failed attempt — see [_check].
  ///
  /// The argument is the reason, as [issues] last recorded it, or a plain
  /// "could not write" where nothing said more.
  final void Function(String reason)? onIssue;

  /// Told when a write succeeds after [onIssue] fired, so an application
  /// showing "autosave is not working" can stop showing it. Called on the
  /// edge out of failure only, the mirror of [onIssue]'s own edge in.
  final void Function()? onRecovered;

  /// Whether the last attempt failed — what a crash dialog asks before
  /// promising a person their edits were written.
  bool get isFailing => _lastAttemptFailed;

  late DateTime _lastEditAt;
  DateTime? _lastSavedAt;

  /// Set while a write is in flight, so a slow [BinaryStorage.write] cannot
  /// overlap with the next poll's own write of a document that has since
  /// moved on.
  bool _writing = false;

  /// Whether the last attempt failed — [onIssue] fires on the edge into this
  /// state, not on every tick it stays true, which is what keeps a storage
  /// that is stuck refusing from repeating itself every poll.
  bool _lastAttemptFailed = false;

  late final StreamSubscription<ModelerState> _subscription;
  late final Timer _timer;

  void _onState(ModelerState state) {
    if (state is ModelerReady && state.history.isDirty) {
      _lastEditAt = clock.now();
    }
  }

  Future<void> _check() async {
    if (_writing) return;
    final state = cubit.state;
    if (state is! ModelerReady) return;

    final now = clock.now();
    if (!shouldSave(
      policy,
      isDirty: state.history.isDirty,
      now: now,
      lastEditAt: _lastEditAt,
      lastSavedAt: _lastSavedAt,
    )) {
      return;
    }

    _writing = true;
    try {
      final Uint8List bytes = writeProject(state.history.project);
      final key = recoveryPathFor(null, sessionId: sessionId);
      final wrote = await storage.write(key, bytes);
      _lastSavedAt = clock.now();
      if (!wrote) {
        if (!_lastAttemptFailed) onIssue?.call(_reason());
        _lastAttemptFailed = true;
      } else {
        if (_lastAttemptFailed) onRecovered?.call();
        _lastAttemptFailed = false;
      }
    } finally {
      _writing = false;
    }
  }

  /// What [issues] last heard from [storage], stripped of the prefix the
  /// storage puts on every message of its own — a person reading the status
  /// line is already being told this is about autosave.
  String _reason() {
    final List<String> said = issues?.issues ?? const <String>[];
    if (said.isEmpty) return 'could not write';
    const String prefix = 'storage: ';
    final String last = said.last;
    return last.startsWith(prefix) ? last.substring(prefix.length) : last;
  }

  void dispose() {
    _timer.cancel();
    unawaited(_subscription.cancel());
  }
}

/// Writes [cubit]'s open document to [sessionId]'s own recovery slot right
/// now, bypassing [AutosavePolicy] entirely.
///
/// `ui-30n`'s own "аварийная запись автосохранения до показа ошибки": a
/// crash is not a moment to wait out a debounce, and [AutosaveController]'s
/// last poll may predate the very edit that is about to be lost. Same key,
/// same [writeProject] as the periodic write, so a session that crashed
/// offers the same "предложение восстановить" on its next launch as one that
/// autosaved on schedule.
///
/// A no-op when there is no open document — nothing here throws a second
/// exception on top of the first.
///
/// Answers whether the bytes actually landed, because the dialog that follows
/// says so out loud: `ux-01`'s own finding was a crash dialog promising "an
/// emergency autosave was written" at the end of a session where every write
/// had failed. `false` covers both "nothing to write" and "the storage
/// refused".
Future<bool> emergencyAutosave(
  ModelerCubit cubit,
  BinaryStorage storage,
  String sessionId,
) async {
  final ModelerState state = cubit.state;
  if (state is! ModelerReady) return false;
  final Uint8List bytes = writeProject(state.history.project);
  return storage.write(recoveryPathFor(null, sessionId: sessionId), bytes);
}
