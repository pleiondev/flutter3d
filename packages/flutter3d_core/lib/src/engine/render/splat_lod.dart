/// Choosing how much of a splat tree to draw — `C7`.
///
/// **A cut through the tree under a budget.** A cut is a set of nodes that
/// covers the cloud once: every leaf has exactly one node of the cut above it
/// or is in it itself. Drawing a cut draws the whole cloud, coarsely where
/// the cut stays high and exactly where it reaches the leaves. [SplatLod]
/// grows one from the root, always refining the node that looks biggest from
/// the eye next — a priority queue on a node's radius over its distance —
/// and refines a node only when its children fit in what is left of the
/// budget. So the cut never exceeds the budget, and once the budget covers
/// the whole cloud every node refines and the cut is the leaves: the
/// original splats, nothing merged.
///
/// **A node is never more splats than its children together**, since a
/// merge makes at most one splat per splat it merges; that is what makes
/// "refine while it fits" safe — no partial cut costs more than the leaves
/// under it.
///
/// **Chosen when the cloud is re-sorted, not every frame.** `SplatQuads`
/// calls [SplatLod.choose] exactly when it would sort anyway — the eye moved
/// far enough, the cloud moved, a page arrived or the budget changed — so the
/// cut costs a heap walk over the visible top of the tree on the frames that
/// already pay for a sort, and nothing on the others.
///
/// **Streaming falls out of the same walk.** A node whose children have not
/// all arrived stays in the cut as it is, and its missing children are asked
/// for ([PagedSplatOctree.request]) in the order the walk reached them — the
/// most visible first. When a page lands the tree's `pageVersion` moves, the
/// next frame re-sorts, and the cut goes one level deeper there.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../formats/splat/splat_cloud.dart';
import '../../formats/splat/splat_octree.dart';
import '../../formats/splat/splat_paged.dart';

/// Draws a splat tree at a budget — what `SplatQuads.lod` takes in place of
/// a single cloud.
final class SplatLod {
  SplatLod(this.tree, {required this.budget, this.pages})
    : assert(pages == null || identical(pages.tree, tree));

  /// A tree whose pages arrive on request, drawn as far as it has arrived.
  SplatLod.paged(PagedSplatOctree pages, {required int budget})
    : this(pages.tree, budget: budget, pages: pages);

  final SplatOctree tree;

  /// Where missing pages are asked for; null when every page is loaded.
  final PagedSplatOctree? pages;

  /// The most splats a cut may hold. A budget below the root's own count
  /// draws nothing, since there is no coarser cut to offer.
  int budget;

  /// The nodes of the last cut, in the order the walk settled them.
  List<int> get cut => _cut;
  List<int> _cut = const <int>[];

  /// How many splats the last cut holds; never more than [budget].
  int get cutSplatCount => _cutCount;
  int _cutCount = 0;

  // The heap, as parallel arrays: a node and its priority.
  Int32List _heapNodes = Int32List(64);
  Float64List _heapKeys = Float64List(64);
  int _heapSize = 0;

  // The assembled cloud's storage, grown to the largest cut drawn.
  Float32List _centres = Float32List(0);
  Float32List _colours = Float32List(0);
  Float32List _scales = Float32List(0);
  Float32List _rotations = Float32List(0);

  /// Chooses the cut for an eye at [eye], in the tree's own space, and
  /// returns it as one cloud — views over storage this reuses, valid until
  /// the next call.
  SplatCloud choose(Vector3 eye) {
    final nodes = tree.nodes;
    final root = nodes.first;
    final cut = <int>[];
    var used = 0;
    _heapSize = 0;

    if (root.isLoaded && root.splatCount <= budget) {
      used = root.splatCount;
      _push(0, _priority(root, eye));
      while (_heapSize > 0) {
        final index = _pop();
        final node = nodes[index];
        final refined = node.isLeaf ? null : _refine(node, used);
        if (refined == null) {
          cut.add(index);
          continue;
        }
        used += refined;
        for (var c = 0; c < node.childCount; c++) {
          final child = node.firstChild + c;
          _push(child, _priority(nodes[child], eye));
        }
      }
    }

    _cut = cut;
    _cutCount = used;
    return _assemble(cut, used);
  }

  /// What refining [node] adds to the cut, or null if it stays: a child
  /// still to arrive (asked for here), or children that do not fit.
  int? _refine(SplatOctreeNode node, int used) {
    final children = tree.nodes
        .getRange(node.firstChild, node.firstChild + node.childCount)
        .toList();
    final extra =
        children.fold(0, (int sum, SplatOctreeNode c) => sum + c.splatCount) -
        node.splatCount;
    // Only pages the budget could draw are worth asking for.
    if (used + extra > budget) return null;
    if (children.every((SplatOctreeNode c) => c.isLoaded)) return extra;
    for (var c = 0; c < children.length; c++) {
      if (!children[c].isLoaded) pages?.request(node.firstChild + c);
    }
    return null;
  }

  /// How large [node] looks from [eye]: its radius over its distance, with
  /// a node the eye is inside always first.
  static double _priority(SplatOctreeNode node, Vector3 eye) {
    final dx = node.x - eye.x, dy = node.y - eye.y, dz = node.z - eye.z;
    final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
    return node.radius / math.max(distance - node.radius, 1e-9 * node.radius);
  }

  SplatCloud _assemble(List<int> cut, int count) {
    if (_centres.length < count * 3) {
      _centres = Float32List(count * 3);
      _colours = Float32List(count * 4);
      _scales = Float32List(count * 3);
      _rotations = Float32List(count * 4);
    }
    var at = 0;
    for (final index in cut) {
      final splats = tree.nodes[index].splats!;
      final n = splats.count;
      _centres.setRange(at * 3, (at + n) * 3, splats.centres);
      _colours.setRange(at * 4, (at + n) * 4, splats.colours);
      _scales.setRange(at * 3, (at + n) * 3, splats.scales);
      _rotations.setRange(at * 4, (at + n) * 4, splats.rotations);
      at += n;
    }
    return SplatCloud(
      centres: Float32List.sublistView(_centres, 0, count * 3),
      colours: Float32List.sublistView(_colours, 0, count * 4),
      scales: Float32List.sublistView(_scales, 0, count * 3),
      rotations: Float32List.sublistView(_rotations, 0, count * 4),
    );
  }

  void _push(int node, double key) {
    if (_heapSize == _heapNodes.length) {
      _heapNodes = Int32List(_heapSize * 2)..setAll(0, _heapNodes);
      _heapKeys = Float64List(_heapSize * 2)..setAll(0, _heapKeys);
    }
    var i = _heapSize++;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_heapKeys[parent] >= key) break;
      _heapNodes[i] = _heapNodes[parent];
      _heapKeys[i] = _heapKeys[parent];
      i = parent;
    }
    _heapNodes[i] = node;
    _heapKeys[i] = key;
  }

  int _pop() {
    final top = _heapNodes[0];
    final lastNode = _heapNodes[--_heapSize];
    final lastKey = _heapKeys[_heapSize];
    var i = 0;
    while (true) {
      final left = 2 * i + 1;
      if (left >= _heapSize) break;
      final right = left + 1;
      final larger = right < _heapSize && _heapKeys[right] > _heapKeys[left]
          ? right
          : left;
      if (_heapKeys[larger] <= lastKey) break;
      _heapNodes[i] = _heapNodes[larger];
      _heapKeys[i] = _heapKeys[larger];
      i = larger;
    }
    _heapNodes[i] = lastNode;
    _heapKeys[i] = lastKey;
    return top;
  }
}
