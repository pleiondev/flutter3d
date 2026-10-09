---
description: Plugins for flutter3d, ours and the community's, read from pub.dev by topic, with the plugin API each is written against, the backends it runs on and whether it holds the conformance badge.
---

# Plugin catalogue

Everything outside the engine's kernel is a plugin: the genres, the elements, the post-processing addons, and whatever somebody else writes. A plugin is a `Flutter3dPlugin` with a manifest (its id, the plugin API version it was written against, its dependencies, the backends it runs on, whether it touches the simulation or only the view, and the permissions it asks for) and an `install` that registers what it adds through the host it is handed. The [architecture page](/core/architecture/) says how the host orders and switches them, and the [`flutter3d_plugin_api` README](https://github.com/pleiondev/flutter3d/blob/main/packages/flutter3d_plugin_api/README.md) is what a plugin is written against.

## Getting listed

The list below is read from pub.dev. A package appears in it when it carries the `flutter3d-plugin` topic, and what the table says about it comes from the `flutter3d_plugins:` block of its pubspec (`flutter3d:` before 1.0, still read until 2.0): the same block discovery reads to find the plugin class, plus a few keys the catalogue shows.

```yaml
topics:
  - flutter3d-plugin

flutter3d_plugins:
  plugin: package:wind/wind.dart#WindPlugin
  api: "1.0"              # the plugin API version the manifest names
  backends: [webgpu, cpu] # leave out for every backend
  touches: simulation     # or view
  demo: https://example.dev/wind/   # somewhere to run it in a browser
  conformance: true       # only when the badge below holds
```

The catalogue is fetched when the site is built from a fresh checkout by `npm run plugins`, and the result is committed beside this page, so a build with no network shows the list as it was last read and says when that was.

## The conformance badge

`flutter3d_conformance` has a suite a plugin runs against itself, the way a backend runs the device suite. The badge reads **flutter3d conformant**, and it means: `checkPluginConformance` passes every check on every declared backend, with a world given to determinism and a budget declared and kept, on the plugin API version in its manifest. The checks are that the manifest is valid, that the plugin switches off and on at a step boundary and leaves nothing registered behind, that two runs of one step from one state agree, that it installs on each backend it names and stays off on one it does not, and that it keeps the budget it declares.

A plugin with no world handed to the determinism check, or no budget declared, still passes what it can be asked; it does not get the badge, because the two checks that matter most to a replay were declined rather than run.

## Starting one

```bash
dart run flutter3d_build:create plugin --kind render-step --name soft_glow
```

`--kind` is one of `render-step`, `effect`, `genre`, `element` or `tool`. Each writes a package with the pubspec block above, a plugin class with its manifest, and a test that runs the conformance suite, so the badge is something a new plugin starts out able to earn.

{{plugin-catalogue}}
