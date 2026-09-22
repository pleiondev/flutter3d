/// `mat-13`'s own node-graph editor over one material's `TextureGraph` —
/// `TextureGraphPanel`, collapsed to a single header row until opened, an
/// `InteractiveViewer` canvas of draggable node boxes and cubic-Bézier links
/// once it is.
///
/// **A dumb widget, the same split every panel in this shell already keeps.**
/// `ModifierStackPanel` reads a stack and calls back with an index; this
/// reads a [TextureGraph] and calls back with exactly what `AddNode`,
/// `Link`, `Unlink`, `SetNodeField` and `MoveNode` (`flutter3d_model_core`)
/// each take — a kind and its fields, a node id and an input name, a field
/// and a value, a node id and a new (x, y) — so whoever owns the document
/// (a cubit, not built here) turns a callback straight into the matching
/// command without this file importing `ModelCommand` at all.
///
/// **A node's thumbnail is handed in, not decoded here.** [thumbnails] maps
/// a node id to whatever bytes a caller already has ready for `Image.memory`
/// — most of this app's eleven node kinds have no bytes of their own to
/// show (a `Blend` or a `Noise` node is a formula, not a file) and building
/// a preview for one means baking it, which is `bakeTextureGraph`'s own
/// CPU work and does not belong inside a widget's `build`.
///
/// **The bake button is `JobButton`, not a new progress bar.** `job_button.dart`
/// already reads `null` as idle and a 0-to-1 [bakeProgress] as running, with
/// its own cancel affordance — the same shape `ModelerCubit`'s own
/// `ActiveJob` already gives every other background bake in this app, so
/// `BakeTextureGraph`'s own 2048² pass is shown the same way rather than a
/// second progress convention this file would have invented.
library;

import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
// `EnumHint` hidden: this file switches on `MaterialHint.kind`, which is
// `flutter3d_formats`' own `EnumHint` — `flutter3d_model_core`'s is
// `ModelCommand.hints`' own, for a command argument, and the two are kept
// apart the same way `command.dart` itself keeps them apart.
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide EnumHint;

import '../../l10n/app_localizations.dart';
import 'job_button.dart';
import 'named_button.dart';
import 'theme.dart';

/// A node's own header, in logical pixels — the offset every input port and
/// the single output port is anchored from, in both [_NodeCard] and
/// [_LinksPainter], so a link never has to guess where a port drew itself.
const double _kHeaderHeight = 26;

/// One input socket's own row height, stacked below the header in
/// [TextureNode.inputs]' own order.
const double _kPortRowHeight = 20;

/// The eleven kinds [TextureNode.fromJson] reads, in the order
/// `TextureGraphPanel`'s own "Add" menu offers them — [TextureGraph]'s own
/// library comment's list, unchanged.
const List<String> textureNodeKinds = <String>[
  'image',
  'color',
  'blend',
  'channels',
  'levels',
  'invert',
  'uvTransform',
  'checker',
  'noise',
  'normalFromHeight',
  'output',
];

/// The fields [AddNode] needs for a fresh node of [kind] — exactly what
/// [TextureNode.fromJson] requires and nothing [fromJson] would default for
/// free, so a node this menu adds is never refused by [AddNode] itself for
/// leaving out something required.
Map<String, Object?> defaultTextureNodeFields(String kind) => switch (kind) {
  'image' => const <String, Object?>{'imageId': 0},
  'color' => const <String, Object?>{
    'value': <double>[1, 1, 1, 1],
  },
  'blend' => const <String, Object?>{'mode': 'normal', 'factor': 1.0},
  'channels' => const <String, Object?>{'channel': 'r'},
  'levels' => const <String, Object?>{
    'blackPoint': 0.0,
    'whitePoint': 1.0,
    'gamma': 1.0,
  },
  'invert' => const <String, Object?>{},
  'uvTransform' => const <String, Object?>{
    'offset': <double>[0, 0],
    'scale': <double>[1, 1],
    'rotation': 0.0,
  },
  'checker' => const <String, Object?>{
    'colorA': <double>[0, 0, 0, 1],
    'colorB': <double>[1, 1, 1, 1],
    'scale': 8.0,
  },
  'noise' => const <String, Object?>{'seed': 0, 'scale': 1.0},
  'normalFromHeight' => const <String, Object?>{'strength': 1.0},
  'output' => const <String, Object?>{},
  _ => const <String, Object?>{},
};

