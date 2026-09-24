import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// Runs the light optimizer on [level] away from the frame.
///
/// **On another isolate**, because the optimizer draws every light from
/// every view in software and then searches: a second or two of work that,
/// on the isolate that draws the editor, would freeze the view for as long.
/// The level travels as its document, which is what it is anyway.
Future<LightPlan> planLights(Level level, List<LightView> views) {
  final document = level.toJson();
  return Isolate.run(
    () =>
        const LightOptimizer().optimize(Level.fromJson(document), views: views),
  );
}

/// Shows what [plan] would do — the two pictures side by side, the moves
/// and the numbers — and answers whether to apply it.
Future<bool> showLightPlan(BuildContext context, LightPlan plan) async {
  final pngs = plan.pngs;
  Widget picture(String label, Uint8List png) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Image.memory(
        png,
        width: plan.width * 2.0,
        height: plan.height * 2.0,
        filterQuality: FilterQuality.none,
      ),
      const SizedBox(height: 4),
      Text(label),
    ],
  );

  final apply = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('Fewer lights'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                picture('now', pngs.before),
                picture('after', pngs.after),
              ],
            ),
            const SizedBox(height: 12),
            Text(plan.says),
            for (final move in plan.moves) Text('· $move'),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep the lights'),
        ),
        TextButton(
          onPressed: plan.changes
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Apply'),
        ),
      ],
    ),
  );
  return apply ?? false;
}
