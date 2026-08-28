import 'pointer_lock_method_channel.dart';
import 'pointer_lock_platform_interface.dart';

/// The pointer capture a build outside the browser gets.
///
/// [MethodChannelPointerLock], whose `isSupported` is a whitelist: macOS has a
/// native side and nothing else does, so a Windows or Linux build answers false
/// instead of raising `MissingPluginException` at the first call. A game reads
/// that answer and turns the camera with a drag instead — which it did not do
/// before, because the platform list deciding that lived in the game and named
/// three desktops where the plugin serves one.
PointerLockPlatform defaultPointerLockPlatform() => MethodChannelPointerLock();