double _asDouble(Object? value) => switch (value) {
  final num n => n.toDouble(),
  _ => 0.0,
};

/// A control for [value], shaped by [hint].kind — [RangeHint] a slider,
/// [EnumHint] a dropdown, [ColorHint] a swatch, [TextureHint] the image
/// index it is today with a way to move it on.
///
/// **A swatch cycles a short fixed palette rather than opening a colour
/// picker.** A real one is `mat-15`'s own `MaterialStudioDialog` scale of
/// work, not a control inside one row of eleven possible node kinds; this
/// keeps the row real and testable — tapping it does change the node's own
/// field through [onChanged] — without pulling that whole dialog in here.
/// The same trade is why [TextureHint] moves the image index by one rather
/// than opening a file picker: picking a file is disk access, which belongs
/// to whatever app-level code already owns it, not to a presentational row.
final class HintRow extends StatelessWidget {
  const HintRow({
    super.key,
    required this.field,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  /// The node field this hints at — one of [TextureNode.hints]' own keys.
  final String field;

  final MaterialHint hint;

  /// The field's own JSON value right now — a number, a string, or a list of
  /// numbers, straight out of [TextureNode.toJson].
  final Object? value;

  /// Called with a replacement for [value], already shaped the way
  /// [TextureNode.fromJson] reads that field back.
  final ValueChanged<Object?> onChanged;

  static const List<List<double>> _swatches = <List<double>>[
    <double>[1, 1, 1, 1],
    <double>[0, 0, 0, 1],
    <double>[0.8, 0.2, 0.2, 1],
    <double>[0.2, 0.7, 0.3, 1],
    <double>[0.25, 0.4, 0.85, 1],
  ];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String label = hint.label ?? field;
    final String bound = value?.toString() ?? '\u2014';
    final Widget control = switch (hint.kind) {
      RangeHint(:final double min, :final double max, :final double? step) =>
        RangeSliderField(
          value: _asDouble(value),
          min: min,
          max: max,
          step: step,
          onChanged: (double v) => onChanged(v),
        ),
      EnumHint(:final values) => EnumField(
        value: switch (value) {
          final String s => s,
          _ => null,
        },
        options: values,
        onChanged: onChanged,
      ),
      ColorHint(:final channels) => GestureDetector(
        onTap: () {
          final List<double> current = switch (value) {
            final List<Object?> l => <double>[for (final e in l) _asDouble(e)],
            _ => _swatches.first,
          };
          var index = _swatches.indexWhere(
            (List<double> s) =>
                s.take(channels).toList().toString() ==
                current.take(channels).toList().toString(),
          );
          index = (index + 1) % _swatches.length;
          onChanged(_swatches[index].take(channels).toList());
        },
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Color.fromRGBO(
              (255 * _channelAt(value, 0)).round(),
              (255 * _channelAt(value, 1)).round(),
              (255 * _channelAt(value, 2)).round(),
              channels > 3 ? _channelAt(value, 3) : 1.0,
            ),
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      TextureHint() => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The image index, or an em dash for a node that names none.
          // Built above rather than inside the string: a quote inside
          // an interpolation reads as the end of the string to every
          // scanner that is not a Dart parser, `ux-22`'s own literal
          // check included.
          Text('#$bound', style: theme.textTheme.bodySmall),
          NamedButton(
            label: l.graphNextImage,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              iconSize: 14,
              icon: const Icon(Icons.swap_horiz),
              tooltip: l.graphNextImageTooltip,
              onPressed: () => onChanged(switch (value) {
                final int n => n + 1,
                _ => 0,
              }),
            ),
          ),
        ],
      ),
    };
    return SizedBox(
      height: ModelerMetrics.row,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(child: control),
        ],
      ),
    );
  }
}

