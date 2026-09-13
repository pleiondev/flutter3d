/// A colour: a swatch, a hex box, three sliders for hue/saturation/value and
/// — only when the colour carries one — a fourth for alpha.
///
/// **`channels` decides whether alpha exists, not whether it is enabled.**
/// `ColorHint(channels: 3)` — `emissive`'s own hint in
/// `builtInMaterialHints` — describes a value the shader never reads a
/// fourth number from. A slider sitting there disabled would still be a
/// slider promising a fourth number is coming; this widget does not build
/// the row at all when [ColorField.channels] is 3.
///
/// **`linear` moves the whole surface, not one field.** A [ColorField.value]
/// read as linear light is not what a screen can show unchanged — the
/// swatch, the hex text and the three sliders all show the sRGB-encoded
/// approximation of it, and an edit through any of them is decoded back to
/// linear before [ColorField.onChanged] is called. Alpha is never encoded:
/// it is a coverage fraction, not a light quantity, in every convention this
/// engine's own materials already use.
///
/// **A standalone widget, not a properties-panel row.** `mat-04`, the panel
/// this is meant to sit in, does not exist yet — this file takes a value, a
/// channel count and a callback, and knows nothing about `MaterialHint` or a
/// document beyond the shape `ColorHint` already commits to.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// One colour, [ColorField.channels] components long, each in `0..1`.
class ColorField extends StatefulWidget {
  const ColorField({
    super.key,
    required this.value,
    required this.channels,
    required this.onChanged,
    this.linear = false,
    this.enabled = true,
  }) : assert(
         channels == 3 || channels == 4,
         'a colour is three components or four',
       ),
       assert(
         value.length == channels,
         'value must carry exactly one component per channel',
       );

  /// The colour as the document holds it: sRGB-encoded unless [linear] says
  /// otherwise, and never clamped by this widget — a value above 1 (an HDR
  /// emissive) draws as flat white in the swatch rather than being rewritten.
  final List<double> value;

  /// 3 for a tint with no opacity of its own, 4 when the fourth component is
  /// alpha.
  final int channels;

  /// Called with a whole new [channels]-long colour, in the same space
  /// [value] arrived in.
  final ValueChanged<List<double>> onChanged;

  /// Whether [value] is linear light rather than already sRGB-encoded.
  final bool linear;

  final bool enabled;

  /// The threshold and the two branches of the sRGB transfer function, taken
  /// from `flutter3d_cpu`'s `cpu_shaders_color.dart` — the same numbers this
  /// engine already renders every frame with, so a swatch and the pixel the
  /// renderer puts on screen for the same material never disagree.
  static double encodeSrgb(double linear) {
    final double c = linear.clamp(0.0, 1.0);
    return c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  }

