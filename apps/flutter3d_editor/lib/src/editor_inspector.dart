/// Every field of the selected thing, editable.
///
/// **Most of the level format was unauthorable in the editor that exists to
/// author it.** The tools could move any of the three kinds, resize a brush,
/// brighten a light and turn an entity — and could not touch a brush's
/// material, `solid`, `castsShadow`, `layer` or `ramp`, a light's colour,
/// range or type, or an entity's properties. Those are the one-way platforms,
/// the non-solid decoration and the per-brush physics surfaces that the level
/// format's own documentation calls its point.
///
/// **Built from the document rather than from a list of fields.** One row per
/// key in `Editing.fields`, typed by the value that is there. That is why
/// there is no case per kind and no case per field, and why the day the format
/// grows a field this panel edits it — including a field this build has never
/// heard of, which `Level`'s write-through carries and which a hand-written
/// inspector would silently drop.
///
/// What it deliberately does not do is replace the gizmos. `at` and `size` are
/// shown because seeing the number matters, and they are also the two things
/// the arrow keys and the handles already move.
///
/// **Typed by the value, unless something can say better.** [FieldRow] asks a
/// [MaterialHint] first and falls back to the value's own type, which is what
/// lets one row serve two panels: the level has no schema and goes on being
/// edited exactly as it was, while a material — which does have one, in
/// `builtInMaterialHints` and in a `.fmat`'s own `hints` — gets a slider where
/// the range is known, a picker where the value is a colour, a file field where
/// it is a path and a list where the choices are finite. See
/// `material_panel.dart`, which is the panel on the other end of that.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart'
    show ColorHint, EnumHint, MaterialHint, RangeHint, TextureHint;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';

import 'editor_cubit.dart';

/// What a file field may offer to choose from, filtered to the suffixes the
/// hint accepts.
///
/// **A callback rather than a listing done here**, because a widget cannot list
/// a disk it was never told about: the editor knows where the open document
/// came from and this file does not. Answering nothing is allowed and is the
/// default — the row is then a path somebody types, which is what it was
/// before any of this and is still the only way to name a file that has not
/// been made yet.
typedef PathOffers = List<String> Function(List<String> suffixes);

/// The default [PathOffers]: nothing can list the files, so nothing is
/// offered. Named rather than written twice, because both panels want it.
List<String> nothingToOffer(List<String> suffixes) => const <String>[];

final class EditorInspector extends StatelessWidget {
  const EditorInspector({
    super.key,
    required this.state,
    required this.onChanged,
  });

  final EditorReady state;

  /// Called after a field was actually written, so the screen can rebuild and
  /// the scene can be rebuilt from the document.
  final void Function(String what) onChanged;

