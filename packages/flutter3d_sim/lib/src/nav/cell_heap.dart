import 'dart:typed_data';

/// A binary heap of cells ordered by cost, with lazy deletion.
///
/// Lazy rather than decrease-key: a cell reached again more cheaply is pushed
/// a second time and the stale entry is skipped when it surfaces. That costs a
/// few extra pushes and removes the position index a decrease-key needs, which
/// on a grid this size is the better trade.
///
/// An implementation detail of [FlowField]'s Dijkstra sweep, kept in its own
/// file because it is a data structure the sweep leans on rather than part of
/// what a flow field is.
final class CellHeap {
  Int32List _cell = Int32List(256);
  Int32List _cost = Int32List(256);
  int _size = 0;

  /// The cost of the entry [pop] last returned.
  int poppedCost = 0;

  /// Whether no entries are left, stale ones included.
  bool get isEmpty => _size == 0;

  /// Drops every entry, keeping the storage for the next sweep.
  void clear() => _size = 0;

  /// Adds [cell] at [cost]; a cell already in the heap is added again,
  /// and the dearer entry is skipped when it comes up.
  void push(int cell, int cost) {
    if (_size == _cell.length) {
      _cell = Int32List(_size * 2)..setRange(0, _size, _cell);
      _cost = Int32List(_size * 2)..setRange(0, _size, _cost);
    }
    var i = _size++;
    _cell[i] = cell;
    _cost[i] = cost;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_cost[parent] <= _cost[i]) break;
      _swap(parent, i);
      i = parent;
    }
  }

  /// Removes and answers the cheapest cell, its cost in [poppedCost]. The
  /// heap must not be empty.
  int pop() {
    final top = _cell[0];
    poppedCost = _cost[0];
    _size--;
    if (_size > 0) {
      _cell[0] = _cell[_size];
      _cost[0] = _cost[_size];
      var i = 0;
      while (true) {
        final left = i * 2 + 1;
        if (left >= _size) break;
        final right = left + 1;
        var small = left;
        if (right < _size && _cost[right] < _cost[left]) small = right;
        if (_cost[i] <= _cost[small]) break;
        _swap(i, small);
        i = small;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final cell = _cell[a];
    _cell[a] = _cell[b];
    _cell[b] = cell;
    final cost = _cost[a];
    _cost[a] = _cost[b];
    _cost[b] = cost;
  }
}
