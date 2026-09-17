/// A replayable record of every command run against a project.
///
/// **JSON Lines, and a line each, rather than one JSON array.** A crash mid
/// write truncates the last line; every line before it is still whole JSON,
/// which is what makes recovery — `doc-17`'s `AutosavePolicy`, reading this
/// file back after a crash — possible over a container `doc-16` merely
/// describes the shape of. An array would need the closing bracket to parse at
/// all, and the one line most likely to be missing after a crash is the last
/// one written.
///
/// **Separate from `ModelHistory` on purpose.** `ModelHistory` keeps whole
/// documents so undo can never be wrong about anything, and collapses a
/// transaction to the *first* command it ran for the sake of one undo-stack
/// label — the rest of a hundred-frame drag is not kept anywhere. A journal
/// meant to survive a crash needs every one of those hundred, not the label,
/// so it is recorded alongside `ModelHistory.run` rather than read back out of
/// it: a caller writes to both, in step, each time a command succeeds.
///
/// **Only what succeeded is recorded, and that is what makes a refusal during
/// [replay] a real fault.** A caller records a command after `ModelHistory.run`
/// returns null, never before — so a line replay refuses on is a line the same
/// commands, run in the same order, did not refuse on the first time: a
/// different build, a corrupted line, or a command that reads something the
/// journal does not carry.
///
/// **A real limit, narrower than it used to be: a command that reads
/// `selection` rather than taking ids in its own arguments cannot replay
/// correctly unless every change to that selection was itself recorded.**
/// `doc-06`'s object commands take an id because of exactly this — `Rename`,
/// `SetTransform`, `SetParent`, `AssignMaterial`, `SetParametric` and the rest
/// all replay cleanly — but `MoveBy`, `RotateBy`, `ScaleBy`, `DeleteObjects`,
/// `DuplicateObjects` and every mesh command act on "what is selected".
/// **`tut-05`, closed:** `ModelSession.select` — the door an agent over MCP
/// picks through — now runs `SelectElements`, a thin, non-mutating
/// `ModelCommand` (`command.dart`) that records and replays a pick the same
/// as any other edit, at either object or mesh-element level. What remains
/// outside this journal's reach is only a caller that assigns
/// `ModelHistory.selection =` directly, bypassing both `select` and
/// [ModelHistory.run] — the live application's own pointer and gizmo click
/// path (`ModelerCubit`) still does, a UI-implementation choice rather than a
/// limit of this format: nothing stops that click from running
/// `SelectElements` through `run` too, it simply does not today.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'command.dart';
import 'history.dart';
import 'project.dart';

/// One JSON Lines record, and the one way back into a project from nothing
/// but that record.
final class CommandJournal {
  CommandJournal();

  final List<String> _lines = <String>[];

  /// Transactions opened whose `begin` marker has not been written yet.
  ///
  /// **A transaction that records nothing writes no markers at all** —
  /// `tut-01`'s own gap, found reading `case1.jsonl`. `ModelHistory` already
  /// promised this on its side: "a transaction in which nothing succeeded
  /// leaves no step". This journal promised it on replay — an empty bracket is
  /// a no-op there — and broke it on the page, where a `cleanup()` that found
  /// nothing to clean still left a `begin`/`end` pair for whoever opened the
  /// file to puzzle over. Holding the marker until the first line inside it
  /// costs one counter and makes the two promises the same promise.
  ///
  /// Counted rather than flagged, because transactions nest: the count is how
  /// many `begin` lines a record has to lay down before its own, which is what
  /// keeps the depth a replay sees the depth the caller opened.
  int _unwrittenBegins = 0;

  /// How many lines have been recorded, transaction markers included.
  ///
  /// A transaction that has opened but not yet recorded anything counts for
  /// nothing here, because it has written nothing — see [_unwrittenBegins].
  int get length => _lines.length;

