/// Which faces of the atlas are redrawn this frame.
///
/// The dynamic atlas holds only the things that move, and most frames most of
/// them are not moving: a monster standing still, a door that is shut, a room
/// the player has left. Redrawing all six faces of every occupied row every
/// frame pays for all of that regardless.
///
/// So the caller offers a signature per tile — what would be drawn there if it
/// were drawn now — and this decides. A tile whose signature is unchanged is
/// left alone, which is only possible because a tile can now be reset by
/// drawing rather than by clearing the whole attachment; see
/// shadow_tile_reset.frag.
final class ShadowFaceScheduler {
  ShadowFaceScheduler({required this.tileCount, this.budget = 0})
    : assert(tileCount >= 0),
      assert(budget >= 0),
      _drawn = List<int?>.filled(tileCount, null);

  /// Tiles in the atlas: rows times faces.
  final int tileCount;

  /// Most tiles to redraw in one frame, or zero for no limit.
  ///
  /// A limit trades latency for a flat cost: a shadow can lag its caster by
  /// `tiles / budget` frames in the worst case. Worth it when many lights are
  /// moving at once, which is exactly when the unlimited version spikes.
  final int budget;

  final List<int?> _drawn;

  /// Where the next scan starts, so a tile that keeps losing to the budget
  /// eventually wins. Without it the low-numbered tiles would take every slot
  /// and a light at the end of the atlas would never update at all.
  int _cursor = 0;

  final List<int> _selection = <int>[];
  List<int>? _pending;

  /// Tiles to redraw, given what each would now contain.
  ///
  /// [signatures] must have [tileCount] entries; a null entry means the tile is
  /// unused and is never selected. The result is owned by this scheduler and
  /// reused, so copy it if it must outlive the frame.
  List<int> select(List<int?> signatures) {
    assert(signatures.length == tileCount);
    _pending = List<int>.filled(tileCount, 0);
    _selection.clear();
    if (tileCount == 0) return _selection;

    for (var n = 0; n < tileCount; n++) {
      final tile = (_cursor + n) % tileCount;
      final signature = signatures[tile];
      if (signature == null) continue;
      _pending![tile] = signature;
      if (_drawn[tile] == signature) continue;
      _selection.add(tile);
      if (budget > 0 && _selection.length >= budget) {
        // Resume after the last tile taken, not after the last tile looked at:
        // the ones passed over were up to date and do not need a turn.
        _cursor = (tile + 1) % tileCount;
        return _selection;
      }
    }
    _cursor = 0;
    return _selection;
  }

  /// Records that the tiles from the last [select] were drawn.
  ///
  /// Separate for the same reason the slot allocator's bake record is: a frame
  /// can decide and then not draw, and a scheduler that marked tiles clean on
  /// the strength of the decision would leave a shadow permanently stale.
  void recordDrawn() {
    final pending = _pending;
    if (pending == null) return;
    for (final tile in _selection) {
      _drawn[tile] = pending[tile];
    }
  }

  /// Forgets everything, for a reallocated atlas whose pixels are gone.
  void reset() {
    for (var i = 0; i < tileCount; i++) {
      _drawn[i] = null;
    }
    _cursor = 0;
    _selection.clear();
    _pending = null;
  }
}
