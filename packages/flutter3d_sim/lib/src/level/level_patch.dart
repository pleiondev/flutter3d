import '../save/state_digest.dart';
import 'level.dart';
import 'level_diff.dart';

/// The lists a level keeps its pieces in, which a [LevelPatch] edits row by
/// row rather than whole.
const List<String> patchedLists = <String>['brushes', 'lights', 'entities'];

/// One row of one of [patchedLists] put in, taken out or replaced.
///
/// **A row is named by where it stands and what it was**, [at] and [was],
/// because the format gives a brush nothing else to be named by. Ids in the
/// document were the alternative and were refused: every level ever saved
/// would grow a key per row on its next save, recipes expand into brushes
/// that have none, and the editor's undo puts back whole documents, so ids
/// would have to be minted and kept stable across all of it. What a reference
/// has to guarantee is narrower than identity — that a patch never edits a
/// row other than the one it was made against — and the row's digest gives
/// exactly that: the receiving end finds the row at [at], digests it, and
/// refuses the patch when it is not the row [was] names.
final class RowEdit {
  const RowEdit({required this.list, required this.at, this.was, this.row});

  factory RowEdit.fromJson(Map<String, Object?> json) => RowEdit(
    list: json['list']! as String,
    at: (json['at']! as num).toInt(),
    was: json['was'] as String?,
    row: json['row'] as Map<String, Object?>?,
  );

  /// One of [patchedLists].
  final String list;

  /// Where the row stands in the list as it is when this edit is applied —
  /// after the edits before it in the patch, not in the original.
  final int at;

  /// The digest of the row taken out or replaced; null for a row put in.
  final String? was;

  /// The row put in or replacing; null for a row taken out.
  final Map<String, Object?>? row;

  bool get inserts => was == null;
  bool get removes => row == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'list': list,
    'at': at,
    'was': ?was,
    'row': ?row,
  };
}

/// What changed between two versions of one level, as edits a running game
/// can make to the version it has.
///
/// **Made against a version, and applied only to that version.** [base] is
/// the digest of the level the patch was made from and [hash] the digest of
/// the level it makes; [applyTo] refuses a level that is not [base] and a
/// result that is not [hash]. A refusal costs one whole document — the sender
/// falls back to it — and a patch applied to the wrong level would cost a
/// level that nobody saved, so nothing between the two is guessed at.
///
/// Three kinds of change, by how the document holds them: rows of
/// [patchedLists] ([rows]), materials by name ([materials]), and every other
/// top-level key whole ([fields]) — fog, music, the ground, recipes, `next`,
/// and keys this format does not know. A list or the material table that one
/// side has and the other does not goes whole as a field too: the patch then
/// says what the document says rather than inventing an empty one.
final class LevelPatch {
  const LevelPatch({
    required this.base,
    required this.hash,
    this.rows = const <RowEdit>[],
    this.materials = const <String, Object?>{},
    this.fields = const <String, Object?>{},
  });

  factory LevelPatch.fromJson(Map<String, Object?> json) => LevelPatch(
    base: json['base']! as String,
    hash: json['hash']! as String,
    rows: <RowEdit>[
      for (final row in json['rows'] as List<Object?>? ?? const <Object?>[])
        RowEdit.fromJson(row! as Map<String, Object?>),
    ],
    materials:
        json['materials'] as Map<String, Object?>? ?? const <String, Object?>{},
    fields:
        json['fields'] as Map<String, Object?>? ?? const <String, Object?>{},
  );

  /// The edits that make [after] out of [before].
  ///
  /// Rows are matched by digest: a common head and tail are trimmed, and what
  /// is left between them is aligned by its longest common run, so a brush
  /// deleted from the middle of a thousand is one edit rather than the rest of
  /// the list shifted by one. Unmatched rows facing each other are paired as
  /// replacements, which is what moving or recolouring one thing looks like.
  /// A middle too long to align (see [_alignLimit]) is replaced row for row —
  /// a bigger patch, never a wrong one.
  factory LevelPatch.between(Level before, Level after) {
    final old = before.toJson();
    final now = after.toJson();
    final rows = <RowEdit>[];
    final fields = <String, Object?>{};
    for (final key in <String>{...old.keys, ...now.keys}) {
      final (a, b) = (old[key], now[key]);
      if (_digest(a) == _digest(b)) continue;
      if (patchedLists.contains(key) && a is List && b is List) {
        rows.addAll(_rowEdits(key, a, b));
      } else if (key == 'materials' && a is Map && b is Map) {
        // Handled below, by name.
      } else {
        fields[key] = b;
      }
    }
    final (oldMaterials, newMaterials) = (old['materials'], now['materials']);
    return LevelPatch(
      base: before.digestHex,
      hash: after.digestHex,
      rows: rows,
      materials: oldMaterials is Map && newMaterials is Map
          ? <String, Object?>{
              for (final name in <Object?>{
                ...oldMaterials.keys,
                ...newMaterials.keys,
              })
                if (_digest(oldMaterials[name]) != _digest(newMaterials[name]))
                  name! as String: newMaterials[name],
            }
          : const <String, Object?>{},
      fields: fields,
    );
  }