  /// Records [command] as the next line. Call this after [command] has
  /// already run and succeeded — see the library comment for why an earlier
  /// call would make a refusal during [replay] mean nothing.
  ///
  /// [author] rides alongside the command's own arguments as one more key,
  /// `mcp-12n`'s own reason this journal names one at all — the same
  /// `StepAuthor` `HistoryStep` (`mcp-10n`) already carries, read back by
  /// [replay] and threaded into `ModelHistory.run` the same way, so a
  /// recovered journal's undo stack refuses an agent's own undo past a
  /// person's step exactly as the live session would have.
  void record(ModelCommand command, {StepAuthor author = StepAuthor.person}) {
    _writeOpenBegins();
    _lines.add(
      jsonEncode(<String, Object?>{...command.toJson(), 'author': author.name}),
    );
  }

  /// Lays down the `begin` lines for every transaction still holding one.
  void _writeOpenBegins() {
    for (; _unwrittenBegins > 0; _unwrittenBegins--) {
      _lines.add(_beginMarker);
    }
  }

  /// Forgets the last recorded step and writes [replacement] in its place —
  /// the journal-side half of `ModelHistory.amend`'s own "the stack does
  /// not grow" rule.
  ///
  /// **Overwrites rather than appending, so a cold [replay] lands on the
  /// adjusted state.** A caller pairs this with `ModelHistory.amend`, at the
  /// same moment: that method re-runs [replacement] against the document
  /// the top step's own command ran against, in place of it, and this
  /// forgets the original line(s) the same way — replay meets a `command`
  /// line carrying [replacement]'s own arguments where the original's used
  /// to be, and reaches the adjusted document directly rather than the
  /// original followed by a second, unrecorded edit on top of it.
  ///
  /// **A step [transaction] wrote as a `beginTransaction`/several lines/
  /// `endTransaction` bracket loses the whole bracket, not only its own
  /// last line.** `ModelHistory.amend` replaces everything back to
  /// `HistoryStep.before` — the document as it stood before the *whole*
  /// step, transaction or not — with [replacement] alone, so a journal that
  /// kept the bracket's inner lines would replay a step nothing in the live
  /// session still remembers taking.
  void amend(
    ModelCommand replacement, {
    StepAuthor author = StepAuthor.person,
  }) {
    if (_lines.isNotEmpty && _lines.last == _endMarker) {
      _lines.removeLast();
      var depth = 1;
      while (depth > 0 && _lines.isNotEmpty) {
        final String removed = _lines.removeLast();
        if (removed == _endMarker) {
          depth++;
        } else if (removed == _beginMarker) {
          depth--;
        }
      }
    } else if (_lines.isNotEmpty) {
      _lines.removeLast();
    }
    record(replacement, author: author);
  }

  /// Brackets the commands recorded between this and the matching
  /// [endTransaction] as one undo step on [replay], mirroring
  /// `ModelHistory.beginTransaction`. Call it at the same moment a caller
  /// opens the transaction on its own `ModelHistory`, not after.
  ///
  /// **The marker itself waits for the first line inside it** — see
  /// [_unwrittenBegins]. A transaction that records nothing leaves nothing.
  void beginTransaction() => _unwrittenBegins++;

  /// Closes the transaction [beginTransaction] opened.
  void endTransaction() {
    if (_unwrittenBegins > 0) {
      // Nothing was recorded inside it, so its `begin` never reached the page
      // and neither does this.
      _unwrittenBegins--;
      return;
    }
    _lines.add(_endMarker);
  }

  /// Abandons the transaction [beginTransaction] opened: on [replay] it is
  /// closed and then taken straight back, leaving the project exactly as it
  /// was before the first command inside it — `ux-20`.
  ///
  /// **A marker rather than erasing the lines.** A journal is append-only,
  /// because it is written to a file as it goes and a crash between two edits
  /// is the case it exists for; rewinding a file that may already be on disk
  /// is not something this can promise. Saying "and then that was undone" is
  /// something it can.
  ///
  /// A transaction whose every command refused recorded nothing, so there is
  /// nothing on the page to take back and no marker to write — the same
  /// silence [endTransaction] keeps, and the case `replay`'s own rollback
  /// branch already guards against on the other side.
  void rollbackTransaction() {
    if (_unwrittenBegins > 0) {
      _unwrittenBegins--;
      return;
    }
    _lines.add(_rollbackMarker);
  }

  /// Runs [body], recording everything it does as one transaction.
  T transaction<T>(T Function() body) {
    beginTransaction();
    try {
      return body();
    } finally {
      endTransaction();
    }
  }