  @override
  Widget build(BuildContext context) {
    final editing = state.editing;
    final fields = editing.fields;
    if (fields.isEmpty) return const SizedBox.shrink();

    final keys = fields.keys.toList()..sort();
    // **What the document does not say, and could.** A brush is solid and casts
    // a shadow by omission, so the crypt's every wall carries neither key — and
    // a one-way platform or a piece of non-solid decoration is made by adding
    // one. A panel built purely from the row would show three fields and offer
    // no way to reach the two that matter.
    final absent = editing.offerable;
    final more = absent.keys.toList()..sort();

    return Container(
      width: 232,
      // **Nearly opaque, where the palette is translucent.** Both sit over the
      // level, and the palette is labels somebody glances at while the picture
      // behind it matters. This is numbers somebody reads exactly and boxes
      // somebody types into, over whatever the level happens to be lit like —
      // and a coordinate you have to squint at is a coordinate you retype.
      color: const Color(0xF20D0F12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              editing.says.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6F7885),
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Scrolls for the reason the palette does: how many rows there are is
          // the document's decision, and a column that overflows in Flutter
          // does not draw the rows past the bottom at all.
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
                      value: fields[key],
                      // Through the history, like every other change: one row
                      // written is one step back, named after the field it
                      // wrote. `run` answers what `setField` answers, so a
                      // value the format cannot read still rebuilds nothing.
                      onWrite: (Object? value) {
                        if (editing.history.run(SetField(key, value))) {
                          onChanged(key);
                        }
                      },
                    ),
                  if (more.isNotEmpty) ...<Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
                      child: Text(
                        'NOT SET',
                        style: TextStyle(
                          color: Color(0xFF525A66),
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final key in more)
                      FieldRow(
                        key: ValueKey<String>('field:$key'),
                        name: key,
                        value: absent[key],
                        // Dimmed, because what is shown is what the format
                        // would use rather than what the document says — and
                        // the difference matters to somebody reading a diff.
                        faded: true,
                        onWrite: (Object? value) {
                          if (editing.history.run(SetField(key, value))) {
                            onChanged(key);
                          }
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One field: its name, and whatever editor the hint — or, failing that, its
/// current value — calls for.
///
/// **One row for both panels**, which is why it is public. The level and a
/// material are the same problem asked twice — a name, a value, and a way to
/// write it back — and two rows would be two places for "emptying a box clears
/// the key" and "a change goes through the history" to drift apart.
final class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.name,
    required this.value,
    required this.onWrite,
    this.hint,
    this.faded = false,
    this.offers = nothingToOffer,
  });

  final String name;
  final Object? value;
  final void Function(Object? value) onWrite;

  /// What a control for this value should look like, when anything knows.
  ///
  /// Null for every field of a level, and that is the whole reason the switch
  /// below has two halves: the level format has no schema to ask, so a document
  /// nothing has hinted goes on being edited by the type of what is there.
  final MaterialHint? hint;

  /// Whether this row shows what the format would use rather than what the
  /// document says. Writing it is what puts the key in the document.
  final bool faded;

  /// See [PathOffers]. Only a [TextureHint] reads it.
  final PathOffers offers;

  @override
  Widget build(BuildContext context) {
    final editor = _hinted() ?? _byType();

    final label = hint?.label ?? name;
    final help = hint?.help;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The sentence a hint carries is shown on hover rather than under the
          // name: it is a paragraph — "nought is a dielectric, one is bare
          // metal" — and a panel this narrow that printed every one of them
          // would be four fields tall and unscrollable to the fifth.
          Tooltip(
            message: help ?? '',
            excludeFromSemantics: help == null,
            child: Text(
              label,
              style: TextStyle(
                color: faded
                    ? const Color(0xFF5E6672)
                    : const Color(0xFF8A93A0),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 2),
          editor,
        ],
      ),
    );
  }

  /// The control the hint asks for, or null.
  ///
  /// **Null when the value is not the shape the hint describes**, and that
  /// matters more than it looks: a hint may come from a file written by another
  /// tool, so a `range` over a string or a `color` over a single number is a
  /// thing that can arrive. Falling back to [_byType] there shows the value as
  /// it is, which is the only honest thing to do with a field whose description
  /// and whose content disagree.
  Widget? _hinted() => switch ((hint?.kind, value)) {
    (final RangeHint it, final num at) => _SliderField(
      hint: it,
      value: at,
      onWrite: onWrite,
    ),
    (final ColorHint it, final List<Object?> at)
        when at.length >= 3 && at.every((Object? e) => e is num) =>
      _ColorField(hint: it, values: at.cast<num>(), onWrite: onWrite),
    (final TextureHint it, final String at) => _TextureField(
      hint: it,
      path: at,
      offers: offers,
      onWrite: onWrite,
    ),
    (final EnumHint it, final String at) => _EnumField(
      hint: it,
      value: at,
      onWrite: onWrite,
    ),
    _ => null,
  };

  /// The editor the value's own type calls for — the panel as it was before
  /// anything was hinted, and what a level still gets.
  Widget _byType() => switch (value) {
    final bool it => _BoolField(value: it, onWrite: onWrite),
    final num it => _TextField(
      text: numberText(it),
      onWrite: (String text) {
        final parsed = num.tryParse(text);
        if (parsed != null) onWrite(parsed);
      },
    ),
    // **Emptying a text field removes the key.** `surface`, a light's `name`
    // and an entity's are all "not set" by being absent, and writing `""`
    // instead gives a brush a surface called nothing — a value the format
    // reads happily and no game means. Clearing a box is how a person says
    // "no value", so it is what it does.
    final String it => _TextField(
      text: it,
      onWrite: (String text) => onWrite(text.isEmpty ? null : text),
    ),
    // A list of numbers is a position, a size, a colour or a direction, and
    // all four are worth seeing and worth typing exactly — a colour picked by
    // eye is a colour nobody can reproduce from the document.
    final List<Object?> it when it.every((Object? e) => e is num) =>
      _NumbersField(
        values: it.cast<num>(),
        onWrite: (List<num> next) => onWrite(next),
      ),
    // Anything else — a nested object, a mixed list — has no honest editor
    // here. Shown, so nobody thinks the field is missing, and not editable,
    // because a text box over a structure is a way to write a document that
    // will not load.
    _ => _ReadOnly(text: '$value'),
  };

  /// Whole numbers without a trailing `.0`, which is what the generators write
  /// and what a diff of one of these documents should stay readable as.
  ///
  /// Public because the controls below and the material panel both print
  /// numbers, and a panel that spelled the same value two ways in two rows
  /// would look like two different values.
  static String numberText(num it) =>
      it is int || it == it.roundToDouble() ? '${it.toInt()}' : '$it';
}

final class _BoolField extends StatelessWidget {
  const _BoolField({required this.value, required this.onWrite});

