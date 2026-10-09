/// The editor's docked panels, and the side each docks to until somebody
/// moves it.
///
/// The palette and the outliner down the left — what the level can be made
/// of, and what it is made of; the inspector, the material panel and the
/// step panel down the right — what the selected thing is; the console and
/// the render graph along the bottom — what happened, and what the last
/// frame cost. Each but the last three is a panel that used to float over
/// the level, given the room it takes instead of covering the picture.
///
/// [pieces] is what the installed plugins brought: their palette entries are
/// rows of the palette and their components sections of the inspector.
///
/// A function of its own, outside the screen's state, so the panels can be
/// docked and laid out in a test with no device under them — the screen
/// itself cannot be built without one.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show FrameResult;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_play/attach.dart' show PlayedGame;
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart'
    show DockPanel, DockSide;

import 'console_panel.dart';
import 'editor_cubit.dart';
import 'editor_inspector.dart';
import 'editor_palette.dart';
import 'material_panel.dart';
import 'outliner.dart';
import 'render_graph_view.dart';
import 'step_panel.dart';

List<DockPanel> editorPanels({
  required EditorReady state,
  required EditorLog log,
  required PlayedGame? game,
  required FrameResult? frame,
  required void Function(Picked picked, {required bool add}) onSelect,
  required ValueChanged<Picked> onFlyTo,
  required void Function(String what) onChanged,
  required void Function(String material, Map<String, Object?> fields) onLive,
  EditorPieces? pieces,
}) => <DockPanel>[
  DockPanel(
    id: 'outliner',
    title: 'Outliner',
    icon: Icons.account_tree_outlined,
    side: DockSide.left,
    builder: (_) =>
        Outliner(editing: state.editing, onSelect: onSelect, onFrame: onFlyTo),
  ),
  DockPanel(
    id: 'place',
    title: 'Place',
    icon: Icons.add_box_outlined,
    side: DockSide.left,
    builder: (_) => EditorPalette(state: state, width: null, pieces: pieces),
  ),
  DockPanel(
    id: 'inspector',
    title: 'Inspector',
    icon: Icons.tune,
    side: DockSide.right,
    builder: (_) =>
        EditorInspector(state: state, onChanged: onChanged, pieces: pieces),
  ),
  // `HR4`: a value dragged here reaches a running game at once; a value
  // written is the level's, as any.
  DockPanel(
    id: 'materials',
    title: 'Materials',
    icon: Icons.palette_outlined,
    side: DockSide.right,
    builder: (_) => SingleChildScrollView(
      child: MaterialPanel(
        editing: state.editing,
        onChanged: onChanged,
        onLive: onLive,
      ),
    ),
  ),
  // `edu-01`: a step panel selects; the inspector still edits whatever that
  // selects, field by field, the same as it does for any other entity.
  DockPanel(
    id: 'steps',
    title: 'Steps',
    icon: Icons.view_list_outlined,
    side: DockSide.right,
    builder: (_) => StepPanel(editing: state.editing, onChanged: onChanged),
  ),
  DockPanel(
    id: 'console',
    title: 'Console',
    icon: Icons.terminal,
    side: DockSide.bottom,
    builder: (_) => ConsolePanel(log: log, game: game),
  ),
  DockPanel(
    id: 'graph',
    title: 'Render graph',
    icon: Icons.account_tree,
    side: DockSide.bottom,
    builder: (_) => RenderGraphView(frame: frame),
  ),
];
