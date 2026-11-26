require 'xcodeproj'
project=Xcodeproj::Project.open('frontend/ios/Runner.xcodeproj')
raise 'Target already exists; review manually' if project.targets.any?{|t|t.name=='WizUserLiveActivityExtension'}
runner=project.targets.find{|t|t.name=='Runner'}
group=project.main_group.new_group('LiveActivityExtension','LiveActivityExtension')
files=%w[OrderLiveActivityAttributes.swift WizUserLiveActivity.swift WizUserLiveActivityBundle.swift].map{|f|group.new_file(f)}
group.new_file('Info.plist')
target=project.new_target(:app_extension,'WizUserLiveActivityExtension',:ios,'16.1')
files.each{|f|target.source_build_phase.add_file_reference(f)}
target.add_system_framework('ActivityKit');target.add_system_framework('SwiftUI')
runner.source_build_phase.add_file_reference(files.first)
runner_group=project.main_group.find_subpath('Runner')
channel=runner_group.new_file('LiveActivityChannel.swift');runner.source_build_phase.add_file_reference(channel)
runner.add_system_framework('ActivityKit')
runner.add_dependency(target)
embed=runner.new_copy_files_build_phase('Embed App Extensions');embed.dst_subfolder_spec='13'
embed.add_file_reference(target.product_reference)
# Embed before Flutter's Thin Binary phase to avoid a build dependency cycle.
index=runner.build_phases.index{|p|p.display_name=='Thin Binary'}||runner.build_phases.length
runner.build_phases.delete(embed);runner.build_phases.insert(index,embed)
target.build_configurations.each do |cfg|
 cfg.build_settings.merge!({'PRODUCT_NAME'=>'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER'=>'com.wiz.wizuserapp.liveactivity','INFOPLIST_FILE'=>'LiveActivityExtension/Info.plist','GENERATE_INFOPLIST_FILE'=>'NO','SWIFT_VERSION'=>'5.0','SKIP_INSTALL'=>'YES','DEVELOPMENT_TEAM'=>'F6B9QH9W82','CODE_SIGN_STYLE'=>'Automatic','CURRENT_PROJECT_VERSION'=>'1','MARKETING_VERSION'=>'1.0.0','TARGETED_DEVICE_FAMILY'=>'1,2'})
end
project.save
puts 'Added extension while preserving Runner iOS deployment settings.'
