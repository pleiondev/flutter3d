/// `edu-06`'s own screen: the same lesson a step panel authors, drawn as a
/// stereo pair and stepped through by button rather than by editing.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

import 'lesson_player.dart';
import 'stereo_rig.dart';
import 'stereo_surface.dart';
import 'stereo_viewer.dart';

/// Wraps [StereoSurface] around a [LessonPlayer], with a "Previous"/"Next"
/// button pair driving it — the whole of "переключение шагов кнопкой" from
/// `edu-06`'s own acceptance line.
///
/// **No Cardboard is in this room.** [viewer] defaults to
/// [StereoViewer.cardboardV2] because that is the profile the format's own
/// acceptance names, but nothing here has held a real folded holder up to a
/// real phone — the honest claim is that the rig, the lesson and the button
/// are proven; the lens numbers are the published ones, unverified against
/// glass.
class LessonStereoView extends StatefulWidget {
  const LessonStereoView({
    super.key,
    required this.renderer,
    required this.scene,
    required this.rig,
    required this.player,
    this.nodes = const <String, SceneNode>{},
    this.viewer = StereoViewer.cardboardV2,
  });

  final Renderer renderer;
  final Scene scene;
  final StereoRig rig;
  final LessonPlayer player;
  final Map<String, SceneNode> nodes;
  final StereoViewer? viewer;

  @override
  State<LessonStereoView> createState() => _LessonStereoViewState();
}

class _LessonStereoViewState extends State<LessonStereoView> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        StereoSurface(
          renderer: widget.renderer,
          scene: widget.scene,
          rig: widget.rig,
          settings: () => const RenderSettings().forStereo(),
          onBeforeFrame: () =>
              widget.player.applyCurrent(widget.rig, nodes: widget.nodes),
          viewer: widget.viewer,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Previous step',
                onPressed: widget.player.isFirst
                    ? null
                    : () => setState(widget.player.previous),
              ),
              const SizedBox(width: 24.0),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: 'Next step',
                onPressed: widget.player.isLast
                    ? null
                    : () => setState(widget.player.next),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
