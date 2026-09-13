## 0.6.0

* **`par-02`: a diagnostic server, over the headless frame `ai-00` already
  proved.** `open`/`frame`/`pixel`/`passes`/`scanNaN` — a debug view of the
  renderer's own switches (surface buffer, shadow maps), `CpuDevice.
  readHdrPixels` for a value before it is clamped for display, and a scan
  that names the first non-finite pixel it finds.
* `CpuDevice.readHdrPixels` itself moved down into `flutter3d_cpu`, because
  `readPixels`'s own clamp answered `1.0` for a `NaN` rather than surfacing
  it — a diagnostic that read through the same clamp would be blind to the
  one thing it exists to catch.
