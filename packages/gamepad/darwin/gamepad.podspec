#
# The Apple side of the gamepad package, shared by macOS and iOS.
#
# One source directory for both, which is what `sharedDarwinSource` in the
# pubspec buys: `GameController.framework` is the same framework on both, and a
# second copy of this file would be a second copy to fix.
#
Pod::Spec.new do |s|
  s.name             = 'gamepad'
  s.version          = '0.1.0'
  s.summary          = "A gamepad's sticks, triggers and buttons."
  s.description      = <<-DESC
Reads a gamepad through GameController.framework and reports it as a snapshot.
                       DESC
  s.homepage         = 'https://github.com/dzolotov/flutter3d'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'flutter3d' => 'noreply@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'gamepad/Sources/gamepad/**/*'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
