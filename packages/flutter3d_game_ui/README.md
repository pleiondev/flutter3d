# flutter3d_game_ui

Every widget around a flutter3d game, one library each. A game takes the parts it wants by importing their libraries; `package:flutter3d_game_ui/flutter3d_game_ui.dart` exports all of them.

| Library | Was | What it is |
| --- | --- | --- |
| `hud.dart` | `flutter3d_addon_hud` | Heads-up display pieces for a game on flutter3d |
| `touch.dart` | `flutter3d_addon_touch` | Touch controls for a flutter3d game on a device with no keyboard |
| `access.dart` | `flutter3d_addon_access` | Accessibility for a game on flutter3d, past what the engine's settings already do |
| `screens.dart` | `flutter3d_addon_screens` | The screens a flutter3d game shows around its play |
| `settings.dart` | `flutter3d_game`'s settings panel | The settings panel, its sections and the rebinding list |
| `theme.dart` | `flutter3d_game`'s `GameUiTheme` and words | The colours every widget here is drawn in and the words it says |
| `photo_mode.dart` | `flutter3d_addon_photo_mode` | Photo mode for a game on flutter3d |
| `capture.dart` | `flutter3d_addon_capture` | Recording and sharing what was played on flutter3d |

## `hud.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_hud`.*

Heads-up display pieces for a game on flutter3d. Flutter widgets over the
picture rather than geometry in it: the engine hands back a texture and
Flutter composites over it, so a HUD costs no draw calls and gets text
layout, scaling and accessibility for nothing. Every piece takes values and
draws them; none reads a simulation.

| Piece | What it is | Came from |
|---|---|---|
| `HudPanel`, `HudLine` | A dark panel of labelled values in a fixed label column, tabular figures, an accent for what just became true | the racing demo's `hud_pieces.dart` |
| `HudTally`, `HudTallyStyle` | A big number over a small label, read by a screen reader as one thing (`"coins 12"`) | the platformer's and strategy's HUDs |
| `HudBanner` | A sentence across the middle of the screen | the platformer's and strategy's HUDs |
| `Speedometer` | Kilometres an hour from metres a second | racing |
| `MiniMap`, `MiniMapPainter` | A course flattened to a line, fitted to its box, a dot for everything on it | racing's `mini_map.dart` |
| `AutomapView`, `AutomapPainter` | The cells an `Automap` has revealed, centred on the player and turned the way they face; a different job from `MiniMap`, which fits a whole course | `flutter3d_game`, until 1.0.0-rc.1 |
| `MomentHint`, `MomentHints` | A sentence said once, the first time a step's events hold its moment | the dungeon's `first_shot_hint.dart`, as a rule |
| `lightBeacon`, `beaconGlow` | What already glows on an objective raised to a glow findable in the dark | the dungeon's `way_out_glow.dart` |
| `StereoHudPanel` | The same HUD on a stereo surface, redrawn from a `ValueListenable` | racing's `stereo_hud_panel.dart` |

**The stereo panel is here and not a package of its own.** It is one widget
of thirty lines over Flutter alone, and it shows the HUD a game already has;
a package for it would carry more pubspec than code.

There is no plugin. A HUD is a widget a game puts in its tree, and the
beacon is one call when a level is built, so nothing is installed into a
loop and the pubspec has no `flutter3d_plugins:` marker.

### Example

```dart
import 'package:flutter3d_game_ui/hud.dart';

Widget hud(Readout r) => Stack(
  children: <Widget>[
    Positioned(
      left: 16,
      top: 16,
      child: HudPanel(
        children: <Widget>[
          HudLine(label: 'TIME', value: clockText(r.time)),
          HudLine(label: 'BEST', value: clockText(r.best), accent: r.isBest),
        ],
      ),
    ),
    Positioned(
      right: 16,
      bottom: 16,
      child: Speedometer(metersPerSecond: r.speed),
    ),
    Positioned(
      left: 16,
      bottom: 16,
      child: MiniMap(outline: r.course, markers: r.positions),
    ),
  ],
);

// Said once a run, the first time the player jumps.
final hints = MomentHints<GameEvent>(<MomentHint<GameEvent>>[
  MomentHint<GameEvent>('Hold to jump higher.', when: (e) => e is Jumped),
]);
final sentence = hints.next(stepEvents); // null on every other step

// The exit, made findable in a dark room. Own materials only.
final exit = asset.instantiate(scene, shareMaterials: false);
lightBeacon(exit.meshes);
```

