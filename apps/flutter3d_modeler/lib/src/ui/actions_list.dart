/// `anim-07`'s own `ActionsList`: the project's own [ProjectClip]s, one row
/// per action a person can select and play — [ModelProject.clips], the way
/// [ModifierStackPanel] already lists a stack's own slots, "Add" link
/// included so a brand new project is never stuck with zero clips and no way
/// to get one (`AddClip`, `anim-04`'s own row).
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'theme.dart';

/// One row per clip in [clips]. Selecting a row reports its index through
/// [onSelectClip]; the "Add" link, always present, reports through
/// [onAddClip].
class ActionsList extends StatelessWidget {
  const ActionsList({
    super.key,
    required this.clips,
    this.selectedClip,
    required this.onSelectClip,
    required this.onAddClip,
  });

  final List<ProjectClip> clips;
  final int? selectedClip;
  final ValueChanged<int> onSelectClip;
  final VoidCallback onAddClip;

  static String _labelOf(ProjectClip clip, int index) =>
      clip.name ?? 'clip $index';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (clips.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'No actions',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        )
      else
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: clips.length,
          itemBuilder: (BuildContext context, int index) => ListTile(
            dense: true,
            selected: index == selectedClip,
            selectedTileColor: kModelerScheme.primaryContainer,
            contentPadding: EdgeInsets.zero,
            title: Text(
              _labelOf(clips[index], index),
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelectClip(index),
          ),
        ),
      TextButton(
        onPressed: onAddClip,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, ModelerMetrics.row - 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Add'),
      ),
    ],
  );
}