  static final String _beginMarker = jsonEncode(<String, Object?>{
    'transaction': 'begin',
  });
  static final String _endMarker = jsonEncode(<String, Object?>{
    'transaction': 'end',
  });
  static final String _rollbackMarker = jsonEncode(<String, Object?>{
    'transaction': 'rollback',
  });

  /// The journal so far, one JSON object per line, UTF-8, each line ended.
  Uint8List toBytes() => utf8.encode(_lines.map((String l) => '$l\n').join());

  /// Replays a journal written by [record]/[beginTransaction]/[endTransaction]
  /// against [initial], returning the history it reaches — undo stack and
  /// all, one step per transaction — or the sentence and the line it could
  /// not go on.
  ///
  /// **A transaction left open at the end of the file is closed rather than
  /// dropped.** That is not a garbled journal; it is the ordinary shape of one
  /// that stops mid-drag — the exact moment `doc-17` exists to recover from —
  /// and everything recorded before the crash is still a real edit.
  static JournalReplay replay(Uint8List bytes, ModelProject initial) {
    final history = ModelHistory(initial);
    final lines = utf8.decode(bytes).split('\n');
    // How tall the undo stack was when the open transaction began — what a
    // `rollback` marker measures against. See that case below.
    var stepsBeforeTransaction = 0;
    for (var i = 0; i < lines.length; i++) {
      final String raw = lines[i];
      if (raw.trim().isEmpty) continue;

      final Object? parsed;
      try {
        parsed = jsonDecode(raw);
      } on FormatException {
        return JournalReplay.refused('line ${i + 1} is not JSON');
      }

      switch (parsed) {
        case {'transaction': 'begin'}:
          stepsBeforeTransaction = history.steps.length;
          history.beginTransaction();
          continue;
        case {'transaction': 'end'}:
          history.endTransaction();
          continue;
        // `ux-20`: a batch one of whose commands refused. The `end` marker
        // came first and has already left whatever succeeded as one step;
        // this takes that step back, so the replay lands where the live
        // session landed — on the project as it was before the batch.
        //
        // **Guarded on a step having actually appeared.** A transaction in
        // which nothing succeeded leaves none, and an unguarded undo here
        // would reach past it and take back the edit *before* the batch —
        // a rollback that deletes somebody's work.
        case {'transaction': 'rollback'}:
          history.endTransaction();
          if (history.steps.length > stepsBeforeTransaction) {
            history
              ..undo()
              ..dropRedo();
          }
          continue;
      }

      final ModelCommand? command = modelCommandFromJson(parsed);
      if (command == null) {
        return JournalReplay.refused(
          'line ${i + 1} names a command this build does not know',
        );
      }
      // Absent reads as `person` — the same "a name nobody wrote is a human"
      // default `HistoryStep.author` has always had, so a journal written
      // before this row read the same way it always did.
      final StepAuthor author = switch (parsed) {
        {'author': 'agent'} => StepAuthor.agent,
        _ => StepAuthor.person,
      };
      final String? refusal = history.run(command, author: author);
      if (refusal != null) {
        return JournalReplay.refused('line ${i + 1}: $refusal');
      }
    }
    // A no-op when the file closed its own transactions, and the recovery
    // for the one that did not.
    history.endTransaction();
    return JournalReplay.ok(history);
  }
}

/// What [CommandJournal.replay] reached.
///
/// **A whole [ModelHistory], not the [ModelProject] it holds.** A transaction
/// marker exists so a hundred-frame drag replays as one undo step rather than
/// a hundred — and that fact lives in `ModelHistory`'s stack, not in the
/// project value. Handing back the project alone would answer "what does it
/// look like now" and throw away "what would ⌘Z do", which is the one thing a
/// caller recovering from a crash and continuing to edit needs.
final class JournalReplay {
  const JournalReplay._(this.history, this.refused);

  factory JournalReplay.ok(ModelHistory history) =>
      JournalReplay._(history, null);

  factory JournalReplay.refused(String said) => JournalReplay._(null, said);

  final ModelHistory? history;
  final String? refused;

  bool get ok => refused == null;
}
