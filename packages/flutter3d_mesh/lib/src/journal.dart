/// Arrays that remember what an edit replaced.
///
/// **The shape `p0-05` chose, and the one it rejected is worth naming.** The
/// plan called for persistent vectors: positions in fixed-size chunks, a write
/// copying one chunk and a version sharing the rest. Measured on 200 000
/// vertices, that costs 1 % of a full copy when the edited vertices are
/// adjacent — dragging one face — and **92 to 100 %** when they are scattered,
/// which is what selecting every rib of a mesh and moving them looks like. A
/// thousand scattered vertices touch nearly every chunk, and copy-on-write
/// copies the mesh.
///
/// A journal of previous values costs 2 % in both cases and is faster in both.
/// So the values live in one flat array, and a step of history is the indices
/// an edit wrote and what was there before. See `doc/model-editor.md` §6 for
/// the table.
///
/// **What that trades away, stated because it decides how history is written.**
/// A persistent vector hands out *versions*: two of them exist at once and a
/// caller can hold the old one. A journal has one array and a way back, so an
/// older state exists only by undoing to it. Undo and redo are exactly what a
/// modeller needs; what it cannot do is show two versions side by side, which
/// nothing in the plan asks for.
library;

import 'dart:typed_data';

/// One step of a journal: which slots an edit wrote, and what they held.
///
/// Public because `doc-08`'s history and `doc-31d`'s file format both read it —
/// the file's history section is these records, not a second encoding of them.
final class JournalStep {
  const JournalStep(this.indices, this.before);

  /// Slots that were written, in the order they were written.
  final Int32List indices;

  /// What each of those slots held, index-aligned with [indices].
  ///
  /// A `TypedData` rather than a typed list, because the two vectors below hold
  /// floats and ints and a step of either is the same record. Whoever wrote it
  /// knows which it is; whoever replays it is the vector that owns it.
  final TypedData before;

  /// Bytes this step holds, which is what a history limit counts.
  int get byteCount => indices.lengthInBytes + before.lengthInBytes;
}

/// A growable list of floats that records what each step overwrote.
///
/// Reading is a plain array read — no chunk arithmetic, no indirection — which
/// is the other half of why this won the measurement: every operation on a mesh
/// reads far more than it writes.
final class JournalledFloats {
  JournalledFloats(int length) : _values = Float32List(length);

  JournalledFloats.of(Float32List values) : _values = values;

  Float32List _values;

  /// The values as they are now.
  ///
  /// **Handed out rather than copied, and writes through it are not recorded.**
  /// A reader that walks every vertex — a bounds pass, a conversion to
  /// `MeshData`, a BVH build — must not pay for a copy or for a bounds check
  /// per element. Anything that *edits* goes through [write], and
  /// `EditMesh` is what keeps that rule; this class cannot enforce it without
  /// giving up the cheap read.
  Float32List get values => _values;

  int get length => _values.length;

  double operator [](int index) => _values[index];

  final List<JournalStep> _undo = <JournalStep>[];
  final List<JournalStep> _redo = <JournalStep>[];

  // The step being built. Two growable lists rather than typed arrays, because
  // how many slots an edit will touch is not known until it ends; they are
  // copied into typed arrays once, at `endStep`.
  List<int>? _openIndices;
  List<double>? _openBefore;

  /// How many steps can be taken back.
  int get undoDepth => _undo.length;

  /// How many steps can be put back after an undo.
  int get redoDepth => _redo.length;

  /// Bytes the journal holds, both directions.
  ///
  /// What a history limit is written against: `doc-08` caps depth *and* size,
  /// because sixty-four steps over a large selection is a different amount of
  /// memory from sixty-four nudges of one vertex.
  int get journalBytes {
    var total = 0;
    for (final step in _undo) {
      total += step.byteCount;
    }
    for (final step in _redo) {
      total += step.byteCount;
    }
    return total;
  }

  /// Opens a step. Writes until [endStep] belong to it.
  ///
  /// Throws if one is already open: a nested step is a caller that has lost
  /// track of a transaction, and the failure it causes otherwise — an edit
  /// recorded in somebody else's step and undone with it — is invisible until
  /// somebody presses undo twice.
  void beginStep() {
    if (_openIndices != null) {
      throw StateError('a step is already open; end it before opening another');
    }
    _openIndices = <int>[];
    _openBefore = <double>[];
  }