### Where it is used

- **Dungeon:** `lightBeacon` on the exit arch; the first-shot hint is a
  `MomentHint` whose sentence and moment stay in the game.
- **Platformer:** `HudTally` and `HudBanner` in its HUD and results.
- **Racing:** `HudPanel`, `HudLine`, `Speedometer` and `MiniMap` in its HUD,
  and `StereoHudPanel` on the stereo visor.
- **Strategy:** `HudTally` and `HudBanner`, in its own ink.

What stays in each game is the layout that puts the pieces on its screen and
the readout it reads them from.

## `touch.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_touch`.*

Touch controls for a flutter3d game on a device with no keyboard. Every
control writes the same `InputState` a key or a pad button does, through
`flutter3d_game`'s input layer, so the game steps the same either way and
cannot tell which it was.

| Widget | What it is | Writes |
|---|---|---|
| `TouchStick` | two analogue axes under a thumb | `setDualAxis`; cleared on release |
| `SteeringBand` | a strip a thumb slides along: one analogue axis | `setActionValue` on two actions, 0 to 1 each; withdrawn on release |
| `TouchButton` | an action held while a finger is on it, round or a pedal (`TouchButton.pedal`), labelled for a screen reader | `press` / `release` |
| `TouchToggle` | a control that is set rather than held; the caller owns whether it is on | the caller's tap |
| `TouchSlots`, `TouchSlot` | the numbered slots as buttons | `requestSlot` |
| `TouchControls` | a stick bottom left, a cluster of buttons bottom right, an optional row of switches over them, numbered slots up the right edge and a switch in the corner, placed by how often each is wanted | the above |
| `TouchDrive` | a band bottom left, pedals bottom right, one button in the far corner | the above |

Each control is owned by one pointer: a second finger landing on a band or a
button already held does not take it over. A control unmounted while held (a
settings panel opening over it) lets go of what it held, since no pointer-up
ever reaches a widget that is gone.

**One widget for each job.** Until 1.0.0-rc.1 the stick and its buttons
were `flutter3d_game`'s, with `TouchControls` laying out a stick and a row,
and this library had `TouchCluster` laying out a stick, a cluster, slots and
a corner switch, and `Pedal` holding an action the way `TouchButton` did.
`TouchCluster` is `TouchControls` now (its `toggle:` is `corner:`), and
`Pedal` is `TouchButton.pedal`.

### Not a plugin

These are widgets an application lays over its picture, so there is nothing
for a plugin host to install and the pubspec carries no `flutter3d_plugins:`
marker.

### Example

```dart
import 'package:flutter3d_game_ui/touch.dart';

// A vehicle.
TouchDrive(
  state: input,
  steerLeft: Drive.left,
  steerRight: Drive.right,
  throttle: Drive.throttle,
  brake: Drive.brake,
  handbrake: Drive.handbrake,
  corner: const TouchAction(Drive.tireSet, 'pit'),
);

// A game with many verbs.
TouchControls(
  state: input,
  corner: TouchToggle(label: 'map', on: mapOn, onTap: toggleMap),
  slots: const <TouchSlot>[TouchSlot('axe'), TouchSlot('bow', owned: false)],
  current: 0,
  buttons: const <TouchAction>[
    TouchAction(GameAction.use, 'use'),
    TouchAction(GameAction.jump, 'jump'),
    TouchAction(Actions.strike, 'strike'), // nearest the thumb
  ],
);
```

### Where it came from

The band, the pedals and their layout were the racing demo's
(`steering_band.dart`, `pedal.dart`, `touch_drive.dart`); the slots and the
corner of `TouchControls` are the dungeon demo's `touch_crypt.dart` layout
with the crypt's verbs taken out. The demos keep only which of their actions
go where: racing names its pit stop as the corner button, the dungeon lays
its verbs, its slot row and its map switch into `TouchControls`, and the
platformer's `TouchRunner` hands it three verbs and a sprint switch.

