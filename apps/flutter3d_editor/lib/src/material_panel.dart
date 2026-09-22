/// The level's materials, and every field of the one being looked at.
///
/// **The half of the format the inspector could not reach.** `EditorInspector`
/// edits whatever is *selected*, and a selection is a brush, a light or an
/// entity — see `Piece`, which explains at length why a material is not a
/// fourth one. So a level's materials, which are what every brush in it points
/// at, had no panel at all: the editor could name a material on a brush and had
/// no way to say what that material looks like.
///
/// **This one is built from hints, where the inspector is built from types.**
/// The difference is that a material has a schema and a level does not. The
/// engine keeps [builtInMaterialHints] for the fields every material has, and a
/// `.fmat` carries [MaterialDocument.hints] for the parameters only a studio's
/// own shader knows about — so here a range is a slider, a colour is a picker,
/// a path is a file field and a finite set is a list, and none of that is a
/// widget this file chose by looking at what type happened to be in the box.
/// [FieldRow] is shared with the inspector and falls back to the type when
/// nothing hinted the field, which is what keeps the two panels one row.
///
/// **Two gates, because there are two writers and only one of them refuses.**
/// A level material is written back through `Level.fromJson`, which is strict
/// about types and throws — so [setLevelMaterialField] parses and rolls back,
/// exactly as `Editing.setField` does. A `.fmat` is the other case and the
/// reason `flutter3d_editor_core`'s own `materialWith` exists: `readFmat`
/// almost never refuses anything, it *warns* — an unknown alpha mode becomes
/// opaque with a note, a shader it does not ship becomes the scene's — so a
/// panel that wrote straight into a material document would be the one place
/// in this editor that can produce a file which does not say what it appears
/// to say. The editor's whole claim is that it does not write documents that
/// will not load; a writer with no reader behind it does not get to make that
/// claim, so this one puts the reader behind it. `materialWith`,
/// `materialDocumentFields` and `materialDocumentHint` moved to
/// `flutter3d_editor_core` (mat-03) once `MaterialDocument` left `flutter3d`
/// for `flutter3d_formats` — the second editor a `.fmat` field ever gets
/// edited from will not have to write the gate again.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart'
    show
        MaterialDocument,
        MaterialHint,
        RangeHint,
        TextureHint,
        builtInMaterialHints;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart'
    show SectionLabel;
// For `Level`, which is what a material is written back through. The editor's
// core keeps the document open and does not re-export the format it is in.
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;

import 'editor_inspector.dart';

/// How a control for one field of a *level* material should look.
///
/// **Borrowed from the engine where the two vocabularies agree, written here
/// where they do not.** `baseColor`, `roughness` and `metallic` mean the same
/// thing in a level document as in a `.fmat` and are taken straight from
/// [builtInMaterialHints], so a range that changes there changes here. The rest
/// are the level format's own: `emissive` is the case that proves the borrowing
/// has to be selective, because a level material's is a *strength* and the
/// engine's field of that name is a colour — a panel that had blindly reused
/// the table would have offered a colour picker over a single number.
///
/// This is a table of descriptions, not the hand-written list of *fields* the
/// inspector still needs: the rows come from the material's own document, and
/// a key nothing here describes is shown by its type like any other.
final Map<String, MaterialHint> levelMaterialHints = <String, MaterialHint>{
  'baseColor': builtInMaterialHints['baseColor']!,
  'roughness': builtInMaterialHints['roughness']!,
  'metallic': builtInMaterialHints['metallic']!,
  'emissive': const MaterialHint(
    RangeHint(0.0, 8.0, step: 0.05),
    label: 'Emissive',
    help:
        'How brightly the surface glows in its own colour. Nought is not '
        'lit. Above one is a surface that blows out, which is what a lamp '
        'housing wants and a wall does not.',
  ),
  'texelsPerMetre': const MaterialHint(
    RangeHint(0.125, 8.0, step: 0.125),
    label: 'Texels per metre',
    help: 'How many times the maps repeat across a metre of wall.',
  ),
  'albedo': const MaterialHint(TextureHint(), label: 'Albedo map'),
  'normal': const MaterialHint(
    TextureHint(),
    label: 'Normal map',
    help: 'Tangent space, OpenGL convention — green points up.',
  ),
  'orm': const MaterialHint(
    TextureHint(),
    label: 'ORM map',
    help: 'Occlusion in red, roughness in green, metallic in blue.',
  ),
  'fmat': const MaterialHint(
    TextureHint(extensions: <String>['.fmat']),
    label: 'Material file',
    help:
        'A standalone material this surface defers its whole look to. The '
        'fields above go on describing the surface for anything that cannot '
        'read the file.',
  ),
};

/// Sets one field of one of [editing]'s materials, or refuses.
///
/// The same bargain `Editing.setField` strikes for a brush, and for the same
/// reason: the change is made in the decoded document, the document is read
/// back, and a reading that throws puts the row back and answers false. The
/// level reader is strict about types — a roughness of `"very"` is a
/// `LevelFormatException` rather than a shrug — so this is a real gate and the
/// editor goes on being unable to write a level that will not load.
///
/// Through [Editing.history], so one row written is one step back, named after
/// the material and the field it wrote.
bool setLevelMaterialField(
  Editing editing,
  String material,
  String key,
  Object? value,
) {
  final document = editing.level.toJson();
  final materials = document['materials'];
  if (materials is! Map<String, Object?>) return false;
  final row = materials[material];
  if (row is! Map<String, Object?>) return false;

  final before = Map<String, Object?>.from(row);
  if (value == null) {
    row.remove(key);
  } else {
    row[key] = value;
  }

  final Level rebuilt;
  try {
    rebuilt = Level.fromJson(document);
  } catch (_) {
    row
      ..clear()
      ..addAll(before);
    return false;
  }

  editing.history.remember(
    value == null ? 'clear $material.$key' : 'set $material.$key',
  );
  editing.level = rebuilt;
  return true;
}

