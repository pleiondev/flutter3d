/// Analyzer rules for code a flutter3d fixed step runs.
///
/// Enabled as an analysis server plugin from `analysis_options.yaml` — see
/// the package README — which loads `main.dart`. This library is for tooling
/// that runs the rules itself: [scanSimulationCode] over a parsed or resolved
/// unit, and [simulationRules] as the analysis server takes them.
library;

export 'src/rules.dart';
export 'src/simulation_scan.dart';
