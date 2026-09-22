# Tombstone: sy_im_flutter_sdk is a Dart package as of 0.3.0 (no native plugin).
# Real native IM is provided by flutter_openim_sdk.
Pod::Spec.new do |s|
  s.name             = 'sy_im_flutter_sdk'
  s.version          = '0.4.2'
  s.summary          = 'Tombstone — use Dart OpenIMAdapter / flutter_openim_sdk'
  s.homepage         = 'https://github.com/carlcy/sy_im_flutter_sdk'
  s.license          = { :type => 'MIT' }
  s.author           = { 'SY' => 'dev@local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
