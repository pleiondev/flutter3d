/// `pro-uv-07`'s own screen 06, absorbing view-19: the seam-highlighted 3D
/// view on the left, the UV layout and its own method/margin/list panel on
/// the right.
///
/// **The viewport is handed in, not built here.** A real one needs a
/// `Renderer` and a `ModelerStage` this screen has no business owning, and
/// `ModelerViewport` — this app's own `RenderView` — already draws
/// [EdgeFlags.seam]-marked edges in `MeshOverlayColours.seam` the moment its
/// own `editMesh` is set (`mesh_overlay_builder.dart`'s `_emitLines`), so a
/// caller wiring the real 3D view need do nothing more than keep passing the
/// unwrapped mesh through as it already does for every other screen. This
/// widget's own job stops at composing screens, the way `ExportScreen`
/// composes a project rather than opening a viewport of its own.
///
/// **Three layouts, because the hand-over draws one and a window is not
/// always that wide.** Screen 06 is three columns — the model, a 400-pixel
/// square with room round it, and a 250-wide panel — which is 700 pixels
/// spoken for before the model gets any. Given that much and a model's worth
/// more, this is that picture. Given less it stacks the square over the
/// panel in one column, and given a phone's width it puts both under the
/// model instead of beside it. In each the square is as big as the column it
/// is in lets it be and no bigger: `UvLayoutView` sizes itself to the room it
/// is given, so nothing here ever clips an island off the edge of the
/// texture.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../l10n/app_localizations.dart';
import '../uv_unwrap_layout.dart';
import 'theme.dart';
import 'uv_layout_view.dart';
import 'uv_unwrap_panel.dart';

/// At and above this width the screen is the hand-over's own three columns.
///
/// The square's own column ([_wideLayoutColumn]) and the panel's
/// ([ModelerMetrics.propertiesMin]) are fixed, so this is what leaves the
/// model a little over a quarter of a thousand pixels — below that a person
/// is marking seams on a picture too small to aim at, and the stacked
/// layout gives the model the width back.
const double kUvScreenWide = 960;

/// Below this width the layout and the panel go under the model.
const double kUvScreenNarrow = 560;

/// The square, 400, and the 24 pixels either side of it the hand-over leaves.
const double _wideLayoutColumn = 448;

/// How wide the square's own pane is under the model, on a phone.
const double _narrowLayoutColumn = 200;

/// How tall the strip under the model is, on a phone — enough for the
/// [_narrowLayoutColumn]-wide square, its title and its legend.
const double _narrowStrip = 264;

/// Screen 06: the 3D view on the left, the UV layout and its own panel on
/// the right.
final class UvScreen extends StatelessWidget {
  const UvScreen({
    super.key,
    required this.viewport,
    required this.islands,
    required this.methods,
    required this.method,
    required this.onMethodChanged,
    required this.margin,
    required this.onMarginChanged,
    this.selectedIslandId,
    this.onIslandSelected,
    this.autoPack,
    this.onAutoPackChanged,
    this.onUnwrap,
    this.unwrapRefusal,
  });

  /// The 3D view, already wired with the mesh this screen is unwrapping —
  /// whatever this app calls its own `RenderView`, today `ModelerViewport`.
  /// Handed in rather than built here; see this file's own doc comment.
  final Widget viewport;

  /// The unwrap's own islands, read off the mesh by [buildUvIslandData].
  final List<UvIslandData> islands;

  final List<UnwrapMethod> methods;
  final UnwrapMethod method;
  final ValueChanged<UnwrapMethod> onMethodChanged;

  final double margin;
  final ValueChanged<double> onMarginChanged;

  final int? selectedIslandId;

  /// An island was picked, whether by a tap on [UvLayoutView] or a row in
  /// [UvUnwrapPanel]'s own list — both report through this one callback, so
  /// a caller keeps one idea of "which island is selected" rather than two
  /// that can disagree.
  final ValueChanged<int>? onIslandSelected;

  /// [UvUnwrapPanel]'s own four, carried straight through — see their doc
  /// comments there. All optional, so a caller that only wants the picture
  /// and the list builds this exactly as it did before they existed.
  final bool? autoPack;
  final ValueChanged<bool>? onAutoPackChanged;
  final VoidCallback? onUnwrap;
  final String? unwrapRefusal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelEdge =
        theme.extension<ModelerColors>()?.panelEdge ?? theme.dividerColor;
    final onSelected = onIslandSelected;