  /// Closes the open step and pushes it onto the undo stack.
  ///
  /// A step that wrote nothing is dropped rather than pushed: a drag that ended
  /// where it started is not an undo step, and a stack full of those is a stack
  /// somebody has to press undo through.
  ///
  /// **[keepEmpty] is for a caller that keeps several of these in step**, which
  /// `EditMesh` does: nine arrays, and an edit that moved a vertex wrote to one
  /// of them. Dropping the empty steps would leave the arrays at different
  /// depths, and an undo would then take one array back a step and the others
  /// nowhere — which shows up as a mesh whose positions are from one version
  /// and whose topology is from another. An empty step is two empty arrays.
  ///
  /// Returns whether anything was actually recorded.
  bool endStep({bool keepEmpty = false}) {
    final indices = _openIndices;
    final before = _openBefore;
    if (indices == null || before == null) {
      throw StateError('no step is open');
    }
    _openIndices = null;
    _openBefore = null;
    if (indices.isEmpty && !keepEmpty) return false;
    if (indices.isEmpty) {
      _undo.add(JournalStep(Int32List(0), Float32List(0)));
      _redo.clear();
      return false;
    }

    _undo.add(
      JournalStep(Int32List.fromList(indices), Float32List.fromList(before)),
    );
    // Anything that was undone is unreachable now: the new step is a different
    // future. This is the one place a redo stack may be dropped, and dropping
    // it anywhere else is how a redo comes back as somebody else's edit.
    _redo.clear();
    return true;
  }

  /// Writes [value] at [index], recording what was there.
  ///
  /// **Recorded even when the value is unchanged**, deliberately: a caller that
  /// writes the same number is a caller whose edit happened to be a no-op for
  /// this slot, and skipping the record would make an undo of the *whole* step
  /// depend on which slots happened to match. The cost is eight bytes.
  void write(int index, double value) {
    final indices = _openIndices;
    if (indices == null) {
      throw StateError('no step is open; call beginStep before writing');
    }
    indices.add(index);
    _openBefore!.add(_values[index]);
    _values[index] = value;
  }

  /// Takes the last step back. Does nothing when there is none.
  bool undo() {
    if (_openIndices != null) {
      throw StateError('a step is open; end it before undoing');
    }
    if (_undo.isEmpty) return false;
    _redo.add(_backwards(_undo.removeLast()));
    return true;
  }

  /// Puts back the last undone step. Does nothing when there is none.
  bool redo() {
    if (_openIndices != null) {
      throw StateError('a step is open; end it before redoing');
    }
    if (_redo.isEmpty) return false;
    _undo.add(_forwards(_redo.removeLast()));
    return true;
  }

  /// Undoes [step], and returns the step that redoes it.
  ///
  /// **Backwards, and the direction is not symmetry — it is the case where a
  /// step wrote one slot twice.** A drag reports a position per pointer move,
  /// so `write(v, …)` on the same vertex thirty times in one step is the
  /// ordinary case. Walking backwards restores each slot to what it held
  /// before its *first* write, which is what the step began with; walking
  /// forwards would leave it holding what it had before its *last* one.
  JournalStep _backwards(JournalStep step) {
    final before = step.before as Float32List;
    final after = Float32List(step.indices.length);
    for (var i = step.indices.length - 1; i >= 0; i--) {
      final index = step.indices[i];
      after[i] = _values[index];
      _values[index] = before[i];
    }
    return JournalStep(step.indices, after);
  }

  /// Redoes [step] — whose `before` is the values the undo took away — and
  /// returns the step that undoes it again.
  ///
  /// Forwards, for the mirror of the reason above: replaying an edit means
  /// replaying its writes in the order they happened, so a slot written twice
  /// ends up holding the second value rather than the first.
  JournalStep _forwards(JournalStep step) {
    final after = step.before as Float32List;
    final before = Float32List(step.indices.length);
    for (var i = 0; i < step.indices.length; i++) {
      final index = step.indices[i];
      before[i] = _values[index];
      _values[index] = after[i];
    }
    return JournalStep(step.indices, before);
  }

  /// Drops the oldest steps until the journal is within [maxSteps] and
  /// [maxBytes], and returns how many were dropped.
  ///
  /// **The oldest, not the newest**, which is the only end that can be dropped:
  /// history is walked backwards from now, so losing step one leaves every
  /// later step still applicable, and losing the last one leaves a document
  /// nobody can undo out of.
  int trim({int maxSteps = 64, int maxBytes = 64 * 1024 * 1024}) {
    var dropped = 0;
    while (_undo.length > maxSteps) {
      _undo.removeAt(0);
      dropped++;
    }
    var bytes = journalBytes;
    while (bytes > maxBytes && _undo.isNotEmpty) {
      bytes -= _undo.removeAt(0).byteCount;
      dropped++;
    }
    return dropped;
  }

  /// Grows the array to hold at least [length] values, keeping what is there.
  ///
  /// **Growth is not journalled, and that is a rule rather than an omission.**
  /// A step that added vertices is undone by removing them, which is topology
  /// rather than values — `EditMesh` records that in its own step and truncates
  /// back. A journal of "the array used to be shorter" would record the same
  /// fact twice and let the two disagree.
  void grow(int length) {
    if (length <= _values.length) return;
    // Doubling rather than exact: an operation that appends a vertex at a time
    // — an extrusion walking a loop — would otherwise copy the whole array per
    // vertex.
    final grown = Float32List(
      length > _values.length * 2 ? length : _values.length * 2,
    )..setRange(0, _values.length, _values);
    _values = grown;
  }

  /// Forgets every step. The values stay as they are.
  void clearJournal() {
    _undo.clear();
    _redo.clear();
  }