## `access.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_access`.*

Accessibility for a game on flutter3d, past what the engine's settings
already do.

| Piece | What it is | Came from |
|---|---|---|
| `RoleRings` | The high-contrast look's ring colour for a role (`'threat'`, `'pickup'`, `'key.brass'`), the one the player chose, read every frame | the dungeon's `high_contrast_rings.dart` |
| `RolesApart` | Which palette colour each colliding role should take so the roles seen together stay apart for the player's colour vision | new |
| `SpokenEvents`, `Spoken` | A view plugin that says a table of bus events aloud through Flutter's semantics, rate-limited by step | new (B6.23) |

**What it builds on.** `flutter3d_game` already corrects the whole picture
for a colour-vision deficiency (`ColorVisionLook`), lets a player pick each
role's colour from Okabe and Ito's eight (`ColorRoles`), and finds the pairs
a deficiency runs together (`ColorRoles.confusions`). This package does not
repeat any of it. `RolesApart` answers the question those leave the player
with, which colour to pick, as a settings panel's "choose for me" would.

### `SpokenEvents`: manifest

- **id** `flutter3d_addon_access.spoken_events` (a second table in one
  engine takes another `id`);
- **apiVersion** 1.0;
- **touches** `view`, so switching it is not written into a replay;
- **backends** all of them; **permissions** none; **dependsOn** nothing.

It subscribes on the bus's frame channel only: each event is said once,
after the frame's steps, and a step run again on a rollback is reconciled
rather than said twice. It writes nothing back, so a sighted player's game is
the same frame for frame with it installed. A sentence is a polite
announcement on the view (`SemanticsService.sendAnnouncement`), read by
whatever reader the player already uses in their own voice, and it goes
nowhere when no reader is on.

**The same sentence waits `quietSteps` steps** (sixty by default) before it
is said again; a different one is said at once. Steps rather than seconds,
so the limit needs no clock and is the same on a replay.

The pubspec has **no `flutter3d_plugins:` marker**: discovery builds a plugin
with no arguments, and a spoken table is the game's own, handed in code.

### Example

```dart
import 'package:flutter3d_game_ui/access.dart';

final loop = EngineLoop(
  input: input,
  plugins: <Flutter3dPlugin>[
    genre,
    SpokenEvents(<Spoken<BusEvent>>[
      Spoken<PlayerHurt>((_) => 'Hurt.'),
      Spoken<SecretFound>((_) => 'You found a secret.'),
      Spoken<PlayerDied>((_) => 'You died.'),
    ]),
  ],
);

// Rings in the colors the player chose.
final rings = RoleRings(myColours, config);
visuals.outlineOf ??= (Actor a) =>
    a.isAlive ? rings.of('threat', fallback: vermillion) : null;

// "Choose for me": move the keys of this level apart for the player's eyes.
RolesApart(myColours).apply(<String>['key.brass', 'key.iron'], config);
```

### Where it is used

- **Dungeon:** `CryptRings` asks `RoleRings` for every ring; what is worth
  a ring (a living monster, a pickup on the floor) stays the game's.
  `SpokenEvents` says a hurt, a secret and a death (`src/spoken.dart`).

## `screens.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_screens`.*

The screens a flutter3d game shows around its play: the card it opens on,
the credits, the ending and its scoreboard, a cutscene's overlay, and the
lens the play is seen through.

| Piece | What it is | Came from |
|---|---|---|
| `TitleSheet` | The game's name, a line about it, the controls the game hands in, the credits owed, a notice and how to begin; begins on a touch anywhere when asked | the platformer's and racing's `title_card.dart` |
| `Credit`, `CreditsSection` | One piece of work the game did not make, and the list of them on a screen | `flutter3d_game`, until 1.0.0-rc.1 |
| `CreditLedger` | A game's list of `Credit`s, with `owed` and `untraced` | `credits.dart` in five games |
| `LicenseRecord` | The `LICENSES.md` beside the models, read: a section a file with `Author`, `Source` and `Licence` rows, or one table a file | new; the games' tests compared the two by searching text |
| `EndingSheet`, `EndingTally`, `TallyView` | One sentence, the tallies, the credits and how to play again, full-screen | the endings of the platformer, the dungeon and racing |
| `CutsceneOverlay` | A sequence's fade, its subtitle and the way out | the dungeon |
| `TapToRestart` | The loss screen's one way out: a tap anywhere, or a key | `flutter3d_game`, until 1.0.0-rc.1 |
| `Lens` | One base projection, widened for speed and opened on a screen narrower than it was designed for | the platformer's `lens.dart` |