  final bool value;
  final void Function(Object? value) onWrite;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    // Scaled down to the height of a text row, so a panel of mixed fields
    // reads as one list rather than as rows of two different sizes.
    child: Transform.scale(
      scale: 0.75,
      alignment: Alignment.centerLeft,
      child: Switch(
        value: value,
        onChanged: onWrite,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

/// A box that writes when the field is left or Enter is pressed.
///
/// **Not on every keystroke.** A document rebuilt per character would put an
/// undo step behind each one, and half a typed word is usually not a value the
/// format can read — so the panel would spend most of a rename refusing.
final class _TextField extends StatefulWidget {
  const _TextField({required this.text, required this.onWrite});

  final String text;
  final void Function(String text) onWrite;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    // The document is the source of truth: an undo, or an edit from a gizmo,
    // has to show here. Only when it actually differs, or typing would fight
    // the rebuild for the cursor.
    if (widget.text != _controller.text) _controller.text = widget.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    // Keystrokes belong to the box while it has the focus, and the editor's
    // own `Focus` above would otherwise read W, A, S and D as flying the
    // camera while somebody types a material name.
    onKeyEvent: (FocusNode node, KeyEvent event) =>
        KeyEventResult.skipRemainingHandlers,
    child: TextField(
      controller: _controller,
      onSubmitted: widget.onWrite,
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        if (_controller.text != widget.text) widget.onWrite(_controller.text);
      },
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        filled: true,
        fillColor: Color(0xFF171A1F),
        border: OutlineInputBorder(borderSide: BorderSide.none),
      ),
    ),
  );
}

/// Three or four numbers side by side: a position, a size, a colour.
final class _NumbersField extends StatelessWidget {
  const _NumbersField({required this.values, required this.onWrite});

  final List<num> values;
  final void Function(List<num> values) onWrite;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      for (var i = 0; i < values.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: _TextField(
            text: FieldRow.numberText(values[i]),
            onWrite: (String text) {
              final parsed = num.tryParse(text);
              if (parsed == null) return;
              onWrite(<num>[
                for (var j = 0; j < values.length; j++)
                  j == i ? parsed : values[j],
              ]);
            },
          ),
        ),
      ],
    ],
  );
}

final class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: Color(0xFF5E6672), fontSize: 11),
  );
}

/// A number with two ends: a slider, and the number itself beside it.
///
/// **Both, not one.** The slider is what roughness wants — it is a feel, found
/// by dragging — and the box is what a document wants, because a value found by
/// eye and never printed is a value nobody can reproduce or review in a diff.
/// The panel already made that argument for a colour and it is the same
/// argument here.
///
/// **A value outside the hint's ends is shown, not clamped.** The engine's own
/// note on [MaterialHint] says a hint is a description for a person and never a
/// rule for the reader: a roughness of 1.5 is what the shader receives, and a
/// slider that silently dragged it back to 1 would be an editor changing what a
/// picture looks like in order to tidy up its own control. So the thumb parks
/// at the near end, the box goes on printing the real number, and a line under
/// it says the two disagree.
final class _SliderField extends StatefulWidget {
  const _SliderField({
    required this.hint,
    required this.value,
    required this.onWrite,
  });

  final RangeHint hint;
  final num value;
  final void Function(Object? value) onWrite;

  @override
  State<_SliderField> createState() => _SliderFieldState();
}

