## 1.0.0-rc.1

- **Depends on `flutter3d_foundation` instead of the plugin API**, for the
  exception family `MaterialBuildException` is of.

- **New: the material compiler a build hook needs, on its own.**
  `compileMaterial`, `MaterialCompilers`, `MaterialBuildException` and
  `generateMaterialAccessors` moved here from `flutter3d_build`, which still
  exports them under the same names. A package that compiles its own
  materials in its build hook, as `flutter3d_effects` does, depends on this
  and no longer resolves `flutter3d_build`'s converters, MCP servers and
  `dart_mcp` into every game that depends on it.