  /// Pushes [count] steps that wrote nothing.
  ///
  /// **For an array that arrives late.** `EditMesh` creates an attribute layer
  /// the first time somebody writes to it, which may be forty edits into a
  /// session — and every array has to sit at the same depth or an undo takes
  /// some of them back and leaves the rest. A layer that did not exist for
  /// those forty steps has nothing to say about them, which is exactly what an
  /// empty step means.
  void padSteps(int count) {
    for (var i = 0; i < count; i++) {
      _undo.add(JournalStep(Int32List(0), Float32List(0)));
    }
  }
}

/// The same, for the integer arrays a topology is made of.
///
/// A second class rather than a generic one: `Float32List` and `Int32List` have
/// no common supertype that can be indexed, and the alternative — `TypedData`
/// plus a cast per element — is a bounds check and a virtual call in the
/// hottest loop in the package.
final class JournalledInts {
  JournalledInts(int length) : _values = Int32List(length);

  JournalledInts.of(Int32List values) : _values = values;

  Int32List _values;

  /// The values as they are now. See [JournalledFloats.values] for why this is
  /// handed out rather than copied.
  Int32List get values => _values;

  int get length => _values.length;

  int operator [](int index) => _values[index];

  final List<JournalStep> _undo = <JournalStep>[];
  final List<JournalStep> _redo = <JournalStep>[];

  List<int>? _openIndices;
  List<int>? _openBefore;

  int get undoDepth => _undo.length;
  int get redoDepth => _redo.length;

  int get journalBytes {
    var total = 0;
    for (final step in _undo) {
      total += step.byteCount;
    }
    for (final step in _redo) {
      total += step.byteCount;
    }
    return total;
  }

  void beginStep() {
    if (_openIndices != null) {
      throw StateError('a step is already open; end it before opening another');
    }
    _openIndices = <int>[];
    _openBefore = <int>[];
  }

  /// See [JournalledFloats.endStep] for what [keepEmpty] is for.
  bool endStep({bool keepEmpty = false}) {
    final indices = _openIndices;
    final before = _openBefore;
    if (indices == null || before == null) {
      throw StateError('no step is open');
    }
    _openIndices = null;
    _openBefore = null;
    if (indices.isEmpty && !keepEmpty) return false;
    if (indices.isEmpty) {
      _undo.add(JournalStep(Int32List(0), Int32List(0)));
      _redo.clear();
      return false;
    }

    _undo.add(
      JournalStep(Int32List.fromList(indices), Int32List.fromList(before)),
    );
    _redo.clear();
    return true;
  }

  void write(int index, int value) {
    final indices = _openIndices;
    if (indices == null) {
      throw StateError('no step is open; call beginStep before writing');
    }
    indices.add(index);
    _openBefore!.add(_values[index]);
    _values[index] = value;
  }

  bool undo() {
    if (_openIndices != null) {
      throw StateError('a step is open; end it before undoing');
    }
    if (_undo.isEmpty) return false;
    _redo.add(_backwards(_undo.removeLast()));
    return true;
  }

  bool redo() {
    if (_openIndices != null) {
      throw StateError('a step is open; end it before redoing');
    }
    if (_redo.isEmpty) return false;
    _undo.add(_forwards(_redo.removeLast()));
    return true;
  }

  /// See [JournalledFloats._backwards] for why the two directions differ.
  JournalStep _backwards(JournalStep step) {
    final before = step.before as Int32List;
    final after = Int32List(step.indices.length);
    for (var i = step.indices.length - 1; i >= 0; i--) {
      final index = step.indices[i];
      after[i] = _values[index];
      _values[index] = before[i];
    }
    return JournalStep(step.indices, after);
  }

  JournalStep _forwards(JournalStep step) {
    final after = step.before as Int32List;
    final before = Int32List(step.indices.length);
    for (var i = 0; i < step.indices.length; i++) {
      final index = step.indices[i];
      before[i] = _values[index];
      _values[index] = after[i];
    }
    return JournalStep(step.indices, before);
  }

  int trim({int maxSteps = 64, int maxBytes = 64 * 1024 * 1024}) {
    var dropped = 0;
    while (_undo.length > maxSteps) {
      _undo.removeAt(0);
      dropped++;
    }
    var bytes = journalBytes;
    while (bytes > maxBytes && _undo.isNotEmpty) {
      bytes -= _undo.removeAt(0).byteCount;
      dropped++;
    }
    return dropped;
  }

  void grow(int length, {int fill = 0}) {
    if (length <= _values.length) return;
    final grown = Int32List(
      length > _values.length * 2 ? length : _values.length * 2,
    );
    if (fill != 0) grown.fillRange(_values.length, grown.length, fill);
    grown.setRange(0, _values.length, _values);
    _values = grown;
  }

  void clearJournal() {
    _undo.clear();
    _redo.clear();
  }

  /// See [JournalledFloats.padSteps].
  void padSteps(int count) {
    for (var i = 0; i < count; i++) {
      _undo.add(JournalStep(Int32List(0), Int32List(0)));
    }
  }
}
