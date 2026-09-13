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
/// **A real limit: a command that reads `selection` rather than taking ids in
/// its own arguments cannot replay correctly unless every change to that
/// selection was itself recorded.** `doc-06`'s object commands take an id
/// because of exactly this — `Rename`, `SetTransform`, `SetParent`,
/// `AssignMaterial`, `SetParametric` and the rest all replay cleanly — but
/// `MoveBy`, `RotateBy`, `ScaleBy`, `DeleteObjects`, `DuplicateObjects` and
/// every mesh command act on "what is selected", and object-level picking is
/// a mouse click that goes through `ModelHistory.selection =`, never through a
/// `ModelCommand`. A caller building a recovery journal on this and using any
/// of those has to also record its own selection changes, replayed before the
/// command that needs them; nothing here does that for it.
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

  /// How many lines have been recorded, transaction markers included.
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
  void record(ModelCommand command, {StepAuthor author = StepAuthor.person}) =>
      _lines.add(
        jsonEncode(<String, Object?>{
          ...command.toJson(),
          'author': author.name,
        }),
      );

  /// Brackets the commands recorded between this and the matching
  /// [endTransaction] as one undo step on [replay], mirroring
  /// `ModelHistory.beginTransaction`. Call it at the same moment a caller
  /// opens the transaction on its own `ModelHistory`, not after.
  void beginTransaction() => _marker('begin');

  /// Closes the transaction [beginTransaction] opened.
  void endTransaction() => _marker('end');

  /// Runs [body], recording everything it does as one transaction.
  T transaction<T>(T Function() body) {
    beginTransaction();
    try {
      return body();
    } finally {
      endTransaction();
    }
  }

  void _marker(String which) =>
      _lines.add(jsonEncode(<String, Object?>{'transaction': which}));

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
          history.beginTransaction();
          continue;
        case {'transaction': 'end'}:
          history.endTransaction();
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
