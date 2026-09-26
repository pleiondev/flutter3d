# flutter3d_showcase

Every capability of the engine gets a page of its own. Each page runs live,
says which version of the engine the capability appeared in, has a step-by-step
guide that builds it from nothing, and shows the file that is running. It runs on macOS (Impeller)
and in a browser (WebGL2, WebGPU where the browser has it).

    flutter run -d macos
    flutter run -d chrome --dart-define=FLUTTER3D_WEBGPU=true

Published at `https://flutter3d.pleion.dev/showcase/`; the guides are also pages
of the documentation site, written once and shown in both places.

`coverage.md` is the list of pages, read from the code of the engine. Read it
before adding one.

## What a page is

A page is four files and a row in a list:

| file | what |
|---|---|
| `lib/pages/<category>/<stem>.dart` | the demo. A `ShowcaseDemo`; regions marked `// #region name` |
| `lib/pages/<category>/<stem>.md` | the guide. Quotes the regions with `{{code name}}` |
| `lib/pages/<category>/registry.dart` | one line: `'<id>': MyDemo.new` |
| `lib/catalog/<category>.dart` | one `Feature(...)`: id, title, since, evidence |
| `test/pages/<category>_test.dart` | see below |

`<stem>` is the id with `-` written as `_`. The category directories are fixed
(`Category` in `lib/src/catalog/feature.dart`), and each is already declared as
an asset in `pubspec.yaml`, so adding a page touches no shared file.

**Do not edit** `lib/src/catalog/catalog.dart`, `lib/src/registry/registry.dart`,
`pubspec.yaml`, `lib/src/common/` or `lib/src/docs/`. They are the platform, and
a dozen pages are written against it at the same time. If a page needs a helper,
put it in the page's own file; it gets promoted when a second page wants it.

## The demo

The host opens the device, builds the renderer, turns the camera as you drag and
tells the person what their device declined. A page has only the lines about its
capability, so its guide can quote every line of it and the reader has nothing
to skip.

    final class BloomDemo extends ShowcaseDemo {
      double intensity = 0.6;

      @override
      Scene build(DemoContext context) { … }

      @override
      RenderSettings settings(DemoContext context) => RenderSettings(…);

      @override
      List<DemoControl> controls(DemoContext context) => […];

      @override
      void verify(Scene scene, FrameResult frame) { … }   // the page's claim
    }

`verify` is the claim the page makes, and its test checks it after one frame:
the thing the page is about actually happened (a shadow was drawn, a pass ran). A page whose
test only says "something is on the screen" proves the host, not the page.

A capability that is not a picture (a writer, a decoder's report) overrides
`customBody` and draws a widget instead of the viewport.

## Regions and the guide

    // #region light
    final sun = LightNode(name: 'sun', intensity: 3.0);
    // #endregion light

A guide is Markdown, in a small subset the app and the site both draw: headings,
paragraphs, lists, code, emphasis, links and `>` callouts (`> **Note.** …`,
`**Warning.**`, `**Tip.**`). No tables, images or HTML: `lintTutorial` refuses
them. It starts with `# Title` and has at least three steps, `## Step 1: …`
onward with no gaps, and every step quotes a region:

    {{code light}}          a region of this page
    {{code other-id#light}} a region of another page
    {{source}}              the whole file, markers out
    {{demo}} {{shot}}       a link and a picture on the site; nothing in the app

Every region a page has must be quoted, and every quote must resolve. Tests
check both, and `dart run tool/showcase_bundle.dart --out <dir>` stops on either.

Write the guide the way you would explain it to somebody at the next desk: what
this is for, then the smallest step that shows it, then the next. Run every
public sentence through the `humanizer` skill before it goes in.

## The version tag

    Feature(
      id: 'cascaded-shadows',
      title: 'Cascaded shadows',
      category: Category.shadows,
      summary: 'One sentence a person who has not read the engine would use.',
      since: '0.2.0',
      evidence: 'Cascaded directional shadows, cube shadows for point and spot',
      keywords: <String>['cascade', 'shadow map'],
    )

`since` is the version whose CHANGELOG says the capability arrived, and
`evidence` is words from that entry. The catalog test finds `evidence` under
`## <since>` of `evidenceFile` (default `packages/flutter3d/CHANGELOG.md`; name
the package's own for a capability of another package) and nowhere else. It also
looks for each of `keywords` in older sections; a word that already appears there
means the tag is too late.

`flutter3d_core` was never published before 0.7.0 and its history is under
`flutter3d`. Where no entry says a capability arrived, set `approximate: true`,
give the earliest place the record mentions it and write "no explicit origin" in
`evidence`; the chip then reads "since 0.5.1 or earlier".

`needs` lists what the page asks of the device (`Need.wireframe`, …). A device
that lacks one still opens the page, with a note that part of it will not show.

## Tests

- Page tests are generated. The loop in `test/pages_test.dart` already builds
  every page in the catalog on the software device, draws a frame, calls `verify`
  and checks that something was lit. Add a category test of your own only for a
  claim that loop cannot make.
- Every test states a claim and carries a `// Mutation:` comment naming a change
  that would make it pass while the behaviour is wrong.
- Run with `very_good test` (not `flutter test`); tests that draw are tagged
  `golden` and `skip_very_good_optimization`.

## Rules that bite

- No file name containing `camera` in `lib/` (the structure rule wants a
  `CameraRig` in it). Say `view` or `orbit`.
- No `static final Vector3` or `Matrix4`; make it a getter.
- No `ignore: avoid_print`. Say "pages" and "demos", not "N scenes" or "N goldens".
- Write `final` unless it changes.
- Nothing here names a backend. Ask the device (`GraphicsDevice.supports*`) or read
  the frame (`FrameResult`).

## For the site

    dart run tool/showcase_bundle.dart --out ../../site/.generated/showcase

writes `manifest.json`, `learn/<id>.md` (the guide with the code filled in) and
`src/<id>.dart` (the file without its markers). `site/tool/build.mjs` builds the
guide and source pages from those and nothing else.
