/// What the retopology, simulation and render panels remember between
/// builds — `ui-37d`'s own tail, the same move [SculptBrush] and [PaintBrush]
/// make and for the same reason.
///
/// **Three classes in one file, unlike the two brushes.** Each of these is a
/// handful of fields nothing outside its own panel reads, and a file apiece
/// would be three doc comments saying the same sentence. The brushes earned
/// their own files by being read from the pointer wiring as well as from a
/// panel — two callers, and a diameter that had been misnamed a radius in
/// both.
///
/// None of these is on `ModelHistory`: they are what a panel is showing, not
/// what the document says, so undo has nowhere to put any of them back to.
library;

import 'dart:ui' as ui;

import 'ui/bake_panel.dart' show BakeProgress;
import 'ui/render_panel.dart' show RenderPassRow;
import 'ui/simulation_panel.dart' show SimulationCacheState;

/// `pro-rt-07`: the retopology target, which maps are ticked, how big they
/// bake, and the job running now.
final class RetopoPanelState {
  int quads = 4000;
  final Set<String> bakeMaps = <String>{'normal'};
  int bakeResolution = 1024;
  BakeProgress? baking;
}

/// `pro-sim-06`: what is being simulated, what it collides with, what holds
/// it up, and where the transport is.
final class SimulationPanelState {
  String kind = 'cloth';
  Map<String, double> parameters = const <String, double>{
    'stiffness': 0.6,
    'damping': 0.1,
  };
  final Set<String> colliders = <String>{};
  Set<int> pinned = <int>{};
  SimulationCacheState cache = (frames: 0, baked: 0, running: false);
  int frame = 0;
  bool playing = false;
}

/// `pro-rn-04`: the composite chain, the last result, and the tiles still to
/// come.
final class RenderPanelState {
  List<RenderPassRow> passes = const <RenderPassRow>[
    (name: 'scene', enabled: true, fixed: true),
    (name: 'ssao', enabled: true, fixed: false),
    (name: 'reflections', enabled: false, fixed: false),
    (name: 'bloom', enabled: true, fixed: false),
    (name: 'tonemap', enabled: true, fixed: false),
    (name: 'look', enabled: false, fixed: false),
    (name: 'output', enabled: true, fixed: true),
  ];
  ui.Image? result;
  int tilesDone = 0;
  int tilesTotal = 0;
}
