/// The modes, and the tools each of them offers.
///
/// **One table, read by four things.** The rail on a desktop, the palette on a
/// tablet, the sheet on a phone and the keyboard all show the same set of
/// tools, and every one of them would otherwise be a second place where a
/// tool's name, icon and shortcut are written down. The rule `ui-07` states is
/// that there is one source: this file. A tool missing from the rail because
/// somebody added it to the palette is a bug that cannot happen if there is
/// nowhere else to add it.
///
/// **No commands here, and that is on purpose.** A tool names what it does with
/// an [id]; what it *does* is one `switch` in `mesh_session.dart` today and a
/// command against a `ModelProject` when there is one. Putting a callback in
/// the table would spread that decision across every row and would have to be
/// unpicked the day the document arrives.
///
/// **Only tools that do something are in it.** Inset, bevel and merge are
/// modelling operations this repository does not have yet — merge exists but
/// hands back a new mesh, which would throw the undo history away — and a rail
/// full of buttons that answer nothing is the fastest way to make a tool feel
/// broken. They arrive here when the operation behind them does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The tools that wait for a pointer instead of acting when pressed.
///
/// A set rather than a check at the call site, so that the shell can ask
/// whether a button arms or acts without knowing what any of them do — and so a
/// tool added to the table without a case behind it is a name in one place
/// rather than a button that silently does nothing.
const Set<String> kDragTools = <String>{
  'object.move',
  'object.rotate',
  'object.scale',
  'mesh.move',
  'mesh.rotate',
  'mesh.scale',
};

/// What the modeller is being used for.
///
/// **All eight are here and two of them work**, which is deliberate: a person
/// opening this should be able to see what the thing is going to be, and a mode
/// that is missing entirely reads as a mode that was never planned. The rest
/// are shown disabled, with the phase they arrive in — see [ModelerMode.phase].
enum ModelerMode {
  object('Object', Icons.category_outlined, 1),
  mesh('Mesh', Icons.hexagon_outlined, 1),
  material('Material', Icons.palette_outlined, 2),
  uv('UV', Icons.grid_on_outlined, 4),
  sculpt('Sculpt', Icons.brush_outlined, 4),
  animation('Animation', Icons.animation_outlined, 3),
  render('Render', Icons.camera_outlined, 4),
  scene('Scene', Icons.light_mode_outlined, 2);

  const ModelerMode(this.label, this.icon, this.phase);

  /// English, and not through `l10n` yet: the strings move to `app_en.arb` and
  /// `app_ru.arb` in `ui-22`, and moving them one at a time as each screen
  /// lands is how half a interface ends up translated.
  final String label;

  final IconData icon;

  /// Which phase of the plan brings this mode to life. Anything past one is
  /// drawn and refused.
  final int phase;

  /// Whether this mode does anything yet.
  bool get isReady => phase <= 1;
}

/// What a sub-mode is: the element level a mesh is edited at.
///
/// Only the mesh mode has one, which is why this is its own enum rather than a
/// field every mode carries. `Selection` in `flutter3d_mesh` has the same three
/// levels; they are not the same type on purpose — that one is a fact about a
/// mesh and this is a state of the interface, and the day a fourth level
/// arrives in one of them it will not arrive in the other.
enum MeshSubmode {
  vertex('Vertex', Icons.scatter_plot_outlined, LogicalKeyboardKey.digit1),
  edge('Edge', Icons.timeline_outlined, LogicalKeyboardKey.digit2),
  face('Face', Icons.pentagon_outlined, LogicalKeyboardKey.digit3);

  const MeshSubmode(this.label, this.icon, this.shortcut);

  final String label;
  final IconData icon;
  final LogicalKeyboardKey shortcut;
}

/// One button, wherever it is shown.
@immutable
final class ModelerTool {
  const ModelerTool({
    required this.id,
    required this.label,
    required this.icon,
    required this.shortcut,
    required this.group,
  });

