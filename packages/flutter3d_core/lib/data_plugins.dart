/// What a data plugin's materials and render steps need from the renderer:
/// the `materials` and `renderSteps` sections of a `.f3dplugin` document
/// ([materialsSection], [renderStepsSection], [renderDataSections]), and
/// [RuntimeShaders], which compiles them where the backend compiles at run
/// time.
///
/// **Here, beside the renderer, and not in `flutter3d_plugin_runtime`.**
/// The runtime reads a document's sections through the plugin API's
/// `DataSectionRegistry` and depends on no subsystem a section installs
/// into, so a server that replays a run with data plugins in it resolves
/// the interpreter without the render core. An engine that draws registers
/// these sections with the rest:
///
/// ```dart
/// final loader = DataPluginLoader(
///   sections: DataSections(<DataSection>[
///     ...renderDataSections,
///     entityKindsSection, // flutter3d_sim
///   ]),
/// );
/// ```
library;

export 'src/data_plugin/material_wgsl.dart';
export 'src/data_plugin/render_sections.dart';
export 'src/data_plugin/runtime_shaders.dart';
