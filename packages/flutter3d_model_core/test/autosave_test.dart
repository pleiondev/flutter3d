/// `shouldSave`, `recoveryPathFor` and `decideRecovery`: pure enough that
/// none of this needs a timer, a clock or a filesystem to test.
///
///     dart test test/autosave_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

void main() {
  group('shouldSave', () {
    const policy = AutosavePolicy(
      debounce: Duration(seconds: 2),
      minInterval: Duration(seconds: 15),
    );
    final edited = DateTime(2026, 1, 1, 12, 0, 0);

    test('a clean document never saves', () {
      // Mutation: check `lastSavedAt == null` before `isDirty`. Every
      // boundary below would still pass on a document that has nothing to
      // save at all.
      expect(
        shouldSave(
          policy,
          isDirty: false,
          now: edited.add(const Duration(minutes: 5)),
          lastEditAt: edited,
        ),
        isFalse,
      );
    });

    test('before the debounce elapses, no save', () {
      expect(
        shouldSave(
          policy,
          isDirty: true,
          now: edited.add(const Duration(milliseconds: 1999)),
          lastEditAt: edited,
        ),
        isFalse,
      );
    });

    test('at exactly the debounce, with nothing saved yet, it saves', () {
      // Mutation: use `>` instead of `>=` for the debounce comparison. This
      // is the one instant that tells the two apart.
      expect(
        shouldSave(
          policy,
          isDirty: true,
          now: edited.add(const Duration(seconds: 2)),
          lastEditAt: edited,
        ),
        isTrue,
      );
    });

    test('debounce has passed but the last save was too recent', () {
      final lastSaved = edited.add(const Duration(seconds: 1));
      expect(
        shouldSave(
          policy,
          isDirty: true,
          now: edited.add(const Duration(seconds: 10)),
          lastEditAt: edited,
          lastSavedAt: lastSaved,
        ),
        isFalse,
      );
    });

    test('at exactly minInterval since the last save, it saves again', () {
      final lastSaved = edited;
      expect(
        shouldSave(
          policy,
          isDirty: true,
          now: lastSaved.add(const Duration(seconds: 15)),
          lastEditAt: edited.subtract(const Duration(minutes: 1)),
          lastSavedAt: lastSaved,
        ),
        isTrue,
      );
    });

    test('continuous editing never autosaves more than once a minInterval', () {
      // A save just happened; editing resumes and goes quiet again well past
      // the debounce, but inside minInterval of the last write.
      final lastSaved = edited;
      expect(
        shouldSave(
          policy,
          isDirty: true,
          now: lastSaved.add(const Duration(seconds: 5)),
          lastEditAt: lastSaved.add(const Duration(seconds: 1)),
          lastSavedAt: lastSaved,
        ),
        isFalse,
      );
    });
  });

  group('recoveryPathFor', () {
    test('the same path always gives the same key', () {
      expect(
        recoveryPathFor('/models/table.f3dproj', sessionId: 'a'),
        recoveryPathFor('/models/table.f3dproj', sessionId: 'z'),
      );
    });

    test('two different paths give different keys', () {
      expect(
        recoveryPathFor('/models/table.f3dproj', sessionId: 'a'),
        isNot(recoveryPathFor('/models/chair.f3dproj', sessionId: 'a')),
      );
    });

    test('a null path falls back to the session id, not to a shared key', () {
      // Mutation: fall back to a constant string for a null path. Two unsaved
      // documents open at once would then autosave over each other.
      expect(
        recoveryPathFor(null, sessionId: 'session-1'),
        isNot(recoveryPathFor(null, sessionId: 'session-2')),
      );
    });

    test('the key is stable across runs — a fixed, checked example', () {
      // Not just "deterministic within one process": FNV-1a is a named,
      // specified algorithm precisely so this exact string survives a Dart
      // upgrade, unlike `String.hashCode`.
      expect(
        recoveryPathFor('/models/table.f3dproj', sessionId: 'unused'),
        'autosave/$_fnv1aOfPathTable',
      );
    });
  });

  group('decideRecovery', () {
    final t0 = DateTime(2026, 1, 1);
    final t1 = t0.add(const Duration(minutes: 1));

    test('no autosave at all: open the file', () {
      expect(
        decideRecovery(savedAt: t0, autosaveAt: null),
        RecoveryDecision.openSaved,
      );
    });

    test('an autosave and no saved file: offer it', () {
      expect(
        decideRecovery(savedAt: null, autosaveAt: t0),
        RecoveryDecision.offerAutosave,
      );
    });

    test('the autosave is strictly newer: offer it', () {
      expect(
        decideRecovery(savedAt: t0, autosaveAt: t1),
        RecoveryDecision.offerAutosave,
      );
    });

    test('the saved file is newer or equal: open it, not the stale copy', () {
      // Mutation: use `isBefore`/`>=` the other way, offering the autosave
      // when it is actually the older of the two.
      expect(
        decideRecovery(savedAt: t1, autosaveAt: t0),
        RecoveryDecision.openSaved,
      );
      expect(
        decideRecovery(savedAt: t0, autosaveAt: t0),
        RecoveryDecision.openSaved,
      );
    });
  });
}

/// Computed once by hand (FNV-1a 64-bit over `'path:/models/table.f3dproj'`)
/// so the "stable across runs" test pins an actual value rather than only
/// re-deriving the function under test and comparing it with itself.
const String _fnv1aOfPathTable = '19eab94e95010514';
