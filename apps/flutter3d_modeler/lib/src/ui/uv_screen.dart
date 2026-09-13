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
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../uv_unwrap_layout.dart';
import 'theme.dart';
import 'uv_layout_view.dart';
import 'uv_unwrap_panel.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelEdge =
        theme.extension<ModelerColors>()?.panelEdge ?? theme.dividerColor;
    final onSelected = onIslandSelected;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: viewport),
        Container(width: 1, color: panelEdge),
        SizedBox(
          width: ModelerMetrics.propertiesMax,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: UvLayoutView(
                    islands: islands,
                    selectedIslandId: selectedIslandId,
                    onTriangleTap: onSelected == null
                        ? null
                        : (int islandId, int triangleIndex) =>
                              onSelected(islandId),
                  ),
                ),
              ),
              Container(height: 1, color: panelEdge),
              Expanded(
                child: SingleChildScrollView(
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
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
