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
    this.onIssue,
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

  /// Told once per failure, not once per failed attempt — see [_check].
  final void Function(String said)? onIssue;

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
        if (!_lastAttemptFailed) onIssue?.call('autosave: could not write');
        _lastAttemptFailed = true;
      } else {
        _lastAttemptFailed = false;
      }
    } finally {
      _writing = false;
    }
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
Future<void> emergencyAutosave(
  ModelerCubit cubit,
  BinaryStorage storage,
  String sessionId,
) async {
  final ModelerState state = cubit.state;
  if (state is! ModelerReady) return;
  final Uint8List bytes = writeProject(state.history.project);
  await storage.write(recoveryPathFor(null, sessionId: sessionId), bytes);
}
