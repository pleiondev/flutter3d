## 1.0.0-rc.1

- **The first release: the elements' simulation, out of
  `flutter3d_effects`.** `ElementsSimulation`, `Fires`, `Igniter`,
  `WaterBody`, `Follower`, `TrackedBody`, `Solid`, `Bed`,
  `ElementHeightfield`, `ElementPose`, `ElementsListener`,
  `ElementsSimulationPlugin`, the plugin element's hook (`ElementHook`,
  `ElementStep`, `ElementFrame`, `ElementFields`, `NativeElementFields`,
  `ElementBody`, `installElement`, `ElementPlugin`), the registries
  (`ElementSwitches`, `ElementEventKinds`), the switches (`ElementsSteps`,
  `FireSteps`, `LiquidSteps`) and the events (`ElementEvent` and the
  listener's eight, `declareElementEvents`) were declared there in 0.9 and
  are declared here now. `flutter3d_effects` does not re-export them:
  import this package. New in 1.0, so no 0.8 code names them.
- **A body and a water hold nothing that draws them.** `TrackedBody.look`
  and `WaterBody.view` and `WaterBody.look` are gone;
  `ElementsSimulation.track` takes no look. The view keeps them:
  `Elements.lookOf`, `Elements.viewOf` and `Elements.waterLookOf` in
  `flutter3d_effects`.
- **`ElementsSimulation.addWater` pours a water with no view**, and
  `waters`, `waterAt` and `remove` hold it, so a server steps the waters a
  game draws. `Elements.addWater` pours through it.
- **`SmokePlume`**: the plume's virtual origin, width, centreline speed and
  optical depth, which `seenThroughSmoke` reads and `FireView.plumeDepth`
  draws with. The numbers are the ones `FireView` had.
