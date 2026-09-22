import 'package:flutter/material.dart';
import 'package:flutter3d_lab/flutter3d_lab.dart';

/// `ls-e-01`'s missing half of the acceptance `doc/lesson-scenarios-plan.md`
/// names: "преподаватель видит на шкале rp-02, на каком шаге студент
/// выставил длину, отличную от задания" — a plain, 2D overlay rather than
/// another `WidgetSurface`, since this is a teacher's own screen, not
/// something the student in the 3D scene taps.
final class LabReviewPanel extends StatelessWidget {
  const LabReviewPanel({
    super.key,
    required this.assignedLength,
    required this.divergence,
    required this.stepsPerSecond,
  });

  /// What the assignment asked for — the length the run started at, unless
  /// a teacher's own assignment sets a different one.
  final double assignedLength;

  /// The first step the student's own recorded length differs from
  /// [assignedLength], or null when it never did.
  final LabDivergence? divergence;

  /// For turning a step number into seconds a teacher reads at a glance.
  final int stepsPerSecond;

  @override
  Widget build(BuildContext context) {
    final divergence = this.divergence;
    return AlertDialog(
      title: const Text('Lab review'),
      content: divergence == null
          ? Text(
              'No divergence: the recorded run kept the assigned length '
              '(${assignedLength.toStringAsFixed(2)} m) the whole way through.',
            )
          : Text(
              'Diverged at step ${divergence.step} '
              '(t = ${(divergence.step / stepsPerSecond).toStringAsFixed(1)} s): '
              'assignment asked for ${divergence.assigned.toStringAsFixed(2)} m, '
              'the student set ${divergence.actual.toStringAsFixed(2)} m.',
            ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// The button that opens [LabReviewPanel] — kept apart from the dialog
/// itself so `main.dart` decides where it sits without this file caring.
final class LabReviewButton extends StatelessWidget {
  const LabReviewButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    onPressed: onPressed,
    icon: const Icon(Icons.fact_check_outlined),
    label: const Text('Review'),
  );
}