  /// What this tool is, for the rest of the application. Stable across a
  /// rename of the label, which is the point of having it.
  final String id;

  final String label;
  final IconData icon;

  /// The key that arms it. One key, not a combination: the modelling keys are
  /// single letters because a hand rests on them, and the combinations belong
  /// to the application-wide actions — save, undo, export.
  final LogicalKeyboardKey shortcut;

  /// Tools of one group are drawn together with a divider between groups.
  final String group;
}

/// The tools of [mode], in the order they are shown.
///
/// A list rather than a map, because the order *is* part of the design: the
/// thing a person reaches for most is at the top of the rail, and a map would
/// leave that to whatever the iteration order happens to be.
List<ModelerTool> toolsFor(ModelerMode mode) => switch (mode) {
  ModelerMode.object => const <ModelerTool>[
    ModelerTool(
      id: 'object.select',
      label: 'Select',
      icon: Icons.near_me_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.move',
      label: 'Move',
      icon: Icons.open_with_outlined,
      shortcut: LogicalKeyboardKey.keyG,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.rotate',
      label: 'Rotate',
      icon: Icons.rotate_90_degrees_ccw_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.scale',
      label: 'Scale',
      icon: Icons.aspect_ratio_outlined,
      shortcut: LogicalKeyboardKey.keyS,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.add',
      label: 'Add a box',
      icon: Icons.add_box_outlined,
      shortcut: LogicalKeyboardKey.keyA,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.duplicate',
      label: 'Duplicate',
      icon: Icons.copy_all_outlined,
      shortcut: LogicalKeyboardKey.keyD,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.bake',
      label: 'Convert to a mesh',
      icon: Icons.change_circle_outlined,
      shortcut: LogicalKeyboardKey.keyB,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.delete',
      label: 'Delete',
      icon: Icons.backspace_outlined,
      shortcut: LogicalKeyboardKey.keyX,
      group: 'cleanup',
    ),
  ],
  ModelerMode.mesh => const <ModelerTool>[
    ModelerTool(
      id: 'mesh.select',
      label: 'Select',
      icon: Icons.near_me_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.move',
      label: 'Move',
      icon: Icons.open_with_outlined,
      shortcut: LogicalKeyboardKey.keyG,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.rotate',
      label: 'Rotate',
      icon: Icons.rotate_90_degrees_ccw_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.scale',
      label: 'Scale',
      icon: Icons.aspect_ratio_outlined,
      shortcut: LogicalKeyboardKey.keyS,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.extrude',
      label: 'Extrude',
      icon: Icons.upload_outlined,
      shortcut: LogicalKeyboardKey.keyE,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.loopCut',
      label: 'Loop cut',
      icon: Icons.content_cut_outlined,
      shortcut: LogicalKeyboardKey.keyC,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.triangulate',
      label: 'Triangulate',
      icon: Icons.change_history_outlined,
      shortcut: LogicalKeyboardKey.keyT,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.dissolve',
      label: 'Dissolve edges',
      icon: Icons.remove_outlined,
      shortcut: LogicalKeyboardKey.keyV,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.merge',
      label: 'Merge by distance',
      icon: Icons.compress_outlined,
      shortcut: LogicalKeyboardKey.keyM,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.normals',
      label: 'Recalculate normals',
      icon: Icons.north_outlined,
      shortcut: LogicalKeyboardKey.keyN,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.flip',
      label: 'Flip normals',
      icon: Icons.south_outlined,
      shortcut: LogicalKeyboardKey.keyF,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.delete',
      label: 'Delete',
      icon: Icons.backspace_outlined,
      shortcut: LogicalKeyboardKey.keyX,
      group: 'cleanup',
    ),
  ],
  // Every mode past phase one is drawn on the bar and refused, so there is
  // nothing to offer. Returning an empty list rather than throwing, because a
  // rail asking a disabled mode what it holds is not a bug.
  _ => const <ModelerTool>[],
};
