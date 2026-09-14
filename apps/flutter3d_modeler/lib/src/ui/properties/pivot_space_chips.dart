/// The point a rotation or a scale from the transform grid is centred on.
///
/// **Three chips because the row in `doc/model-editor-plan.md` asks for
/// three, and the third is a stand-in rather than a working control.** See
/// [PivotChip.cursor]'s own doc for why: `doc-33n` sketched a 3D cursor and a
/// `SetCursor` command and stopped short of building either, so there is no
/// position anywhere in the document that chip could hand to `RotateBy`.
/// Disabled rather than left off the row: a person reading the panel sees the
/// shape Blender's own pivot picker has, and the chip that does nothing says
/// so instead of pretending to.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../../display_modes.dart';

/// Where a rotation or a scale from the transform grid is centred.
class PivotAndSpaceChips extends StatelessWidget {
  const PivotAndSpaceChips({
    super.key,
    required this.pivot,
    required this.onPivot,
  });

  final PivotChip pivot;
  final ValueChanged<PivotChip> onPivot;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Where a turn or a scale from the boxes above is centred',
    child: SegmentedButton<PivotChip>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<PivotChip>>[
        ButtonSegment<PivotChip>(
          value: PivotChip.median,
          label: Text('Median'),
        ),
        ButtonSegment<PivotChip>(
          value: PivotChip.individual,
          label: Text('Individual'),
        ),
        ButtonSegment<PivotChip>(
          value: PivotChip.cursor,
          label: Text('3D Cursor'),
          enabled: false,
        ),
      ],
      selected: <PivotChip>{pivot},
      onSelectionChanged: (Set<PivotChip> picked) => onPivot(picked.first),
    ),
  );
}

/// Whose axes a rotation from the transform grid is given in.
class SpaceChips extends StatelessWidget {
  const SpaceChips({super.key, required this.space, required this.onSpace});

  final TransformSpace space;
  final ValueChanged<TransformSpace> onSpace;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Whose axes a turn from the boxes above is given in',
    child: SegmentedButton<TransformSpace>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<TransformSpace>>[
        ButtonSegment<TransformSpace>(
          value: TransformSpace.global,
          label: Text('Global'),
        ),
        ButtonSegment<TransformSpace>(
          value: TransformSpace.local,
          label: Text('Local'),
        ),
      ],
      selected: <TransformSpace>{space},
      onSelectionChanged: (Set<TransformSpace> picked) => onSpace(picked.first),
    ),
  );
}