double _channelAt(Object? value, int index) => switch (value) {
  final List<Object?> l when index < l.length => _asDouble(l[index]),
  _ => 0.0,
};

double _nodeWidth(TextureNode node) {
  final int ports = node.inputs.length + node.hints.length;
  return lerpDouble(170, 210, (ports / 6).clamp(0, 1))!;
}

Offset _outputAnchor(Offset topLeft, double width) =>
    topLeft + Offset(width, _kHeaderHeight / 2);

Offset _inputAnchor(TextureNode node, String input, Offset topLeft) {
  final int index = node.inputs.keys.toList(growable: false).indexOf(input);
  final int row = index < 0 ? 0 : index;
  return topLeft +
      Offset(0, _kHeaderHeight + row * _kPortRowHeight + _kPortRowHeight / 2);
}

/// One node, drawn as a box 170–210 px wide — wider the more ports and
/// fields it carries, so a bare `Color` node and an eleven-field `Blend`
/// node do not read as the same size of thing.
final class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.width,
    required this.thumbnail,
    required this.armed,
    required this.onDragStart,
    required this.onDragDelta,
    required this.onDragEnd,
    required this.onOutputTap,
    required this.onInputTap,
    required this.onUnlinkTap,
    required this.onFieldChanged,
    required this.onDeleteTap,
  });

  final TextureNode node;
  final double width;
  final Uint8List? thumbnail;

  /// Whether this node's own output is the one a pending link is armed from
  /// — drawn in the accent colour so the person dragging a link can see
  /// which port they already picked.
  final bool armed;

  /// A drag on the header started, moved by a local-space delta, or ended.
  ///
  /// **`Listener`, not `GestureDetector.onPan*`.** A `GestureDetector` here
  /// would put this node's own pan recognizer into the same gesture arena as
  /// `InteractiveViewer`'s own scale recognizer for the canvas underneath
  /// it, and the canvas usually wins it outright — the drag call never
  /// fires at all. `Listener` reads raw pointer events, which no ancestor's
  /// recognizer can claim away from it.
  final ValueChanged<int> onDragStart;
  final void Function(int nodeId, Offset delta) onDragDelta;
  final ValueChanged<int> onDragEnd;
  final ValueChanged<int> onOutputTap;
  final void Function(int nodeId, String input) onInputTap;
  final void Function(int nodeId, String input) onUnlinkTap;
  final void Function(int nodeId, String field, Object? value) onFieldChanged;

  /// The header's own delete icon was tapped — this node id, for
  /// `RemoveNode`'s own single argument beyond the material.
  final ValueChanged<int> onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, TextureInputSocket> inputs = node.inputs;
    final Map<String, Object?> json = node.toJson();
    return Container(
      key: ValueKey<String>('textureNode-${node.id}'),
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Listener(
            key: ValueKey<String>('textureNodeHeader-${node.id}'),
            onPointerDown: (_) => onDragStart(node.id),
            onPointerMove: (PointerMoveEvent e) =>
                onDragDelta(node.id, e.localDelta),
            onPointerUp: (_) => onDragEnd(node.id),
            onPointerCancel: (_) => onDragEnd(node.id),
            child: SizedBox(
              height: _kHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        node.kind,
                        style: theme.textTheme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      key: ValueKey<String>('textureNodeDelete-${node.id}'),
                      onTap: () => onDeleteTap(node.id),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    GestureDetector(
                      key: ValueKey<String>('textureNodeOutput-${node.id}'),
                      onTap: () => onOutputTap(node.id),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: armed
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (final MapEntry<String, TextureInputSocket> entry
              in inputs.entries)
            SizedBox(
              height: _kPortRowHeight,
              child: Row(
                children: <Widget>[
                  GestureDetector(
                    key: ValueKey<String>(
                      'textureNodeInput-${node.id}-${entry.key}',
                    ),
                    onTap: () => onInputTap(node.id, entry.key),
                    child: Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(left: 4, right: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entry.value.from != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.value.from != null)
                    GestureDetector(
                      key: ValueKey<String>(
                        'textureNodeUnlink-${node.id}-${entry.key}',
                      ),
                      onTap: () => onUnlinkTap(node.id, entry.key),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.close, size: 12),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: Center(
              child: thumbnail != null
                  ? Image.memory(
                      thumbnail!,
                      key: ValueKey<String>('textureNodeThumbnail-${node.id}'),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : Container(
                      key: ValueKey<String>(
                        'textureNodeThumbnailPlaceholder-${node.id}',
                      ),
                      width: 64,
                      height: 64,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          for (final MapEntry<String, MaterialHint> entry in node.hints.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: KeyedSubtree(
                key: ValueKey<String>(
                  'textureNodeHint-${node.id}-${entry.key}',
                ),
                child: HintRow(
                  field: entry.key,
                  hint: entry.value,
                  value: json[entry.key],
                  onChanged: (Object? v) =>
                      onFieldChanged(node.id, entry.key, v),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Every wired input, drawn as a cubic Bézier from the source node's own
/// output port to the target's — the "primary" stroke `mat-13`'s own row
/// asks for at width 2, and the only stroke this painter ever draws.
final class _LinksPainter extends CustomPainter {
  const _LinksPainter({
    required this.graph,
    required this.positions,
    required this.widths,
    required this.color,
  });

  final TextureGraph graph;

  /// Each node's own top-left corner, by id — missing only for a node this
  /// frame has not laid out, which a link from or to it is skipped for.
  final Map<int, Offset> positions;
  final Map<int, double> widths;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final TextureNode node in graph.nodes) {
      final Offset? targetTopLeft = positions[node.id];
      if (targetTopLeft == null) continue;
      for (final MapEntry<String, TextureInputSocket> entry
          in node.inputs.entries) {
        final int? from = entry.value.from;
        if (from == null) continue;
        final Offset? sourceTopLeft = positions[from];
        final double? sourceWidth = widths[from];
        if (sourceTopLeft == null || sourceWidth == null) continue;
        final Offset start = _outputAnchor(sourceTopLeft, sourceWidth);
        final Offset end = _inputAnchor(node, entry.key, targetTopLeft);
        final double reach = (end.dx - start.dx).abs().clamp(40, 200);
        final Path path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + reach / 2,
            start.dy,
            end.dx - reach / 2,
            end.dy,
            end.dx,
            end.dy,
          );
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinksPainter oldDelegate) =>
      !identical(oldDelegate.graph, graph) ||
      oldDelegate.positions.length != positions.length ||
      oldDelegate.positions != positions ||
      oldDelegate.color != color;
}

/// `mat-13`'s own panel: a material's `TextureGraph`, node by node, over an
/// `InteractiveViewer` canvas — collapsed to one header row by default.
final class TextureGraphPanel extends StatefulWidget {
  const TextureGraphPanel({
    super.key,
    required this.graph,
    this.thumbnails = const <int, Uint8List>{},
    this.bakeProgress,
    this.initiallyExpanded = false,
    required this.onAddNode,
    required this.onLink,
    required this.onUnlink,
    required this.onSetNodeField,
    required this.onMoveNode,
    required this.onRemoveNode,
    required this.onBake,
    required this.onCancelBake,
  });

  /// The material's own graph. Never mutated here — every edit leaves
  /// through one of the six callbacks below and comes back in as a new
  /// [graph] once whoever owns the document has run the matching command.
  final TextureGraph graph;

  /// A 64×64-ready preview per node id, already decoded — see the library
  /// comment for why this widget does not bake one itself.
  final Map<int, Uint8List> thumbnails;

  /// `null` while idle; 0 to 1 while `BakeTextureGraph` runs in the
  /// background — [JobButton]'s own contract.
  final double? bakeProgress;

  final bool initiallyExpanded;

  /// The "Add" menu picked [kind]; [fields] and [position] are
  /// [AddNode.fields] and [AddNode.position] ready to hand straight to it.
  final void Function(
    String kind,
    Map<String, Object?> fields,
    (double x, double y) position,
  )
  onAddNode;

  /// A pending link was completed onto [nodeId]'s [input] socket, from
  /// [from]'s own output — [Link]'s own three arguments beyond the material.
  final void Function(int nodeId, String input, int from) onLink;

  /// [nodeId]'s [input] socket had its link removed — [Unlink]'s own two.
  final void Function(int nodeId, String input) onUnlink;

  /// [nodeId]'s [field] took [value] — [SetNodeField]'s own three.
  final void Function(int nodeId, String field, Object? value) onSetNodeField;

  /// [nodeId] was dragged to ([x], [y]) — [MoveNode]'s own three.
  final void Function(int nodeId, double x, double y) onMoveNode;

  /// The header's own delete icon was tapped on [nodeId] — [RemoveNode]'s
  /// own single argument beyond the material.
  final ValueChanged<int> onRemoveNode;

  /// The bake button was pressed while idle.
  final VoidCallback onBake;

  /// The bake button was pressed while [bakeProgress] was not null.
  final VoidCallback onCancelBake;

  @override
  State<TextureGraphPanel> createState() => _TextureGraphPanelState();
}

class _TextureGraphPanelState extends State<TextureGraphPanel> {
  late bool _expanded = widget.initiallyExpanded;

  /// A node mid-drag, or one the document has not confirmed back yet —
  /// cleared for a node the moment [widget.graph] itself carries a position
  /// for it, so an outside edit (undo, another view) is trusted over a stale
  /// gesture. The one piece of mutable state this widget keeps beyond
  /// [_expanded] and [_pendingLinkFrom], per the panel's own standards.
  final Map<int, (double x, double y)> _dragPositions =
      <int, (double x, double y)>{};

  /// The node id a link is armed from, or null — set by tapping an output
  /// port, cleared by completing (or abandoning, by tapping another output)
  /// the link onto an input port.
  int? _pendingLinkFrom;

  /// Whether a node header is mid-drag right now — while true,
  /// `InteractiveViewer`'s own panning is switched off, so a finger already
  /// moving one node does not also pan the canvas underneath it.
  bool _draggingNode = false;

  final TransformationController _transform = TransformationController();

  @override
  void didUpdateWidget(covariant TextureGraphPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.graph, widget.graph)) {
      for (final int id in widget.graph.positions.keys) {
        _dragPositions.remove(id);
      }
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  (double x, double y) _positionOf(TextureNode node, int index) =>
      _dragPositions[node.id] ??
      widget.graph.positions[node.id] ??
      (40.0 + 190.0 * (index % 4), 40.0 + 150.0 * (index ~/ 4));

  void _onNodeDragStart(int nodeId) {
    setState(() => _draggingNode = true);
  }

  /// [delta] is already `PointerEvent.localDelta` — local to this node's own
  /// `Listener`, which sits inside `InteractiveViewer`'s transformed child,
  /// so it already reads in the canvas's own untransformed units and needs
  /// no further division by the current zoom.
  void _onNodeDragDelta(int nodeId, Offset base, Offset delta) {
    setState(() {
      final (double x, double y) current =
          _dragPositions[nodeId] ?? (base.dx, base.dy);
      _dragPositions[nodeId] = (current.$1 + delta.dx, current.$2 + delta.dy);
    });
  }

  void _onNodeDragEnd(int nodeId) {
    setState(() => _draggingNode = false);
    final (double x, double y)? at = _dragPositions[nodeId];
    if (at != null) widget.onMoveNode(nodeId, at.$1, at.$2);
  }

  void _onOutputTap(int nodeId) {
    setState(
      () => _pendingLinkFrom = _pendingLinkFrom == nodeId ? null : nodeId,
    );
  }

  void _onInputTap(int nodeId, String input) {
    final int? from = _pendingLinkFrom;
    if (from == null) return;
    setState(() => _pendingLinkFrom = null);
    widget.onLink(nodeId, input, from);
  }

  Widget _buildBody(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<TextureNode> nodes = widget.graph.nodes;
    final Map<int, Offset> positions = <int, Offset>{};
    final Map<int, double> widths = <int, double>{};
    final AppLocalizations l = AppLocalizations.of(context);
    for (var i = 0; i < nodes.length; i++) {
      final TextureNode node = nodes[i];
      final (double x, double y) at = _positionOf(node, i);
      positions[node.id] = Offset(at.$1, at.$2);
      widths[node.id] = _nodeWidth(node);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: <Widget>[
              PopupMenuButton<String>(
                key: const ValueKey<String>('textureGraphAddNode'),
                tooltip: l.graphAddNode,
                onSelected: (String kind) => widget.onAddNode(
                  kind,
                  defaultTextureNodeFields(kind),
                  (40.0, 40.0),
                ),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  for (final String kind in textureNodeKinds)
                    PopupMenuItem<String>(value: kind, child: Text(kind)),
                ],
                child: const Icon(Icons.add_circle_outline, size: 18),
              ),
              const Spacer(),
              JobButton(
                label: AppLocalizations.of(context).bakeTextureButtonLabel,
                progress: widget.bakeProgress,
                onStart: widget.onBake,
                onCancel: widget.onCancelBake,
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRect(
            child: InteractiveViewer(
              key: const ValueKey<String>('textureGraphViewer'),
              transformationController: _transform,
              panEnabled: !_draggingNode,
              scaleEnabled: !_draggingNode,
              constrained: false,
              minScale: 0.25,
              maxScale: 3,
              boundaryMargin: const EdgeInsets.all(2000),
              child: SizedBox(
                width: 4000,
                height: 4000,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LinksPainter(
                          graph: widget.graph,
                          positions: positions,
                          widths: widths,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    for (final TextureNode node in nodes)
                      Positioned(
                        left: positions[node.id]!.dx,
                        top: positions[node.id]!.dy,
                        child: _NodeCard(
                          node: node,
                          width: widths[node.id]!,
                          thumbnail: widget.thumbnails[node.id],
                          armed: _pendingLinkFrom == node.id,
                          onDragStart: _onNodeDragStart,
                          onDragDelta: (int id, Offset delta) =>
                              _onNodeDragDelta(id, positions[id]!, delta),
                          onDragEnd: _onNodeDragEnd,
                          onOutputTap: _onOutputTap,
                          onInputTap: _onInputTap,
                          onUnlinkTap: widget.onUnlink,
                          onFieldChanged: widget.onSetNodeField,
                          onDeleteTap: widget.onRemoveNode,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      key: const ValueKey<String>('textureGraphPanel'),
      height: _expanded
          ? ModelerMetrics.propertiesMin
          : ModelerMetrics.textureGraphStripCollapsed,
      // `foregroundDecoration`, not `decoration`: `BoxDecoration.padding`
      // reserves space for a border it holds, which would shrink this
      // `Column` one pixel short of the exact row/propertiesMin height this
      // panel is measured against and overflow it. A 1 px hairline painted
      // on top of the content is not a border anything sits behind anyway.
      foregroundDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: const ValueKey<String>('textureGraphPanelHeader'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: SizedBox(
              // 44 collapsed, per `mat-33d`'s 2026-09-11 supplement; expanded,
              // the header stays [ModelerMetrics.row] so the extra 12 goes to
              // the canvas below it rather than to a header nobody asked to
              // grow.
              height: _expanded
                  ? ModelerMetrics.row
                  : ModelerMetrics.textureGraphStripCollapsed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(l.graphTitle, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }
}
