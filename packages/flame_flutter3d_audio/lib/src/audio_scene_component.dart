import 'package:flame/components.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';

/// What opening the speakers gives: the scene to play into, and how to
/// close the device under it. Null when there is no sound to be had.
typedef OpenedSpeakers = ({AudioScene scene, Future<void> Function() close});

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
class AudioSceneComponent extends Component {
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
  /// otherwise, as a test gives a silent pair it can listen to.
  final Future<OpenedSpeakers?> Function()? opener;

  /// Where the game hears from: [HasFlutter3d.camera3d], when the game has
  /// one, facing the way it looks. Otherwise wherever the game puts it.
  final AudioListener listener = AudioListener();

  /// What is played into: silent until [open], then the speakers.
  AudioScene get scene => _scene;
  AudioScene _scene = AudioScene(backend: SilentBackend());

  Future<void> Function()? _close;
  Future<void>? _opening;

  /// Whether the speakers are open.
  bool get isOpen => _close != null;

  /// Opens the speakers and plays through them from the next frame. Call it
  /// from the player's first key, touch or button. Twice is once; a device
  /// that will not open leaves the game silent, which is a way to play.
  Future<void> open() => _opening ??= _open();

  Future<void> _open() async {
    final opened = await (opener ?? _openSpeakers)();
    if (opened == null) return;
    if (isRemoved || isRemoving) {
      // Gone while the device was opening: nothing will close it after this.
      await opened.close();
      return;
    }
    _scene.stopAll();
    _scene = opened.scene;
    _close = opened.close;
  }

  Future<OpenedSpeakers?> _openSpeakers() async {
    final speakers = await openSpeakers(bank: bank, maxVoices: maxVoices);
    if (speakers == null) return null;
    return (scene: speakers.scene, close: speakers.backend.dispose);
  }

  /// Plays [sound] once, at [at] in the scene or at the listener.
  SoundEmitter play(SoundDef sound, {Vector3? at}) =>
      _scene.play(sound, at ?? listener.position);

  /// Closes the speakers, if they are open. The game goes on, silent.
  Future<void> close() async {
    final closing = _close;
    _close = null;
    _opening = null;
    _scene.stopAll();
    _scene = AudioScene(backend: SilentBackend());
    await closing?.call();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final game = findGame();
    if (game is HasFlutter3d && game.has3d) {
      final camera = game.camera3d;
      listener.position.setFrom(camera.readWorldPosition());
      final forward = camera.readRotation().asRotationMatrix().transform(
        Vector3(0.0, 0.0, -1.0),
      );
      listener.aimAlong(listener.position, forward);
    }
    _scene.update(listener);
  }

  @override
  void onRemove() {
    close();
    super.onRemove();
  }
}
