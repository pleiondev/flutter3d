/// Screen 12 — `pro-rn-04`: the render mode's pass list, and the result that
/// takes the viewport's place.
///
/// **The passes are a list a person switches on and off, not a graph they
/// wire.** `pro-rn-03`'s `CompositeGraph` is a fixed chain — scene, SSAO,
/// reflections, bloom, tonemap, look, output — so what there is to decide is
/// which of the middle ones run, and a node editor for a chain that cannot
/// be rewired would be a lie about what the renderer does. The list is drawn
/// in the chain's own order, which is what makes the order visible.
///
/// **The panel is 260 wide and the result is not beside it.** The row asks
/// for both numbers, and a 260-wide strip next to a 760-wide picture is a
/// thousand points of chrome in a properties slot three hundred wide — the
/// overflow that shape actually produced. The list docks in the panel and
/// [RenderResult] replaces the viewport, which is where a picture of the
/// scene belongs and what the retarget mode already does.
library;

import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

/// What a render is asked for at — `pro-rn-04`'s own 760×428, which is 16:9
/// to within a point. The result is then drawn to fit whatever the viewport
/// slot is, so a wider window shows a bigger picture of the same render.
const Size kRenderResultSize = Size(760, 428);

/// The pass list's own width — `pro-rn-04`'s own 260.
const double kRenderGraphWidth = 260;

/// One pass of the composite chain, as the panel lists it.
typedef RenderPassRow = ({String name, bool enabled, bool fixed});

/// Screen 12's own panel: the chain, and the button that runs it.
class RenderPanel extends StatelessWidget {
  const RenderPanel({
    super.key,
    required this.passes,
    required this.onPass,
    required this.onRender,
    this.result,
    this.tilesDone = 0,
    this.tilesTotal = 0,
    this.onCancel,
  });

  /// The chain, in the order it runs.
  final List<RenderPassRow> passes;

  /// A pass was switched on or off. Never called for a [RenderPassRow.fixed]
  /// one — the scene and the output are not optional, and drawing them with
  /// a switch that does nothing would be worse than drawing them without.
  final void Function(String pass, bool on) onPass;

  /// Start a render.
  final VoidCallback onRender;

  /// What came back, or null before anything has.
  final ui.Image? result;

  /// How many tiles are done, and how many there are — zero total means no
  /// render is running.
  final int tilesDone;
  final int tilesTotal;

  /// Stop the render. Null while none is running.
  final VoidCallback? onCancel;

  bool get _running => tilesTotal > 0 && tilesDone < tilesTotal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: kRenderGraphWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionLabel('Passes'),
          for (final RenderPassRow pass in passes)
            SwitchListTile(
              key: ValueKey<String>('renderPass-${pass.name}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(pass.name, style: theme.textTheme.bodySmall),
              subtitle: pass.fixed
                  ? Text('always', style: theme.textTheme.labelSmall)
                  : null,
              value: pass.enabled,
              onChanged: pass.fixed ? null : (bool on) => onPass(pass.name, on),
            ),
          const SizedBox(height: 8),
          if (_running)
            OutlinedButton(
              key: const ValueKey<String>('renderCancel'),
              onPressed: onCancel,
              child: Text('Cancel · $tilesDone/$tilesTotal'),
            )
          else
            FilledButton.icon(
              key: const ValueKey<String>('render'),
              onPressed: onRender,
              icon: const Icon(Icons.camera_outlined),
              label: const Text('Render'),
            ),
        ],
      ),
    );
  }
}

/// Screen 12's own result, which takes the viewport's place.
///
/// **The picture goes where the picture goes.** A render is what the render
/// mode is for, and docking it beside the viewport would leave two pictures
/// of one scene on screen competing for the same glance — the retarget mode
/// already replaces the viewport wholesale for the same reason.
///
/// The progress is drawn *over* it, tile by tile: a render is the one
/// operation here long enough for "is it working" to be a real question, and
/// a bar somewhere else on the screen answers it worse than the picture
/// filling in does.
class RenderResult extends StatelessWidget {
  const RenderResult({
    super.key,
    this.result,
    this.tilesDone = 0,
    this.tilesTotal = 0,
  });

  /// What came back, or null before anything has.
  final ui.Image? result;

  final int tilesDone;
  final int tilesTotal;

  bool get _running => tilesTotal > 0 && tilesDone < tilesTotal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Container(
          key: const ValueKey<String>('renderResult'),
          color: theme.colorScheme.surfaceContainerHighest,
          child: result == null
              ? Center(
                  child: Text(
                    'Nothing rendered yet',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : RawImage(image: result, fit: BoxFit.contain),
        ),
        if (_running)
          Align(
            alignment: Alignment.bottomCenter,
            child: LinearProgressIndicator(
              key: const ValueKey<String>('renderProgress'),
              value: tilesDone / tilesTotal,
            ),
          ),
      ],
    );
  }
}