The credits are one file since 1.0.0-rc.1: `Credit` and `CreditsSection`
were `flutter3d_game`'s, the ledger and the record this library's.

These are widgets and values, not plugins: nothing here is installed into an
engine, and the pubspec has no `flutter3d_plugins:` marker.

### What stays the game's

What a game says on these screens: the lines about its keys, built from the
build it is (touch or keys, a captured pointer or not), the tallies it is
played for, and the sentence it ends on. A game keeps a small widget that
hands them to the sheet, and its tests render that widget both ways.

### Example

```dart
import 'package:flutter3d_game_ui/screens.dart';

const CreditLedger credits = CreditLedger(<Credit>[
  Credit(
    file: 'models/car.glb',
    work: 'Car Kit, race car',
    author: 'Kenney',
    source: 'https://kenney.nl/assets/car-kit',
    license: 'CC0 1.0',
    licenseUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
  ),
]);

TitleSheet(
  title: 'Ring',
  tagline: 'Five circuits and one car.',
  lines: touch ? touchLines : keyLines,
  credits: credits.owed,
  prompt: touch ? 'Touch to start.' : 'Press any key.',
  onBegin: touch ? begin : null,
);

EndingSheet(
  title: 'The season is yours.',
  tallies: <EndingTally>[EndingTally('circuits', '5'), EndingTally('best time', '1:23.456')],
  credits: credits.models,
  again: touch ? 'Tap to race again.' : 'Press R to race again.',
);

const Lens lens = Lens(
  PerspectiveProjection(fovY: 1.05, far: 220.0),
  designAspect: 16 / 9,
);
camera.projection = lens.at(width / height, extraFovY: speedWidening);
```

And in a test, the list held to the record on disk:

```dart
final record = LicenseRecord.parse(
  File('assets_src/models/LICENSES.md').readAsStringSync(),
);
expect(credits.disagreementsWith(record), isEmpty);
```

### The lens by aspect

`Lens.base` is drawn as written on a screen at least `designAspect` wide.
On a narrower one, a handset held upright or a square window, `fovYAt` opens
the vertical field of view until the horizontal one is what it was at the
design aspect, so what the player was shown on a wide screen is still there
on a tall one. With no `designAspect` the lens ignores the screen, which is
how the platformer uses it today.

## `photo_mode.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_photo_mode`.*

Photo mode for a game on flutter3d: the run stopped, a camera flown out of
where the game had it, a filter to pick and a picture larger than the
window.

The parts are the engine's. `PhotoCamera` (`flutter3d_sim`) keeps the
camera on a tether and out of the walls, `PhotoFilter` (`flutter3d_core`)
is a change to the composite's look, and `savePhoto` draws in tiles,
encodes and saves. This package holds them together and owns the keys while
photo mode is open, so a game only says how its own keys fly the camera.

| Piece | What it is |
|---|---|
| `PhotoMode` | Open or shut, busy while a picture is drawn, the filter, the keys it takes, the camera put on a `CameraNode` through the game's lens |
| `PhotoBar` | The strip along the bottom: the filter, the game's line of keys, and what the last picture said |
| `ActionPhotoControls` | The game's walking actions fly the camera, two actions of its own take it up and down, sprint is faster, the mouse turns it |
| `KeyPhotoControls` | WASD read off the keyboard as held, two keys for up and down, Shift faster, and optionally the arrows turning it |
| `PhotoControls` | The base of both, for a game with a third way to fly |

The keys photo mode owns are the same in every game: `[` and `]` step the
filter, `,` and `.` tilt the horizon, `-` and `=` zoom, Enter asks for a
picture at twice the window and Shift+Enter at four times. With
`takesEveryKey`, every other key is taken too, key-ups included: a game
whose keys would still be held in the run when it comes back (a throttle,
a dig) says so.

