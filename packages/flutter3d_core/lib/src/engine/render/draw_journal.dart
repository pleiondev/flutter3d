/// Every draw of one frame, written down as it was encoded — `P12`.
///
/// **Why a journal beside the counters, and why it is off.** `gfx-01n` gave
/// each pass its draw count, and the count says a pass drew forty things
/// without saying which forty. A tool asking "is the crate drawn at all, and
/// with which material" needs the list, and the list costs an allocation per
/// draw — exactly the cost the counters were designed to avoid. So the
/// journal exists for the one frame somebody asked about
/// (`Renderer.captureNextFrame(draws: true)`) and is null in every other one;
/// each site writes through `state.journal?.add(...)`, whose arguments Dart
/// does not evaluate when the journal is null, so an ordinary frame pays one
/// null check per draw and builds nothing.
///
/// **Not every draw is described.** The mesh encoder and the shadow casters
/// know a node and a material and record them; a full-screen triangle in a
/// post pass knows neither, and inventing a "mesh" for it would make the list
/// look more complete than it is. Those are counted per pass in
/// [DrawJournal.undetailed] instead — the pass's own draw count minus what it
/// described — so the total still adds up to what the pass reported.
library;

import 'dart:typed_data';

/// One draw, as the encoder saw it.
final class DrawRecord {
  const DrawRecord({
    required this.index,
    required this.passIndex,
    required this.pass,
    required this.kind,
    required this.mesh,
    required this.material,
    required this.lighting,
    required this.vertices,
    required this.indices,
    required this.instances,
    required this.triangles,
    required this.state,
    required this.uniforms,
    this.node,
  });

  /// Position in the frame, across every pass.
  final int index;

  /// The graph node that encoded it, by position and by name.
  final int passIndex;
  final String pass;

  /// `mesh` for the scene's own encoder, `shadow` for a caster.
  final String kind;

  /// The node's name — a mesh has none of its own — or null when unnamed.
  final String? mesh;
  final String? material;

  /// The lighting model's label: which pipeline drew it.
  final String lighting;

  final int vertices;
  final int indices;
  final int instances;
  final int triangles;

  /// Pipeline state the draw was encoded with: cull, blend, depth, winding,
  /// and the variant flags that pick a pipeline.
  final Map<String, Object?> state;

  /// The values bound for this draw, by name — matrices column-major.
  final Map<String, List<double>> uniforms;

  /// The scene node that was drawn — not its name, which a level gives to
  /// a dozen torches — so [Renderer.pickPixel]'s answer can be found among
  /// the frame's draws. Null for a draw that is not one node's, such as a
  /// contributor's.
  final Object? node;

  /// The row a list shows.
  Map<String, Object?> toSummaryJson() => <String, Object?>{
    'index': index,
    'passIndex': passIndex,
    'pass': pass,
    'kind': kind,
    'mesh': mesh,
    'material': material,
    'vertices': vertices,
    'indices': indices,
    'instances': instances,
  };

  /// Everything.
  Map<String, Object?> toJson() => <String, Object?>{
    ...toSummaryJson(),
    'lighting': lighting,
    'triangles': triangles,
    'state': state,
    'uniforms': uniforms,
  };
}

/// Collects [DrawRecord]s while one frame runs.
final class DrawJournal {
  final List<DrawRecord> _records = <DrawRecord>[];
  final Map<String, int> _undetailed = <String, int>{};

  int _passIndex = -1;
  String _pass = '';
  int _passStart = 0;

  List<DrawRecord> get records => List<DrawRecord>.unmodifiable(_records);

  /// Draws a pass counted and did not describe, by pass name; passes that
  /// described every draw are absent.
  Map<String, int> get undetailed => Map<String, int>.unmodifiable(_undetailed);

  /// Called by the renderer before a graph node runs.
  void beginPass(int index, String name) {
    _passIndex = index;
    _pass = name;
    _passStart = _records.length;
  }

  /// Called by the renderer after the node, with the draws it counted.
  void endPass(int drawCalls) {
    final missing = drawCalls - (_records.length - _passStart);
    if (missing > 0) _undetailed[_pass] = missing;
  }

  /// Writes one draw down. Call as `journal?.add(...)`, so nothing below is
  /// evaluated in a frame that is not being journaled.
  void add({
    required String kind,
    required String? mesh,
    required String? material,
    required String lighting,
    required int vertices,
    required int indices,
    required int instances,
    required Map<String, Object?> state,
    Map<String, Float32List> uniforms = const <String, Float32List>{},
    Object? node,
  }) {
    _records.add(
      DrawRecord(
        index: _records.length,
        passIndex: _passIndex,
        pass: _pass,
        kind: kind,
        mesh: mesh,
        material: material,
        lighting: lighting,
        vertices: vertices,
        indices: indices,
        instances: instances,
        triangles: (indices ~/ 3) * instances,
        state: Map<String, Object?>.unmodifiable(state),
        // Copied: the renderer refills its staging blocks for the next draw.
        uniforms: <String, List<double>>{
          for (final MapEntry(:key, :value) in uniforms.entries)
            key: List<double>.unmodifiable(value),
        },
        node: node,
      ),
    );
  }
}