    final Widget layout = _LayoutPane(
      islands: islands,
      selectedIslandId: selectedIslandId,
      onTriangleTap: onSelected == null
          ? null
          : (int islandId, int triangleIndex) => onSelected(islandId),
    );
    final Widget panel = Padding(
      padding: const EdgeInsets.all(12),
      child: UvUnwrapPanel(
        methods: methods,
        method: method,
        onMethodChanged: onMethodChanged,
        margin: margin,
        onMarginChanged: onMarginChanged,
        islands: islands,
        selectedIslandId: selectedIslandId,
        onIslandSelected: onSelected,
        autoPack: autoPack,
        onAutoPackChanged: onAutoPackChanged,
        onUnwrap: onUnwrap,
        unwrapRefusal: unwrapRefusal,
      ),
    );
    // **A `Material` under everything that is not the picture.** The list
    // rows and the tick are `ListTile`s, which paint their ink on the nearest
    // `Material` above them; the shell puts a plain `ColoredBox` behind its
    // viewport slot, and a `ListTile` over one asserts — the framework's own
    // "ink splashes may be invisible". The properties slot has a `Material`
    // and this screen does not sit in it, so it brings its own: the panel's
    // surface for the panel, one step darker for the square, the way the
    // hand-over shades the two.
    final Color panelSurface = theme.colorScheme.surfaceContainerLow;
    final Color paneSurface = theme.colorScheme.surfaceContainerLowest;
    final Widget upright = Container(width: 1, color: panelEdge);
    final Widget level = Container(height: 1, color: panelEdge);

    // **Everything beside the model scrolls.** The square does not shrink to
    // a short window the way it shrinks to a narrow one — a landscape phone
    // is wide enough for the stacked column and a third as tall as it needs —
    // and a column that overflows draws a striped bar over the island list.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        if (width >= kUvScreenWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: viewport),
              upright,
              SizedBox(
                width: _wideLayoutColumn,
                child: Material(
                  color: paneSurface,
                  child: Center(child: SingleChildScrollView(child: layout)),
                ),
              ),
              upright,
              SizedBox(
                width: ModelerMetrics.propertiesMin,
                child: Material(
                  color: panelSurface,
                  child: SingleChildScrollView(child: panel),
                ),
              ),
            ],
          );
        }
        if (width >= kUvScreenNarrow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: viewport),
              upright,
              SizedBox(
                width: ModelerMetrics.propertiesMax,
                child: Material(
                  color: panelSurface,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[layout, level, panel],
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: viewport),
            level,
            SizedBox(
              height: _narrowStrip,
              child: Material(
                color: panelSurface,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: _narrowLayoutColumn,
                      child: SingleChildScrollView(child: layout),
                    ),
                    upright,
                    Expanded(child: SingleChildScrollView(child: panel)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The square, with what it is above it and what its two colours mean under
/// it — the hand-over's own caption and legend.
final class _LayoutPane extends StatelessWidget {
  const _LayoutPane({
    required this.islands,
    required this.selectedIslandId,
    required this.onTriangleTap,
  });

  final List<UvIslandData> islands;
  final int? selectedIslandId;
  final UvTriangleTap? onTriangleTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle? caption = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.uvLayoutTitle, style: caption),
          const SizedBox(height: 8),
          Center(
            child: UvLayoutView(
              islands: islands,
              selectedIslandId: selectedIslandId,
              onTriangleTap: onTriangleTap,
              semanticLabel: l.uvLayoutSemantics(islands.length),
            ),
          ),
          const SizedBox(height: 8),
          // The two ends of `uvStretchColor`'s own ramp, named. Without it
          // the picture is grey shapes and pink shapes and a person has to
          // guess which of the two is the complaint.
          Wrap(
            spacing: 14,
            children: <Widget>[
              _LegendEntry(
                colour: kUvNeutralColor,
                label: l.uvLegendNormal,
                style: caption,
              ),
              _LegendEntry(
                colour: kUvMaxStretchColor,
                label: l.uvLegendStretched,
                style: caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.colour,
    required this.label,
    required this.style,
  });

  final Color colour;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      ColoredBox(color: colour, child: const SizedBox(width: 10, height: 10)),
      const SizedBox(width: 6),
      Text(label, style: style),
    ],
  );
}