It is a library, not a plugin. Photo mode stops the loop rather than running
in it, and which key opens it is the game's.

### Example

```dart
import 'package:flutter3d_game_ui/photo_mode.dart';

final photo = PhotoMode(
  controls: const ActionPhotoControls(
    up: GameAction.jump,
    down: MyActions.duck,
    sensitivity: 0.0022, // the game's own look, radians a pixel
  ),
);

// P opens it where the player's eye is.
photo.enter(world: level.collision, eye: eye, target: target);

// Each frame while it is open: the paused loop drains nothing, so the look
// is taken here.
photo
  ..fly(dt, input: input, look: look)
  ..applyTo(cameraNode);

// The keys.
final said = photo.key(event, onCapture: (scale) => takePicture(scale));

// The look, filtered, and the strip.
final look = photo.active ? photo.look(game.look) : game.look;
if (photo.active) PhotoBar(mode: photo);
```

A keyboard-only game hands `KeyPhotoControls(up: keyE, down: keyQ,
turnRate: 0.9)` and calls `fly(dt)`; a game that turns the view with a drag
calls `turn(dx, dy, perPixel: lookSpeed)`.

### Where it came from

The dungeon, the platformer, racing and the sandbox each had a
`photo_mode.dart` of their own, the same class four times with different
keys. Each demo now keeps only a function that builds this one with its
keys, its lens and its line of help.

## `capture.dart`

*Until 1.0.0-rc.1, `flutter3d_addon_capture`.*

Recording and sharing what was played on flutter3d: a game filmed frame by
frame into PNGs for a reel or a clip, and the strip a finished run is shared
from and somebody else's is opened from.

| Piece | What it is |
|---|---|
| `Reel` | A renderer, a frame size and a folder: `reel.shot('falls')` is a shot in `<out>/falls` |
| `ReelShot` | `film(scene:, camera:, settings:)` draws the next frame with `savePhoto` and writes `frame_NNNN.png`, numbered from nought |
| `Reel.out`, `reelFrameStep`, `reelEase`, `reelFrameName` | Where a reel goes (the game's own folder, `reel` by default), a thirtieth of a second a frame, the eased camera move, the file name |
| `ShareStrip` | A button that files the run just played and says its code, and a field that opens a friend's code; both answer in a sentence |

It is a library, not a plugin. A reel steps the game itself, from an entry
point of its own, and sharing is a button on the game's screen: neither has
anything to register in a loop.

### Filmed, not recorded

A reel steps the game a fixed `reelFrameStep` a frame and draws each step at
full size however long that takes, so the frames are the same on a laptop
and a workstation and none is dropped. Each frame is drawn in one tile by
default, so nothing that reads its neighbours is cut at a tile's edge;
`tileWidth` and `tileHeight` draw it in tiles as photo mode does. A frame
that cannot be written throws: a reel with a hole in it is not a reel.

On the web each frame goes to the browser as a download, since there is no
folder to write into.

### Example

A game's `lib/reel_main.dart`, run with
`flutter run -d macos --profile -t lib/reel_main.dart --dart-define=REEL_OUT=<dir>`:

```dart
import 'package:flutter3d_game_ui/capture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final device = await openDevice(width: 1280, height: 720);
  final renderer = Renderer.create(device: device);
  final world = await openMyWorld(device, renderer);

  final shot = Reel(renderer: renderer).shot('falls');
  const frames = 180;
  for (var i = 0; i < frames; i++) {
    world.placeCamera(reelEase(i / (frames - 1)));
    world.step(reelFrameStep);
    await shot.film(scene: world.scene, camera: world.camera);
  }
  exit(0);
}
```

And sharing, where a run is over:

```dart
ShareStrip(
  onShare: lastRun == null ? null : () => share(lastRun),
  onOpen: (code) => openGhost(code),
  openLabel: 'Race it',
)
```

### Where it came from

Hollow, racing, Reef, strategy and Water each filmed their part of the 0.9
release reel with a `reel_main.dart` that carried its own PNG writer or its
own folder shelf; they keep only the shots now, and film them through
`Reel`. `ShareStrip` was the platformer's.
