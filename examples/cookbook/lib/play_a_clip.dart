/// Play one of a model's animation clips, and switch to another in place.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: PlayAClip()));

class PlayAClip extends StatefulWidget {
  const PlayAClip({super.key});

  @override
  State<PlayAClip> createState() => _PlayAClipState();
}

class _PlayAClipState extends State<PlayAClip> {
  static const List<String> clips = <String>['Idle', 'Walking', 'Dance'];
  String clip = clips.first;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Scene3D(
      children: <Widget>[
        const OrbitCamera3D(distance: 6.0),
        const Light3D.sun(),
        // A rebuild changes the clip of the instance already loaded.
        Model3D(
          source: 'assets_src/models/RobotExpressive.glb',
          animation: clip,
        ),
      ],
    ),
    bottomNavigationBar: SegmentedButton<String>(
      segments: <ButtonSegment<String>>[
        for (final name in clips) ButtonSegment(value: name, label: Text(name)),
      ],
      selected: <String>{clip},
      onSelectionChanged: (picked) => setState(() => clip = picked.single),
    ),
  );
}
