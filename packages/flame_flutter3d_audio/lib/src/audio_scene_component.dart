import 'package:flame/components.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, WidgetsBinding;
import 'package:flutter3d_audio/flutter3d_audio.dart';

/// A Flame game's sound: one [AudioScene], heard from the game's 3D camera,
/// silent until [open] is called and then through the speakers.
///
/// **What every bridged game with sound wrote for itself.** River Sortie kept
/// a scene, swapped it for a real one on the first take-off, stopped and
/// restarted its loops across the swap, moved its ears every frame and
/// updated the mix after everything else. This is that, once.
///
/// **Silent until [open], and [open] belongs to the player's first input.**
/// A browser lets a page make a sound only after the user has touched it, and
/// a game that opened its audio at launch has its first sound refused. Until
/// then everything plays into a [SilentBackend]: the calls a game makes are
/// the same, and nothing is heard. [SoundEmitterComponent]s move themselves
/// onto the real scene when it arrives, so a loop that was already meant to
/// be playing starts playing.
///
/// **Updated last.** Its priority is high, so the mix is worked out after
/// every emitter and every craft has moved this frame.
class AudioSceneComponent extends Component with UpdatesAtRoot {
  AudioSceneComponent({
    required this.bank,
    this.maxVoices = 16,
    this.opener,
    int priority = BridgePriority.audio,
  }) : super(priority: priority);

  /// Every sound the game can make, loaded when the speakers open.
  final SoundBank bank;

  /// How many voices may sound at once.
  final int maxVoices;

  /// How [open] opens the speakers: `openSpeakers` on [bank] unless given
  /// otherwise, as a test gives a silent pair it can listen to. It throws
  /// [AudioDeviceException] when there is no device, as `openSpeakers` does.
  final Future<Speakers> Function()? opener;

  /// Where the game hears from: [HasFlutter3d.camera3d], when the game has
  /// one, facing the way it looks. Otherwise wherever the game puts it.
  final AudioListener listener = AudioListener();

  /// What is played into: silent until [open], then the speakers.
  AudioScene get scene => _scene;
  AudioScene _scene = AudioScene(backend: SilentBackend());

  Speakers? _speakers;
  Future<void>? _opening;

  /// Set by [dispose], so an [open] still waiting on the device when the
  /// game let its sound go knows it has been overtaken.
  bool _disposed = false;

  /// Whether the speakers are open.
  bool get isOpen => _speakers != null;

  /// Opens the speakers and plays through them from the next frame. Call it
  /// from the player's first key, touch or button. Twice is once; a device
  /// that will not open leaves the game silent, which is a way to play.
  ///
  /// **A refusal can be asked again.** A browser refuses a page sound before
  /// the player has touched it, and an [open] refused once stayed refused
  /// for the rest of the game: the next key asks again. A [dispose] made
  /// while the device was still opening wins: the device is disposed as
  /// soon as it arrives. After [dispose] this does nothing.
  Future<void> open() {
    if (_disposed) return Future<void>.value();
    return _opening ??= _open();
  }

  Future<void> _open() async {
    final Speakers opened;
    try {
      opened = await (opener ?? _openSpeakers)();
    } on AudioDeviceException {
      if (!_disposed) _opening = null;
      return;
    }
    if (isRemoved || isRemoving || _disposed) {
      // Gone, or disposed, while the device was opening: nothing will let it
      // go after this.
      await opened.dispose();
      return;
    }
    _scene.stopAll();
    _scene = opened.scene;
    _speakers = opened;
    if (_paused) opened.pause();
  }

  bool _paused = false;

  /// Whether [pause] has silenced the game.
  bool get isPaused => _paused;

  /// Holds every sound where it is, loops included, until [resume]:
  /// `AudioBackend.pause`, so each voice goes on from where it was.
  ///
  /// **For a paused game.** Flame stops updating a paused game, this with
  /// it, and whatever was sounding went on sounding at its last loudness:
  /// an engine droning under the pause menu. A game that pauses its engine
  /// calls this; a game sent to the background is paused here by itself.
  /// The player's master volume is not touched, so a settings screen open
  /// over the pause still shows and sets the volume it set.
  void pause() {
    if (_paused) return;
    _paused = true;
    _scene.backend.pause();
  }

  /// Lets go on what [pause] held.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _scene.backend.resume();
  }

  AppLifecycleListener? _lifecycle;
  bool _pausedByLifecycle = false;

  @override
  void onMount() {
    super.onMount();
    _lifecycle = _listen();
  }

  /// Null where there is no app to leave: a game stepped in a plain Dart
  /// test, with no widgets binding.
  AppLifecycleListener? _listen() {
    final WidgetsBinding binding;
    try {
      binding = WidgetsBinding.instance;
    } on Object {
      return null;
    }
    return AppLifecycleListener(
      binding: binding,
      onHide: () {
        if (_paused) return;
        _pausedByLifecycle = true;
        pause();
      },
      onShow: () {
        if (!_pausedByLifecycle) return;
        _pausedByLifecycle = false;
        resume();
      },
    );
  }

  Future<Speakers> _openSpeakers() =>
      openSpeakers(bank: bank, maxVoices: maxVoices);

  /// Plays [sound] once, at [at] in the scene or at the listener.
  AudioEmitter play(SoundDef sound, {Vector3? at}) =>
      _scene.play(sound, at ?? listener.position);

  /// Stops every sound and disposes the speakers, if they are open; one
  /// still opening is disposed when it arrives. The game goes on, silent,
  /// and [open] does nothing after this. Called when the component is
  /// removed.
  Future<void> dispose() async {
    final speakers = _speakers;
    _disposed = true;
    _speakers = null;
    _opening = null;
    _scene.stopAll();
    _scene = AudioScene(backend: SilentBackend());
    await speakers?.dispose();
  }

  /// The listener onto the camera and the mix worked out, from the game's
  /// root wherever this was added: inside the world it ran before Flame's
  /// camera, and was heard from where the camera had been a frame before.
  @override
  void rootUpdate(double dt) {
    final game = findGame();
    if (game is HasFlutter3d && game.has3d) {
      final camera = game.camera3d;
      // The camera's turn in the world, not against its parent: a camera
      // riding a craft looked the craft's way plus its own, and was heard
      // looking only its own.
      final world = camera.worldMatrix;
      listener.position.setFrom(world.getTranslation());
      final forward = world.transformed3(Vector3(0.0, 0.0, -1.0))
        ..sub(listener.position);
      listener.aimAlong(listener.position, forward);
    }
    // The frame's seconds, so the mixer's snapshots blend and its ducks move;
    // with neither in use the mix is what it was.
    _scene.update(listener, dt: dt);
  }

  @override
  void onRemove() {
    _lifecycle?.dispose();
    _lifecycle = null;
    dispose();
    super.onRemove();
  }
}
