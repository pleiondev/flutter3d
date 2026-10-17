/// The last frame the viewport drew, pass by pass: what ran, in the order it
/// ran, what each cost, and what did not run and why.
///
/// **The editor drew every frame through a renderer and never looked at the
/// answer.** `Renderer.render` returns a `FrameResult` — each node of the
/// frame graph with its time, its draws, its triangles and its pipeline
/// switches, and every registered node that was skipped with the reason — and
/// `SceneSurface` threw it away after taking out the texture. It now hands
/// the result to `onFrame`; this is what the editor does with it.
///
/// What it shows is what a person asks when a level gets slow or a pass goes
/// missing: which pass, and why. The bars are wall-clock time inside each
/// node's own `execute`, the one number every backend has; the GPU's own time
/// is beside it where the device measures one.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show FrameResult, FramePass;

final class RenderGraphView extends StatelessWidget {
  const RenderGraphView({super.key, required this.frame});

  /// The frame to show, or null before the viewport has drawn one.
  final FrameResult? frame;

  static String _ms(int micros) => (micros / 1000.0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frame = this.frame;
    if (frame == null) {
      return Center(
        child: Text(
          'No frame drawn yet',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      );
    }
    final slowest = frame.passes.fold<int>(
      1,
      (int most, FramePass pass) => pass.micros > most ? pass.micros : most,
    );
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 11);
    return ListView(
      key: const ValueKey<String>('graph.rows'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      children: <Widget>[
        Text(
          '${frame.passes.length} passes · ${frame.drawCalls} draws · '
          '${frame.triangles} triangles · ${frame.culled} culled · '
          '${frame.lights} lights · ${_ms(frame.cpuMicros)} ms on the CPU',
          key: const ValueKey<String>('graph.totals'),
          style: TextStyle(color: scheme.onSurface, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          'anti-aliasing: ${frame.antiAliasing.isNone ? 'none' : _antiAliasing(frame)}'
          ' · exposure ${frame.exposure.toStringAsFixed(2)}'
          ' · ${frame.pipelineSwitches} pipeline switches',
          style: muted,
        ),
        const SizedBox(height: 8),
        for (final (index, pass) in frame.passes.indexed)
          _PassRow(
            key: ValueKey<String>('graph.pass.${pass.name}'),
            pass: pass,
            first: index == 0,
            share: pass.micros / slowest,
          ),
        if (frame.skipped.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text('NOT RUN THIS FRAME', style: muted.copyWith(letterSpacing: 1.2)),
          const SizedBox(height: 4),
          for (final skipped in frame.skipped)
            Padding(
              key: ValueKey<String>('graph.skipped.${skipped.name}'),
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${skipped.name} — ${skipped.reason.name}',
                style: muted,
              ),
            ),
        ],
      ],
    );
  }

  static String _antiAliasing(FrameResult frame) => <String>[
    if (frame.antiAliasing.msaaSamples > 1)
      'MSAA ×${frame.antiAliasing.msaaSamples}',
    if (frame.antiAliasing.fxaa) 'FXAA',
    if (frame.antiAliasing.temporal) 'temporal',
  ].join(', ');
}

/// One node of the graph: an arrow from the one before, its name, a bar of
/// its share of the slowest pass, and its numbers.
final class _PassRow extends StatelessWidget {
  const _PassRow({
    super.key,
    required this.pass,
    required this.first,
    required this.share,
  });

  final FramePass pass;
  final bool first;

  /// Its time over the slowest pass's, nought to one.
  final double share;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 11);
    final gpu = pass.gpuMicros;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(width: 16, child: Text(first ? '' : '→', style: muted)),
              Expanded(
                child: Text(
                  pass.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface, fontSize: 12),
                ),
              ),
              Text(
                '${RenderGraphView._ms(pass.micros)} ms'
                '${gpu == null ? '' : ' · GPU ${RenderGraphView._ms(gpu)} ms'}',
                style: muted,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: const ValueKey<String>('graph.bar'),
                      widthFactor: share.clamp(0.02, 1.0),
                      child: Container(
                        height: 4,
                        color: scheme.primary.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: Text(
                    '${pass.drawCalls} draws · ${pass.triangles} tris · '
                    '${pass.pipelineSwitches} switches',
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
