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
  /// How many quads the retopology aims at.
  int quads = 4000;

  /// Which maps the bake writes, by name; the bake is refused while this is
  /// empty.
  final Set<String> bakeMaps = <String>{'normal'};

  /// The side of each baked map, in pixels.
  int bakeResolution = 1024;

  /// The bake running now, with its label and how far it has got, or null.
  BakeProgress? baking;
}

/// `pro-sim-06`: what is being simulated, what it collides with, what holds
/// it up, and where the transport is.
final class SimulationPanelState {
  /// What is simulated: `cloth`, `rigid` or `particles`, the panel's chips.
  String kind = 'cloth';

  /// The current kind's parameters by name: stiffness and damping for cloth,
  /// mass and friction for a rigid body, rate and lifetime for particles.
  /// Replaced wholesale with the new kind's defaults when [kind] changes.
  Map<String, double> parameters = const <String, double>{
    'stiffness': 0.6,
    'damping': 0.1,
  };

  /// The names of the objects the simulation collides with.
  final Set<String> colliders = <String>{};

  /// The vertices held still, from the selection that pinned them.
  Set<int> pinned = <int>{};

  /// How much of the run is cached, and whether it is being filled now.
  SimulationCacheState cache = (frames: 0, baked: 0, running: false);

  /// The frame the strip is showing.
  int frame = 0;

  /// Whether the strip is playing the cache.
  bool playing = false;
}

/// `pro-rn-04`: the composite chain, the last result, and the tiles still to
/// come.
final class RenderPanelState {
  /// The composite chain in order, each pass on or off; `scene` and `output`
  /// are fixed and cannot be switched off.
  List<RenderPassRow> passes = const <RenderPassRow>[
    (name: 'scene', enabled: true, fixed: true),
    (name: 'ssao', enabled: true, fixed: false),
    (name: 'reflections', enabled: false, fixed: false),
    (name: 'bloom', enabled: true, fixed: false),
    (name: 'tonemap', enabled: true, fixed: false),
    (name: 'look', enabled: false, fixed: false),
    (name: 'output', enabled: true, fixed: true),
  ];

  /// The last finished render, or null before the first one.
  ui.Image? result;

  /// How many tiles of the render in progress are done.
  int tilesDone = 0;

  /// How many tiles the render in progress has, the square of the tiles
  /// along one side.
  int tilesTotal = 0;
}
