/// The sample plugin's editor half: what the `acme_sample` plugin brings to
/// a level editor, written against the published libraries only.
///
/// - **Hints** (`package:flutter3d_plugin_api/editor.dart`), which need no
///   editor to be written: the `acme_sample.heat` component an ember
///   carries, the `ember` entity kind the scene binding draws, and the
///   parameters of the `acme_sample__Hair` lit model. A game installs the
///   plugin with no editor and the hints are skipped.
/// - **Editor pieces** (`package:flutter3d_editor_core`): a command an
///   agent sees as `acme_sample.stoke` (a plugin's commands, like its MCP
///   tools and every name of the runtime half, are under the package's
///   namespace, not under this half's whole id) — offered to an agent
///   because the manifest declares `PluginPermission.tools`, and as a change
///   that can be undone because its hints say so — a gizmo that rings an
///   ember with its reach and lets the ring be pulled, an importer that
///   brings in a list of embers, and an asset-browser entry for such lists.
///
/// A panel is a widget and lives in `flutter3d_editor_widgets`
/// (`EditorPanels`); this example is plain Dart and brings none.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_plugin_api/editor.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_api/tools.dart' show ToolHints;
import 'package:vector_math/vector_math.dart';

/// The heat an ember carries, as the inspector shows it.
const ComponentHints heatHints = ComponentHints(
  id: 'acme_sample.heat',
  title: 'Heat',
  fields: <FieldHint>[
    FieldHint.number(
      'heat',
      label: 'Temperature',
      min: 273,
      max: 1500,
      step: 1,
      unit: Unit.kelvin,
      defaultValue: 900.0,
    ),
  ],
);

/// An ember, as the palette offers it and the inspector shows it.
const EntityKindHints emberHints = EntityKindHints(
  type: 'ember',
  label: 'Ember',
  tint: LinearColor(1.0, 0.35, 0.08),
  fields: <FieldHint>[
    FieldHint.number(
      'reach',
      label: 'Reach',
      min: 0,
      max: 8,
      unit: Unit.meter,
      defaultValue: 2.0,
    ),
  ],
  components: <String>{'acme_sample.heat'},
);

/// The parameters of the `acme_sample__Hair` lit model, as the material
/// panel shows them for a material that names it.
const MaterialHints hairHints = MaterialHints(
  model: 'acme_sample__Hair',
  fields: <FieldHint>[
    FieldHint.number('gloss', min: 0, max: 1, step: 0.05),
    FieldHint.color('tint'),
    FieldHint.number('shift', min: -0.5, max: 0.5, step: 0.01),
    FieldHint.asset('fur', suffixes: <String>['.png', '.ktx2']),
  ],
);

/// Raises the heat of every ember by [by] kelvin: one step of undo.
final class StokeEmbers extends PluginCommand {
  /// A command raising every ember by [by] kelvin.
  const StokeEmbers(this.by);

  /// Reads one back from a call's arguments; `by` defaults to 100 K.
  static StokeEmbers? read(Map<String, Object?> arguments) =>
      switch (arguments['by'] ?? 100) {
        final num by => StokeEmbers(by.toDouble()),
        _ => null,
      };

  /// How much hotter each ember gets, in kelvin; undoing the command takes the
  /// same amount off again.
  final double by;

  /// The published name: the plugin's namespace and the name it registers
  /// it by, as every editor command and MCP tool of a plugin is.
  @override
  String get name => 'acme_sample.stoke';

  @override
  String get says => 'stoke every ember by $by K';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'by': by};

  @override
  bool apply(Editing editing) {
    final level = editing.level;
    final embers = <int>[
      for (var i = 0; i < level.entities.length; i++)
        if (level.entities[i].type == 'ember') i,
    ];
    for (final index in embers) {
      final heat =
          level.entities[index].number('heat') ??
          (heatHints.fields.single.defaultValue! as double);
      editing
        ..kind = Piece.entity
        ..selected = index
        ..setField('heat', heat + by);
    }
    return embers.isNotEmpty;
  }
}