class _SliderFieldState extends State<_SliderField> {
  /// Where the thumb is while a finger is on it.
  ///
  /// State because a drag is state: the document is not written until the drag
  /// ends — one step in the history for one thing a person did, the same
  /// bargain `EditorHistory.transaction` strikes for dragging a brush — and
  /// until then something has to remember where the thumb got to.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final hint = widget.hint;
    final value = widget.value.toDouble();
    final outside = value < hint.min || value > hint.max;
    final step = hint.step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                ),
                child: Slider(
                  value: (_dragging ?? value).clamp(hint.min, hint.max),
                  min: hint.min,
                  max: hint.max,
                  divisions: step == null || step <= 0.0
                      ? null
                      : math.max(1, ((hint.max - hint.min) / step).round()),
                  onChanged: (double it) => setState(() => _dragging = it),
                  onChangeEnd: (double it) {
                    setState(() => _dragging = null);
                    widget.onWrite(_stepped(it, step));
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 54,
              child: _TextField(
                text: FieldRow.numberText(widget.value),
                onWrite: (String text) {
                  final parsed = num.tryParse(text);
                  if (parsed != null) widget.onWrite(parsed);
                },
              ),
            ),
          ],
        ),
        if (outside)
          Text(
            '${FieldRow.numberText(widget.value)} is outside '
            '${FieldRow.numberText(hint.min)}–${FieldRow.numberText(hint.max)}',
            style: const TextStyle(color: Color(0xFFD98F4A), fontSize: 10),
          ),
      ],
    );
  }

  /// [value] on the hint's increment, and short enough to read in a diff.
  ///
  /// A slider lands on a double with fifteen digits in it, and a material file
  /// full of `0.30000000000000004` is a file nobody can review.
  static num _stepped(double value, double? step) {
    final on = step == null || step <= 0.0
        ? value
        : (value / step).roundToDouble() * step;
    return num.parse(on.toStringAsFixed(4));
  }
}

/// A colour: a swatch that opens a picker, and the numbers beside it.
///
/// The numbers stay for the reason the panel's own note gives — a colour picked
/// by eye is a colour nobody can reproduce from the document — and the swatch
/// is there because reading four numbers is not how anybody finds out that the
/// wall is slightly green.
final class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.hint,
    required this.values,
    required this.onWrite,
  });

  final ColorHint hint;
  final List<num> values;
  final void Function(Object? value) onWrite;

  Color get _shown =>
      Color.fromARGB(255, _byte(values[0]), _byte(values[1]), _byte(values[2]));

  static int _byte(num it) => (it.toDouble().clamp(0.0, 1.0) * 255).round();

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      GestureDetector(
        onTap: () async {
          final picked = await showDialog<List<double>>(
            context: context,
            builder: (BuildContext context) => const _ColorPicker(),
          );
          if (picked == null) return;
          // The channel count is the hint's, not the picker's: a swatch that
          // wrote an alpha for `emissive` would be setting a number the shader
          // never reads. A fourth component the document already carries is
          // kept — opacity is not something a hue picker has an opinion about.
          onWrite(<num>[
            ...picked,
            if (hint.channels > 3 && values.length > 3) values[3],
          ]);
        },
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _shown,
            border: Border.all(color: const Color(0xFF2A2F37)),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: _NumbersField(
          values: values,
          onWrite: (List<num> next) => onWrite(next),
        ),
      ),
    ],
  );
}

/// The swatches a colour is picked from.
///
/// A grid rather than a wheel: a wheel is a gesture nobody can repeat, and what
/// this is for is finding roughly the right paint before the numbers beside it
/// are typed exactly. Twelve hues across, four brightnesses down, and a row of
/// greys — which is where most of a level's walls actually live.
final class _ColorPicker extends StatelessWidget {
  const _ColorPicker();

  static const List<double> _levels = <double>[1.0, 0.72, 0.45, 0.2];

  @override
  Widget build(BuildContext context) => SimpleDialog(
    backgroundColor: const Color(0xFF15181D),
    title: const Text(
      'Colour',
      style: TextStyle(color: Color(0xFF8A93A0), fontSize: 13),
    ),
    contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    children: <Widget>[
      for (final level in _levels)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var hue = 0; hue < 12; hue++)
              _swatch(context, _fromHue(hue / 12.0, level)),
          ],
        ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var grey = 0; grey < 12; grey++)
            _swatch(context, <double>[grey / 11.0, grey / 11.0, grey / 11.0]),
        ],
      ),
    ],
  );

  Widget _swatch(BuildContext context, List<double> rgb) => GestureDetector(
    onTap: () => Navigator.of(context).pop(rgb),
    child: Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.all(1),
      color: Color.fromARGB(
        255,
        _ColorField._byte(rgb[0]),
        _ColorField._byte(rgb[1]),
        _ColorField._byte(rgb[2]),
      ),
    ),
  );

  /// A colour at [hue], dimmed to [level]. The same six sectors the editor's
  /// gizmo tints are built from, which is why they are not imported: this wants
  /// three doubles for a swatch and that answers a `Vector3` for a mark.
  static List<double> _fromHue(double hue, double level) {
    final sector = hue * 6.0;
    final rise = sector - sector.floorToDouble();
    final fall = 1.0 - rise;
    final rgb = switch (sector.floor() % 6) {
      0 => <double>[1.0, rise, 0.0],
      1 => <double>[fall, 1.0, 0.0],
      2 => <double>[0.0, 1.0, rise],
      3 => <double>[0.0, fall, 1.0],
      4 => <double>[rise, 0.0, 1.0],
      _ => <double>[1.0, 0.0, fall],
    };
    return <double>[
      for (final channel in rgb)
        double.parse((channel * level).toStringAsFixed(3)),
    ];
  }
}

