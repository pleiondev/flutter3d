#
# The iOS side of the pointer lock: iPadOS with a mouse or a trackpad.
#
Pod::Spec.new do |s|
  s.name             = 'flutter3d_pointer_lock'
  s.version          = '0.5.0'
  s.summary          = 'Locks the mouse pointer and reports its motion as relative deltas.'
  s.description      = <<-DESC
Locks the pointer through prefersPointerLocked and reads its motion from GCMouse.
                       DESC
  s.homepage         = 'https://github.com/pleiondev/flutter3d'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'flutter3d' => 'noreply@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'flutter3d_pointer_lock/Sources/flutter3d_pointer_lock/**/*.swift'
  s.frameworks = 'GameController'

  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