/// Rings an ember with its reach; the ring's handle sets the reach.
final class EmberReach extends EditorGizmo {
  /// The gizmo; it holds nothing, and reads the ember it rings from the
  /// context it is handed.
  const EmberReach();

  @override
  bool appliesTo(GizmoContext context) => context.entity?.type == 'ember';

  @override
  List<GizmoMark> marksFor(GizmoContext context) => <GizmoMark>[
    GizmoMark.ball(
      context.where,
      radius: context.entity!.number('reach') ?? 2.0,
      tint: const LinearColor(1.0, 0.5, 0.1),
      handle: 'reach',
    ),
  ];

  @override
  DocumentCommand? dragged(GizmoDrag drag) =>
      SetField('reach', drag.to.distanceTo(drag.target.where));
}

/// Brings in a `.embers` file: one ember a line, `x y z heat`, placed in
/// the level, and the file kept under `assets/embers/`.
final class EmberImporter extends EditorImporter {
  /// The importer; it holds nothing.
  const EmberImporter();

  @override
  String get label => 'Ember list';

  @override
  List<String> get suffixes => const <String>['.embers'];

  @override
  Future<ImportResult> import(ImportRequest request) async {
    final commands = <DocumentCommand>[];
    final notes = <String>[];
    final lines = const LineSplitter().convert(utf8.decode(request.bytes));
    for (final (index, line) in lines.indexed) {
      final numbers = line.trim().split(RegExp(r'\s+')).map(double.tryParse);
      if (line.trim().isEmpty) continue;
      if (numbers.length != 4 || numbers.any((double? n) => n == null)) {
        notes.add('line ${index + 1} is not "x y z heat": left out');
        continue;
      }
      final [x, y, z, heat] = numbers.cast<double>().toList();
      // A placed ember copies one the level has; its own heat is then set
      // on it, the one just placed being what is selected.
      commands
        ..add(
          Place(
            Piece.entity,
            'ember',
            Vector3(x, y, z),
            properties: <String, Object?>{'heat': heat, 'reach': 2.0},
          ),
        )
        ..add(SetField('heat', heat));
    }
    return ImportResult(
      files: <String, Uint8List>{
        'assets/embers/${request.name}': request.bytes,
      },
      commands: commands,
      notes: <String>['${commands.length ~/ 2} embers', ...notes],
    );
  }
}

/// The editor half of the sample plugin.
final class AcmeEditorPlugin extends Flutter3dPlugin {
  @override
  PluginManifest get manifest => PluginManifest(
    id: 'acme_sample.editor',
    apiVersion: const PluginApiVersion(1, 0),
    // Tooling only: the editor and its tools. A game need not install it,
    // and a run made with it installed carries nothing of it.
    touches: PluginTouches.tooling,
    // Its `stoke` command reaches an agent as a tool of its own.
    permissions: <PluginPermission>{PluginPermission.tools},
    description: 'What the sample brings to a level editor.',
  );

  @override
  void install(PluginHost host) {
    host.maybeRegistry<EditorHintRegistry>()
      ?..addComponent(heatHints)
      ..addEntityKind(emberHints)
      ..addMaterial(hairHints);
    host.maybeRegistry<EditorPieces>()
      ?..addCommand(
        'stoke',
        StokeEmbers.read,
        description: 'Raise the heat of every ember.',
        arguments: const <FieldHint>[
          FieldHint.number('by', unit: Unit.kelvin, defaultValue: 100.0),
        ],
        // An undo takes it back: it changes, and destroys nothing.
        hints: ToolHints.writes,
      )
      ..addGizmo('reach', const EmberReach())
      ..addImporter('embers', const EmberImporter())
      ..addAssetEntry(
        'embers',
        const AssetBrowserEntry(
          label: 'Ember list',
          suffixes: <String>['.embers'],
        ),
      );
  }
}