/// A path to a file: a box to type it in, and — when anything can list them —
/// a button that offers the files that would fit.
///
/// **A path that does not fit the hint is said, not refused.** The suffixes are
/// what this engine decodes today and a material may legitimately name a file
/// that is not there yet, or one a build step produces. Colouring the line is
/// enough to catch the `.tga` somebody dragged in from another engine.
final class _TextureField extends StatelessWidget {
  const _TextureField({
    required this.hint,
    required this.path,
    required this.offers,
    required this.onWrite,
  });

  final TextureHint hint;
  final String path;
  final PathOffers offers;
  final void Function(Object? value) onWrite;

  bool get _fits =>
      path.isEmpty ||
      hint.extensions.any((String it) => path.toLowerCase().endsWith(it));

  @override
  Widget build(BuildContext context) {
    final candidates = offers(hint.extensions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _TextField(
                text: path,
                // Emptying it clears the key, for the reason every other text
                // box here does: a texture slot naming nothing is a slot the
                // reader warns about, and "no texture" is what an empty box
                // means to the person who emptied it.
                onWrite: (String text) => onWrite(text.isEmpty ? null : text),
              ),
            ),
            if (candidates.isNotEmpty) ...<Widget>[
              const SizedBox(width: 4),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: 'Choose a file',
                  color: const Color(0xFF8A93A0),
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    final picked = await showDialog<String>(
                      context: context,
                      builder: (BuildContext context) =>
                          _FilePicker(paths: candidates),
                    );
                    if (picked != null) onWrite(picked);
                  },
                ),
              ),
            ],
          ],
        ),
        if (!_fits)
          Text(
            'not one of ${hint.extensions.join(' ')}',
            style: const TextStyle(color: Color(0xFFD98F4A), fontSize: 10),
          ),
      ],
    );
  }
}

/// The files a [_TextureField] was offered, to pick one from.
final class _FilePicker extends StatelessWidget {
  const _FilePicker({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    backgroundColor: const Color(0xFF15181D),
    title: const Text(
      'Choose a file',
      style: TextStyle(color: Color(0xFF8A93A0), fontSize: 13),
    ),
    children: <Widget>[
      for (final path in paths)
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(path),
          child: Text(
            path,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
    ],
  );
}

/// One of a finite set of words.
///
/// **What is in the document is always in the list**, even when the hint does
/// not offer it. A material written by a newer tool may name an alpha mode this
/// build has never heard of, and a picker that could not display it would show
/// the wrong mode and write the wrong one the moment anybody touched anything
/// else on the panel. So the value joins the list, saying what it is.
final class _EnumField extends StatelessWidget {
  const _EnumField({
    required this.hint,
    required this.value,
    required this.onWrite,
  });

  final EnumHint hint;
  final String value;
  final void Function(Object? value) onWrite;

  @override
  Widget build(BuildContext context) {
    final offered = hint.values.any((it) => it.value == value);
    return DropdownButton<String>(
      value: value,
      isDense: true,
      isExpanded: true,
      dropdownColor: const Color(0xFF171A1F),
      underline: const SizedBox.shrink(),
      style: const TextStyle(color: Colors.white, fontSize: 12),
      items: <DropdownMenuItem<String>>[
        for (final it in hint.values)
          DropdownMenuItem<String>(value: it.value, child: Text(it.label)),
        if (!offered)
          DropdownMenuItem<String>(
            value: value,
            child: Text('$value — not one this build offers'),
          ),
      ],
      onChanged: (String? next) {
        if (next != null && next != value) onWrite(next);
      },
    );
  }
}