  /// The service extension error code a game answers a patch with when it
  /// does not apply — made against another version, or making one nobody
  /// saved. The sender's cue to send the whole document instead; any other
  /// error means the level itself was refused, and sending it whole would be
  /// refused the same way.
  ///
  /// Inside the range `dart:developer` leaves to extensions
  /// (`ServiceExtensionResponse.extensionErrorMin` to `extensionErrorMax`),
  /// spelled here because this package does not import the VM's.
  static const int staleCode = -32001;

  /// How many row pairs [LevelPatch.between] will align by longest common
  /// run, the cost of which grows as their product. A thousand by a thousand
  /// is four megabytes and a few milliseconds; past it, rows are replaced.
  static const int _alignLimit = 1000 * 1000;

  /// The digest of the level this patch was made from.
  final String base;

  /// The digest of the level it makes.
  final String hash;

  /// Row edits, in the order they are applied.
  final List<RowEdit> rows;

  /// Materials changed or added, by name; null for one taken out.
  final Map<String, Object?> materials;

  /// Other top-level keys, whole; null for one taken out.
  final Map<String, Object?> fields;

  /// Whether the patch changes nothing.
  bool get isEmpty => rows.isEmpty && materials.isEmpty && fields.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'base': base,
    'hash': hash,
    if (rows.isNotEmpty) 'rows': <Object?>[for (final r in rows) r.toJson()],
    if (materials.isNotEmpty) 'materials': materials,
    if (fields.isNotEmpty) 'fields': fields,
  };

  /// [level] with this patch made to it, and what that changed — or why not.
  ///
  /// **The diff comes from the patch, not from comparing the two levels.**
  /// The edits already say which lamp changed and whether any brush did, so
  /// the running game is told that without both documents being digested part
  /// by part. The exception is a list or the material table sent whole, where
  /// the patch knows that the part changed and not where: that is compared
  /// the way [diffLevel] compares documents.
  LevelPatchResult applyTo(Level level) {
    final had = level.digestHex;
    if (had != base) {
      return LevelPatchRefused(
        'the patch was made against level $base and the game has $had',
      );
    }
    final document = level.toJson();
    for (final MapEntry(:key, :value) in fields.entries) {
      if (value == null) {
        document.remove(key);
      } else {
        document[key] = value;
      }
    }
    if (materials.isNotEmpty) {
      final table = <String, Object?>{
        ...document['materials'] as Map<String, Object?>? ??
            const <String, Object?>{},
      };
      for (final MapEntry(:key, :value) in materials.entries) {
        if (value == null) {
          table.remove(key);
        } else {
          table[key] = value;
        }
      }
      document['materials'] = table;
    }
    // Copies, because a list the level never changed is handed back by
    // `toJson` as the very list it was read from.
    final lists = <String, List<Object?>>{
      for (final list in <String>{for (final edit in rows) edit.list})
        list: <Object?>[...document[list] as List<Object?>? ?? const []],
    };
    for (final edit in rows) {
      final target = lists[edit.list]!;
      if (edit.inserts && edit.removes) {
        return LevelPatchRefused(
          '${edit.list}[${edit.at}] is neither put in nor taken out',
        );
      }
      final limit = edit.inserts ? target.length : target.length - 1;
      if (edit.at < 0 || edit.at > limit) {
        return LevelPatchRefused(
          '${edit.list}[${edit.at}] is past the end of the game\'s '
          '${target.length}',
        );
      }
      if (edit.was case final String was) {
        final found = _digest(target[edit.at]);
        if (found != was) {
          return LevelPatchRefused(
            '${edit.list}[${edit.at}] is $found in the game, not $was',
          );
        }
      }
      switch ((edit.was, edit.row)) {
        case (null, final Map<String, Object?> row):
          target.insert(edit.at, row);
        case (_, null):
          target.removeAt(edit.at);
        case (_, final Map<String, Object?> row):
          target[edit.at] = row;
      }
    }
    document.addAll(lists);

    final Level next;
    try {
      next = Level.fromJson(document);
    } on Object catch (error) {
      return LevelPatchRefused('the patched document is not a level: $error');
    }
    if (next.digestHex != hash) {
      return LevelPatchRefused(
        'the patched level digests to ${next.digestHex}, not $hash',
      );
    }
    final whole = fields.keys.any(
      (String key) => patchedLists.contains(key) || key == 'materials',
    );
    return LevelPatched(
      next,
      whole ? diffLevel(level, next) : _diff(level, next),
    );
  }

  /// What the edits change, read off the edits themselves — and, for a brush
  /// replaced in place, off the two rows, which is the one place the edit
  /// cannot say whether the simulation would feel it.
  LevelDiff _diff(Level before, Level after) {
    Iterable<RowEdit> of(String list) =>
        rows.where((RowEdit edit) => edit.list == list);
    final lights = of('lights');
    final lightCountChanged = lights.any(
      (RowEdit edit) => edit.inserts || edit.removes,
    );
    // `P7`: brushes replaced in place whose rows differ only in the draw
    // order are a look-only edit. With no row put in or taken out, an edit's
    // place is the brush's place in both levels.
    final brushes = of('brushes');
    final orderOnly =
        brushes.isNotEmpty &&
        brushes.every(
          (RowEdit edit) =>
              !edit.inserts &&
              !edit.removes &&
              _digest(brushWithoutOrder(before.brushes[edit.at])) ==
                  _digest(brushWithoutOrder(after.brushes[edit.at])),
        );
    return LevelDiff(
      brushOrder: orderOnly
          ? <int>[for (final edit in brushes) edit.at]
          : const <int>[],
      // With no row put in or taken out, a row's place in the patch is its
      // place in both levels.
      lights: lightCountChanged
          ? const <int>[]
          : <int>[for (final edit in lights) edit.at],
      lightCountChanged: lightCountChanged,
      materials: materials.keys.toList(),
      fog: fields.containsKey('fogColor') || fields.containsKey('fogDensity'),
      music: fields.containsKey('music'),
      simulation: <String>[
        if (brushes.isNotEmpty && !orderOnly) 'brushes',
        if (of('entities').isNotEmpty) 'entities',
        for (final key in const <String>['heightfield', 'recipes', 'next'])
          if (fields.containsKey(key)) key,
      ],
    );
  }

  static String _digest(Object? json) =>
      contentDigestHex(<String, Object?>{'v': json});

  /// Edits that turn the rows [a] of [list] into [b], applied in order.
  static List<RowEdit> _rowEdits(
    String list,
    List<Object?> a,
    List<Object?> b,
  ) {
    final oldDigests = <String>[for (final row in a) _digest(row)];
    final newDigests = <String>[for (final row in b) _digest(row)];
    final shorter = a.length < b.length ? a.length : b.length;
    final head = Iterable<int>.generate(
      shorter,
    ).takeWhile((int i) => oldDigests[i] == newDigests[i]).length;
    final tail = Iterable<int>.generate(shorter - head)
        .takeWhile(
          (int i) =>
              oldDigests[a.length - 1 - i] == newDigests[b.length - 1 - i],
        )
        .length;
    final from = oldDigests.sublist(head, a.length - tail);
    final to = newDigests.sublist(head, b.length - tail);

    final edits = <RowEdit>[];
    var at = head;
    var (i, j) = (0, 0);
    // Each anchor is a row kept; the sentinel at the end flushes what is left.
    for (final (ai, bj) in <(int, int)>[
      ..._anchors(from, to),
      (from.length, to.length),
    ]) {
      final removed = ai - i;
      final inserted = bj - j;
      final paired = removed < inserted ? removed : inserted;
      for (var k = 0; k < paired; k++) {
        edits.add(
          RowEdit(
            list: list,
            at: at++,
            was: from[i + k],
            row: b[head + j + k]! as Map<String, Object?>,
          ),
        );
      }
      for (var k = paired; k < removed; k++) {
        edits.add(RowEdit(list: list, at: at, was: from[i + k]));
      }
      for (var k = paired; k < inserted; k++) {
        edits.add(
          RowEdit(
            list: list,
            at: at++,
            row: b[head + j + k]! as Map<String, Object?>,
          ),
        );
      }
      at++;
      (i, j) = (ai + 1, bj + 1);
    }
    return edits;
  }

  /// The pairs of positions a longest common run of [a] and [b] keeps, in
  /// order. Empty when the two are too long to align (see [_alignLimit]).
  static List<(int, int)> _anchors(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty || a.length * b.length > _alignLimit) {
      return const <(int, int)>[];
    }
    final width = b.length + 1;
    // `runs[i * width + j]`: the longest common run of a[i..] and b[j..].
    final runs = List<int>.filled((a.length + 1) * width, 0);
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        runs[i * width + j] = a[i] == b[j]
            ? runs[(i + 1) * width + j + 1] + 1
            : _max(runs[(i + 1) * width + j], runs[i * width + j + 1]);
      }
    }
    final anchors = <(int, int)>[];
    var (i, j) = (0, 0);
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        anchors.add((i++, j++));
      } else if (runs[(i + 1) * width + j] >= runs[i * width + j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    return anchors;
  }

  static int _max(int a, int b) => a > b ? a : b;
}

/// What [LevelPatch.applyTo] made of a level.
sealed class LevelPatchResult {
  const LevelPatchResult();
}

/// The patch applied: [level] is the version it makes, and [diff] what that
/// changed for the running game.
final class LevelPatched extends LevelPatchResult {
  const LevelPatched(this.level, this.diff);

  final Level level;
  final LevelDiff diff;
}

/// The patch does not apply, and [reason] says where it stopped: a level
/// that is not the one it was made against, a row that is not the one it
/// names, or a result that is not the level it was meant to make.
final class LevelPatchRefused extends LevelPatchResult {
  const LevelPatchRefused(this.reason);

  final String reason;
}
