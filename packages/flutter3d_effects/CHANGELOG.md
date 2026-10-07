## 0.9.0

- **A sea floor lit through its surface, and a surface seen from below.**
  `SeabedLook` draws a floor with the caustics the surface's own ripples
  focus on it — geometric optics, 1/|det(I + a·H)| with a = d·(1 − 1/n),
  blurred by the sun's half degree — and the colour water takes out of the
  light, red first, on the way down and back up to the eye. Over the floor
  the light averages to what fell on the surface. `LiquidLook`'s surface,
  seen from under it, is Snell's window: the sky in a cone of 97°, a mirror
  of the water outside it.

- **The physics core's water and fire, drawn, in a package of their own.**
  `LiquidView` draws one water of `flutter3d_physics_native`: its surface
  with the `LiquidLook` material — ripples the flow carries, Fresnel's sky,
  the sun's glint, colour by depth, froth where there is air — and the
  sheet off a lip as one sheet, its drops and its bubbles. `FireView` draws
  every fire of a world: tongues risen at the speed of a flame's gas along
  the core's leaning axis, lit smoke at the plume's speed, embers,
  firelight, and the watched bodies charring as they burn. Plain Dart, with
  the material shipped compiled as `LiquidLook.asset`.
