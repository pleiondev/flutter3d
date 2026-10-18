/// Analyzer rules for code a flutter3d fixed step runs.
///
/// Enabled as an analysis server plugin from `analysis_options.yaml` — see
/// the package README — which loads `main.dart`. This library is for tooling
/// that runs the rules itself: [scanSimulationCode] and [scanEngineImports]
/// over a parsed or resolved unit, and the rules' names in [SimulationRules]
/// and [EngineImportRules].
///
/// **The rules as the analysis server takes them are not exported.** They
/// extend `AnalysisRule` of `analysis_server_plugin`, a package at 0.x whose
/// every minor may change that class; a 1.x library that exported them would
/// break with it. The analyzer loads `main.dart`'s `plugin`, which is all it
/// needs.
library;

export 'src/import_scan.dart';
export 'src/simulation_scan.dart';