  /// The inverse of [encodeSrgb].
  static double decodeSrgb(double encoded) {
    final double c = encoded.clamp(0.0, 1.0);
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Three sRGB-space components, `0..1`, as `#RRGGBB`.
  ///
  /// Static and public for the same reason `NumberField.show` is: the
  /// rounding is the thing worth testing on its own, without pumping a
  /// widget to ask what one triple of doubles prints as.
  static String hexOf(List<double> displaySrgb) {
    int byte(double c) => (c.clamp(0.0, 1.0) * 255).round().clamp(0, 255);
    String pair(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${pair(byte(displaySrgb[0]))}'
        '${pair(byte(displaySrgb[1]))}'
        '${pair(byte(displaySrgb[2]))}';
  }

  /// `#RRGGBB` (the leading `#` optional, case-insensitive) to three sRGB
  /// components, or null when [said] is not six hex digits.
  static List<double>? parseHex(String said) {
    final String cleaned = said.trim().replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final int? packed = int.tryParse(cleaned, radix: 16);
    if (packed == null) return null;
    return <double>[
      ((packed >> 16) & 0xFF) / 255,
      ((packed >> 8) & 0xFF) / 255,
      (packed & 0xFF) / 255,
    ];
  }

  /// Red, green, blue (each `0..1`) to hue (`0..360`), saturation and value
  /// (each `0..1`).
  ///
  /// Written out here rather than borrowed from `HSVColor.fromColor`, which
  /// would round-trip every colour through 8-bit integer channels — a hex
  /// box a person is dragging the value slider on would then quietly lose
  /// the fractional colour a linear swatch decoded to.
  static ({double hue, double saturation, double value}) rgbToHsv(
    double r,
    double g,
    double b,
  ) {
    final double maxc = math.max(r, math.max(g, b));
    final double minc = math.min(r, math.min(g, b));
    final double delta = maxc - minc;
    final double value = maxc;
    final double saturation = maxc == 0 ? 0.0 : delta / maxc;
    double hue;
    if (delta == 0) {
      hue = 0;
    } else if (maxc == r) {
      hue = 60 * (((g - b) / delta) % 6);
    } else if (maxc == g) {
      hue = 60 * (((b - r) / delta) + 2);
    } else {
      hue = 60 * (((r - g) / delta) + 4);
    }
    if (hue < 0) hue += 360;
    return (hue: hue, saturation: saturation, value: value);
  }

  /// The inverse of [rgbToHsv].
  static (double r, double g, double b) hsvToRgb(
    double hue,
    double saturation,
    double value,
  ) {
    final double h = (hue % 360) / 60;
    final double c = value * saturation;
    final double x = c * (1 - (h % 2 - 1).abs());
    final double m = value - c;
    final (double r, double g, double b) base = switch (h.floor()) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    return (base.$1 + m, base.$2 + m, base.$3 + m);
  }

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  late final TextEditingController _hex = TextEditingController(
    text: ColorField.hexOf(_displayRgb(widget.value, widget.linear)),
  );
  final FocusNode _hexFocus = FocusNode();

  /// The sRGB triple this widget itself last produced — through the hex box
  /// or a slider — so [didUpdateWidget] can tell "the document changed under
  /// us" from "the document caught up with what we just said", and only
  /// resync the hue in the second case. Without the distinction, a fully
  /// desaturated colour — hue undefined, arbitrarily reported as 0 — would
  /// snap the hue slider back to red on every edit of saturation or value.
  late List<double> _lastReportedRgb = _displayRgb(widget.value, widget.linear);

  /// Local hue/saturation/value, source of truth while a slider is being
  /// dragged, for the reason above.
  late ({double hue, double saturation, double value}) _hsv = ColorField.rgbToHsv(
    _lastReportedRgb[0],
    _lastReportedRgb[1],
    _lastReportedRgb[2],
  );

  static List<double> _displayRgb(List<double> value, bool linear) => linear
      ? <double>[for (final double c in value.take(3)) ColorField.encodeSrgb(c)]
      : List<double>.of(value.take(3));

  @override
  void initState() {
    super.initState();
    _hexFocus.addListener(() {
      if (!_hexFocus.hasFocus) _commitHex();
    });
  }

  @override
  void didUpdateWidget(ColorField old) {
    super.didUpdateWidget(old);
    final List<double> display = _displayRgb(widget.value, widget.linear);
    final bool sameAsReported =
        (display[0] - _lastReportedRgb[0]).abs() < 1e-6 &&
        (display[1] - _lastReportedRgb[1]).abs() < 1e-6 &&
        (display[2] - _lastReportedRgb[2]).abs() < 1e-6;
    if (sameAsReported) return;
    _lastReportedRgb = display;
    _hsv = ColorField.rgbToHsv(display[0], display[1], display[2]);
    if (!_hexFocus.hasFocus) _hex.text = ColorField.hexOf(display);
  }

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  /// Reports [displayRgb] — sRGB, whatever produced it — as the new colour,
  /// converting back to linear light first when [ColorField.linear] says
  /// the document wants that, and carrying alpha through untouched.
  void _report(List<double> displayRgb) {
    _lastReportedRgb = displayRgb;
    _hsv = ColorField.rgbToHsv(displayRgb[0], displayRgb[1], displayRgb[2]);
    _hex.text = ColorField.hexOf(displayRgb);
    final List<double> stored = widget.linear
        ? <double>[for (final double c in displayRgb) ColorField.decodeSrgb(c)]
        : displayRgb;
    widget.onChanged(<double>[
      ...stored,
      if (widget.channels == 4) widget.value[3],
    ]);
  }

  void _commitHex() {
    final List<double>? parsed = ColorField.parseHex(_hex.text);
    if (parsed == null) {
      _hex.text = ColorField.hexOf(_lastReportedRgb);
      return;
    }
    // Submitting with Enter and losing focus both call this — a text field
    // that submits via the keyboard's own done action usually loses focus in
    // the same gesture, and a caller must not see the same commit twice.
    final bool unchanged =
        (parsed[0] - _lastReportedRgb[0]).abs() < 1e-6 &&
        (parsed[1] - _lastReportedRgb[1]).abs() < 1e-6 &&
        (parsed[2] - _lastReportedRgb[2]).abs() < 1e-6;
    if (unchanged) return;
    _report(parsed);
  }

  void _applyHsv({double? hue, double? saturation, double? value}) {
    final (double r, double g, double b) = ColorField.hsvToRgb(
      hue ?? _hsv.hue,
      saturation ?? _hsv.saturation,
      value ?? _hsv.value,
    );
    setState(() => _report(<double>[r, g, b]));
  }

  void _applyAlpha(double alpha) {
    final List<double> next = List<double>.of(widget.value);
    next[3] = alpha.clamp(0.0, 1.0);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<double> display = _lastReportedRgb;
    final int r = (display[0].clamp(0.0, 1.0) * 255).round();
    final int g = (display[1].clamp(0.0, 1.0) * 255).round();
    final int b = (display[2].clamp(0.0, 1.0) * 255).round();
    final double swatchOpacity = widget.channels == 4
        ? widget.value[3].clamp(0.0, 1.0)
        : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Semantics(
              label: 'Colour swatch',
              child: Container(
                width: ModelerMetrics.row,
                height: ModelerMetrics.row,
                decoration: BoxDecoration(
                  color: Color.fromRGBO(r, g, b, swatchOpacity),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                label: 'Hex colour',
                textField: true,
                child: TextField(
                  controller: _hex,
                  focusNode: _hexFocus,
                  enabled: widget.enabled,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                  onSubmitted: (_) => _commitHex(),
                  onTapOutside: (_) => _hexFocus.unfocus(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _ChannelSlider(
          label: 'H',
          semanticLabel: 'Hue',
          value: _hsv.hue / 360,
          enabled: widget.enabled,
          onChanged: (double t) => _applyHsv(hue: t * 360),
        ),
        _ChannelSlider(
          label: 'S',
          semanticLabel: 'Saturation',
          value: _hsv.saturation,
          enabled: widget.enabled,
          onChanged: (double t) => _applyHsv(saturation: t),
        ),
        _ChannelSlider(
          label: 'V',
          semanticLabel: 'Value',
          value: _hsv.value,
          enabled: widget.enabled,
          onChanged: (double t) => _applyHsv(value: t),
        ),
        if (widget.channels == 4)
          _ChannelSlider(
            label: 'A',
            semanticLabel: 'Alpha',
            value: widget.value[3].clamp(0.0, 1.0),
            enabled: widget.enabled,
            onChanged: _applyAlpha,
          ),
      ],
    );
  }
}

/// One labelled `0..1` slider — hue, saturation, value or alpha, told apart
/// only by [label] and what [onChanged] does with the fraction.
class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final String label;
  final String semanticLabel;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 18,
          child: ExcludeSemantics(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              label: semanticLabel,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}
