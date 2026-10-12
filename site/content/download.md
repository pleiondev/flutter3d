---
description: Where to get the level editor and the model editor: in a browser first, built from source second, and the native builds with what each platform is supported for.
---

# Download the editors

There are two editors. The level editor writes the level documents the games read, and scaffolds a new project from a template. The model editor (the modeller) makes and rigs the models. Both run in a browser, which is the quickest way to try them, and both build from source on a desktop.

## In a browser

| Editor | Where | What the browser build cannot do |
|---|---|---|
| The level editor | <https://flutter3d.pleion.dev/demo/editor/> | A page has no disk, so the documents live in the page: a level opens from a file you pick, saving downloads it, and a new project from a template downloads once as a `.zip`. Play cannot start a game; it attaches to one you run yourself, over the VM service address the game prints |
| The model editor | <https://models.pleion.dev> | Saves into a cabinet the account keeps rather than to your disk; [Trying it](/modeler/demo/) has the rest |

In a browser both draw through WebGPU, and through WebGL2 where the browser hands out no WebGPU adapter. Chrome is what they are checked on; Safari and Firefox are best effort.

## Built from source

The editors are applications in the repository, so building one is a checkout and `flutter run`. The [quickstart](/quickstart/#working-on-the-engine-itself) has the checkout.

```bash
git clone https://github.com/pleiondev/flutter3d.git
cd flutter3d
flutter pub get

(cd apps/flutter3d_editor && flutter run -d macos)    # the level editor
(cd apps/flutter3d_modeler && flutter run -d macos)   # the model editor

# A build to keep, where the runner is: macos, windows or linux.
(cd apps/flutter3d_editor && flutter build macos --release)
```

The level editor has runners for macOS, Windows and Linux; the modeller for macOS and the browser.

## Native builds

From 1.0.0-rc.1 on, each tagged release is meant to carry the level editor as a macOS `.dmg`, a Windows `.zip` and a Linux `.tar.gz`, with a `SHA256SUMS` file beside them, on the [GitHub release](https://github.com/pleiondev/flutter3d/releases) of the tag. The workflow that builds them is not in the repository yet, so for now the two ways above are the only ones; this section changes when the first archive is attached to a release.

What each platform is supported for is [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)'s table, and the editor is held to it like the games are:

| Platform | Draws with | Status |
|---|---|---|
| macOS | Impeller on Metal | Supported: used every day, fixed in a patch when it breaks |
| Windows | Impeller on Vulkan | Best effort: CI builds it on every push, and nobody has used a Windows build for real yet |
| Linux | The software rasteriser, unless the runner turns Flutter GPU on | Best effort for the editor; CI runs every test suite on Linux, and Impeller there is not yet green |
| Web (Chrome) | WebGPU, or WebGL2 | Supported on WebGPU, CI on WebGL2 |
| Web (Safari, Firefox) | WebGPU, or WebGL2 | Best effort |

### An unsigned build

Until a build is signed and notarised, the system will not open it by a double-click, and says it cannot check the developer. Check the archive against `SHA256SUMS` first, then tell the system you mean it.

macOS:

```bash
shasum -a 256 -c SHA256SUMS --ignore-missing
xattr -dr com.apple.quarantine editor.app
```

`xattr` takes off the quarantine flag the browser put on the download, which is what Gatekeeper reads. It changes nothing else about the app.

Windows: SmartScreen shows "Windows protected your PC"; *More info*, then *Run anyway*. Check the archive first with `certutil -hashfile <file> SHA256` against `SHA256SUMS`.

Linux: `sha256sum -c SHA256SUMS --ignore-missing`, unpack, and run the binary in the bundle's top directory.

## Next

- [The level editor](/core/editor/): what it does with a level, and the template picker
- [Your first project](/first-project/): a project of your own from a template
- [The modeller](/modeler/): ten modes over one document
