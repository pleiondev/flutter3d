import 'level.dart';
import 'level_issue.dart';

/// A whole-level rule a game brings with it.
///
/// **Not every game is a shooter, and the validator used to assume one.** It
/// required exactly one `player_spawn` and warned about a missing `exit`, which
/// are rules about a genre rather than about the format: a game with several
/// starting points, or one that ends by a script rather than by walking into a
/// door, failed a check the engine had no business making.
///
/// What is left in the validator is what any level in this format must be true
/// of whatever the game is — names unique, references resolving, brushes not
/// degenerate, something to stand on, something to see by. Anything about
/// *which entities* a level ought to contain arrives here.
abstract base class LevelRule {
  const LevelRule();

  void check(Level level, List<LevelIssue> out);
}

/// There must be exactly this many of a type, no more and no fewer.
///
/// The rule a player spawn wants: none and the player starts at the origin,
/// which is usually inside the floor; two and nothing decides which is used.
final class ExactlyOne extends LevelRule {
  const ExactlyOne(this.type, {this.because});

  final String type;

  /// What goes wrong when the count is not one. Worth saying, because "there
  /// are 2 player_spawn entities" tells an author what and not why.
  final String? because;

  @override
  void check(Level level, List<LevelIssue> out) {
    final count = level.ofType(type).length;
    if (count == 1) return;
    out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        count == 0
            ? 'no $type${because == null ? '' : ': $because'}'
            : 'there are $count $type entities and nothing decides which is '
                'used',
      ),
    );
  }
}

/// There should be at least one of a type, or the level is missing something.
final class AtLeastOne extends LevelRule {
  const AtLeastOne(
    this.type, {
    this.because,
    this.severity = LevelIssueSeverity.warning,
  });

  final String type;
  final String? because;
  final LevelIssueSeverity severity;

  @override
  void check(Level level, List<LevelIssue> out) {
    if (level.ofType(type).isNotEmpty) return;
    out.add(
      LevelIssue(severity, 'no $type${because == null ? '' : ': $because'}'),
    );
  }
}
