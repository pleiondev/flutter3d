/// The experiment document, `f3d.experiment`: a level, the substances it
/// uses by catalog id, the probes it reads, and a scenario of steps with the
/// readings each expects and the questions each asks
/// ([ExperimentDocument]); and the question a lesson or an experiment step
/// asks ([CheckQuestion]).
///
/// Plain Dart, as the rest of this package: a server reads an experiment
/// to replay and check a student's run with no Flutter SDK in its
/// container.
library;

// The probe an experiment reads, so its document is written with this
// import alone.
export 'package:flutter3d_sim/flutter3d_sim.dart' show Probe;
export 'src/experiment/check_question.dart';
export 'src/experiment/experiment_document.dart';
