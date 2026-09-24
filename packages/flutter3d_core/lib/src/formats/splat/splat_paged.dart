/// Loading a splat tree a page at a time — `C7`.
///
/// **Range requests, so a viewer starts drawing before the capture has
/// arrived.** A tree file is a header, a node table and then every node's
/// splats as one contiguous page, coarse levels first (`splat_octree.dart`).
/// [PagedSplatOctree.open] reads the header and the table — two small
/// requests — and the root's page; after that a page is fetched only when
/// `SplatLod` wants to draw finer than what has arrived, so a distant cloud
/// on a slow connection costs the pages it is seen at and no more.
///
/// **The fetching is the caller's.** A [SplatRangeReader] is one function
/// from a byte range to its bytes: an HTTP `Range:` request, a
/// `RandomAccessFile`, or a slice of bytes already in memory
/// ([splatBytesReader]). This package depends on no network library, and a
/// reader is the whole of what it needs from one.
library;

import 'dart:async';
import 'dart:typed_data';

import 'splat_octree.dart';

/// Reads [length] bytes of the tree file starting at [offset].
typedef SplatRangeReader = Future<Uint8List> Function(int offset, int length);

/// A [SplatRangeReader] over a file already in memory — for tests, and for
/// a caller that has the whole file but wants the paged path anyway.
SplatRangeReader splatBytesReader(Uint8List bytes) =>
    (int offset, int length) async =>
        Uint8List.sublistView(bytes, offset, offset + length);

/// A splat tree whose pages arrive on request.
final class PagedSplatOctree {
  PagedSplatOctree._(this.tree, this._read, this.maxInFlight);

  /// Reads the header, the node table and the root's page through [read].
  ///
  /// [maxInFlight] caps how many page requests run at once: the cut asks for
  /// pages in the order it wants them, the most visible first, and a cap
  /// keeps a sudden camera move from queueing the whole tree ahead of the
  /// pages it now needs most.
  static Future<PagedSplatOctree> open(
    SplatRangeReader read, {
    int maxInFlight = 4,
  }) async {
    final header = await read(0, kSplatOctreeHeaderBytes);
    final table = await read(
      kSplatOctreeHeaderBytes,
      splatOctreeIndexBytes(header) - kSplatOctreeHeaderBytes,
    );
    final index = Uint8List(header.length + table.length)
      ..setAll(0, header)
      ..setAll(header.length, table);
    final paged = PagedSplatOctree._(
      parseSplatOctreeIndex(index),
      read,
      maxInFlight,
    ).._bytesRead = index.length;
    await paged._fetch(0);
    return paged;
  }

  /// The tree, with a page attached to every node that has arrived.
  final SplatOctree tree;

  final SplatRangeReader _read;

  /// The most page requests outstanding at once.
  final int maxInFlight;

  final Set<int> _inFlight = <int>{};

  /// Bytes read so far, header and table included — what a test holds a
  /// small budget's cut to.
  int get bytesRead => _bytesRead;
  int _bytesRead = 0;

  /// Called after every page is attached; `SplatQuads` does not need it —
  /// it watches [SplatOctree.pageVersion] — but a widget that only repaints
  /// when asked does.
  void Function(int node)? onPage;

  /// The last page request that failed, if one has.
  Object? lastError;

  /// Every page request not yet answered, for a caller that wants to wait.
  Future<void> get idle => Future.wait(_pending.values);
  final Map<int, Future<void>> _pending = <int, Future<void>>{};

  /// Asks for node [index]'s page, unless it is here, on its way, or
  /// [maxInFlight] requests already are. Returns whether it was asked for.
  bool request(int index) {
    if (tree.nodes[index].isLoaded || _inFlight.contains(index)) return false;
    if (_inFlight.length >= maxInFlight) return false;
    // A page that fails is kept rather than thrown into nobody's zone: the
    // node stays unloaded, the cut stays above it, and a later walk asks
    // again.
    _pending[index] = _fetch(index).catchError((Object error) {
      lastError = error;
    });
    return true;
  }

  Future<void> _fetch(int index) async {
    final node = tree.nodes[index];
    final length = node.splatCount * kSplatPageBytesPerSplat;
    _inFlight.add(index);
    try {
      final bytes = await _read(node.pageOffset, length);
      _bytesRead += length;
      tree.attach(index, decodeSplatPage(bytes, node.splatCount));
      onPage?.call(index);
    } finally {
      _inFlight.remove(index);
      _pending.remove(index)?.ignore();
    }
  }
}
