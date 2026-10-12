package dev.flutter3d.flutter3d_pointer_lock

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * The parts of the Android side a JVM can reach without a device.
 *
 *     cd example/android && ./gradlew :flutter3d_pointer_lock:testDebugUnitTest
 *
 * after the example has been built once, so Gradle knows the plugin.
 */
internal class Flutter3dPointerLockPluginTest {
  @Test
  fun the_channels_are_the_ones_every_other_platform_answers_on() {
    assertEquals("dev.flutter3d/flutter3d_pointer_lock", Flutter3dPointerLockPlugin.METHOD_CHANNEL)
    assertEquals(
        "${Flutter3dPointerLockPlugin.METHOD_CHANNEL}/events",
        Flutter3dPointerLockPlugin.EVENT_CHANNEL,
    )
    assertEquals(0, Flutter3dPointerLockPlugin.STATE_RELEASED)
    assertEquals(1, Flutter3dPointerLockPlugin.STATE_CAPTURED)
  }

  @Test
  fun supported_from_api_26_and_only_with_a_mouse() {
    assertFalse(Flutter3dPointerLockPlugin.supports(25, mouseConnected = true))
    assertFalse(Flutter3dPointerLockPlugin.supports(26, mouseConnected = false))
    assertTrue(Flutter3dPointerLockPlugin.supports(26, mouseConnected = true))
    assertTrue(Flutter3dPointerLockPlugin.supports(36, mouseConnected = true))
  }

  @Test
  fun every_sample_of_an_event_counts_and_is_in_logical_pixels() {
    // Three samples batched into one event: a reader taking only the last
    // would turn the camera by a third of the motion.
    val motion = Flutter3dPointerLockPlugin.motion(
        floatArrayOf(2f, 4f, 6f),
        floatArrayOf(-1f, 0f, -3f),
        density = 2f,
    )
    assertContentEquals(doubleArrayOf(6.0, -2.0), motion)
  }

  @Test
  fun a_density_of_zero_does_not_turn_the_motion_into_infinity() {
    assertContentEquals(
        doubleArrayOf(3.0, 1.0),
        Flutter3dPointerLockPlugin.motion(floatArrayOf(3f), floatArrayOf(1f), density = 0f),
    )
  }

  @Test
  fun the_method_channel_answers_every_call_dart_makes() {
    val plugin = Flutter3dPointerLockPlugin()
    for (method in listOf("capture", "release", "reset")) {
      val result = Mockito.mock(MethodChannel.Result::class.java)
      plugin.onMethodCall(MethodCall(method, null), result)
      Mockito.verify(result).success(null)
    }
    // No activity is attached here, so the capture had nothing to hold.
    assertFalse(plugin.captured)

    val captured = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(MethodCall("isCaptured", null), captured)
    Mockito.verify(captured).success(false)

    val unknown = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(MethodCall("getPlatformVersion", null), unknown)
    Mockito.verify(unknown).notImplemented()
  }
}