/// The materials of a level, and the fields of the one that is open.
final class MaterialPanel extends StatefulWidget {
  const MaterialPanel({
    super.key,
    required this.editing,
    required this.onChanged,
    this.documents = const <String, MaterialDocument>{},
    this.onMaterialWritten,
    this.offers = nothingToOffer,
  });

  final Editing editing;

  /// Called after a field was actually written, naming it, so the screen can
  /// rebuild and the scene can be rebuilt from the document. The inspector's
  /// callback, with the same contract: a refused write tells nobody.
  final void Function(String what) onChanged;

  /// The `.fmat` a level material names, by the material's own name.
  ///
  /// **Handed in rather than read here**, because this file has no disk: the
  /// editor knows where the document it opened came from and a widget does not.
  /// Empty is the ordinary case — no level in this repository names a material
  /// file yet — and then the panel is the level's own fields alone.
  final Map<String, MaterialDocument> documents;

  /// Called with the material whose file changed and the document that came
  /// out. Whoever owns the disk writes it; this panel never does — the same
  /// division that keeps `Editing` able to change a level it cannot save.
  final void Function(String material, MaterialDocument document)?
  onMaterialWritten;

  /// See [PathOffers].
  final PathOffers offers;

  @override
  State<MaterialPanel> createState() => _MaterialPanelState();
}

class _MaterialPanelState extends State<MaterialPanel> {
  /// Which material is open.
  ///
  /// **The panel's own, and deliberately not a selection in the document.**
  /// Nothing else in the editor needs to know: no gizmo draws a material, no
  /// arrow key moves one, no click can hit one. A brush's selection is shared
  /// because four things act on it; this is one panel's scroll position with a
  /// name.
  String? _open;

  /// The open material, or the first one, or null in a level with none.
  String? get _name {
    final names = widget.editing.level.materials.keys;
    final open = _open;
    if (open != null && names.contains(open)) return open;
    return names.isEmpty ? null : names.first;
  }

  @override
  Widget build(BuildContext context) {
    final name = _name;
    if (name == null) return const SizedBox.shrink();
    final material = widget.editing.level.materials[name]!;
    final row = material.toJson();
    final keys = row.keys.toList()..sort();
    final document = widget.documents[name];

    return Container(
      width: 232,
      color: const Color(0xF20D0F12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: DropdownButton<String>(
              value: name,
              isDense: true,
              isExpanded: true,
              dropdownColor: const Color(0xFF171A1F),
              underline: const SizedBox.shrink(),
              style: const TextStyle(
                color: Color(0xFF6F7885),
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
              items: <DropdownMenuItem<String>>[
                for (final it in widget.editing.level.materials.keys)
                  DropdownMenuItem<String>(
                    value: it,
                    child: Text(it.toUpperCase()),
                  ),
              ],
              onChanged: (String? next) => setState(() => _open = next),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final key in keys)
                    FieldRow(
                      key: ValueKey<String>('field:$key'),
                      name: key,
                      value: row[key],
                      hint: levelMaterialHints[key],
                      offers: widget.offers,
                      onWrite: (Object? value) {
                        if (setLevelMaterialField(
                          widget.editing,
                          name,
                          key,
                          value,
                        )) {
                          widget.onChanged('$name.$key');
                        }
                      },
                    ),
                  if (document != null) ..._file(name, document),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The rows of the `.fmat` this material defers to, and its parameters.
  ///
  /// Under a heading rather than mixed in with the level's own fields: the two
  /// go to two different files, and a panel that hid which key it was about to
  /// change is a panel that edits the wrong document.
  List<Widget> _file(String name, MaterialDocument document) {
    final fields = materialDocumentFields(document);
    final keys = fields.keys.toList()..sort();
    final parameters = document.parameters.keys.toList()..sort();
    return <Widget>[
      _heading(document.surface.name ?? 'MATERIAL FILE'),
      for (final key in keys)
        FieldRow(
          key: ValueKey<String>('file:$key'),
          name: key,
          value: fields[key],
          hint: materialDocumentHint(document, key),
          offers: widget.offers,
          onWrite: (Object? value) => _writeFile(name, document, key, value),
        ),
      if (parameters.isNotEmpty) ...<Widget>[
        _heading('PARAMETERS'),
        for (final key in parameters)
          FieldRow(
            key: ValueKey<String>('parameter:$key'),
            name: key,
            // One number rather than a list of one, so a shader's single float
            // gets the slider its hint describes instead of a row of one box.
            value: switch (document.parameters[key]!) {
              [final double only] => only,
              final Float32List many => many.toList(),
            },
            hint: document.hints[key],
            offers: widget.offers,
            // Back into a list on the way out, because that is what a uniform
            // is in the file whatever a slider hands over — a bare number under
            // `parameters` reads back as a list of one and would look to the
            // gate like a value the reader had misunderstood.
            onWrite: (Object? value) => _writeFile(
              name,
              document,
              'parameters/$key',
              value is num ? <num>[value] : value,
            ),
          ),
      ],
    ];
  }

  void _writeFile(
    String name,
    MaterialDocument document,
    String key,
    Object? value,
  ) {
    final next = materialWith(
      document,
      key,
      value,
      hint: materialDocumentHint(document, key),
    );
    if (next == null) return;
    widget.onMaterialWritten?.call(name, next);
    widget.onChanged('$name:$key');
  }

  Widget _heading(String says) => SectionLabel(
    says,
    style: const TextStyle(
      color: Color(0xFF525A66),
      fontSize: 10,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w700,
    ),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
  );
}
