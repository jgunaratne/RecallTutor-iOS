require 'xcodeproj'
project_path = '/Users/junius/git/RecallTutor-iOS/RecallTutor.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'RecallTutor' }

main_group = project.main_group.children.find { |g| g.path == 'RecallTutor' }

if main_group.isa == 'PBXFileSystemSynchronizedRootGroup'
  puts "The RecallTutor group is a synchronized folder (PBXFileSystemSynchronizedRootGroup)."
  puts "Files created inside this directory are automatically added to the target by Xcode."
  puts "No modifications to the project file are needed."
else
  # Fallback for older Xcode projects
  services_group = main_group['Services'] || main_group.new_group('Services')
  file_ref1 = services_group.new_file('VideoService.swift')
  target.source_build_phase.add_file_reference(file_ref1, true)

  views_group = main_group['Views'] || main_group.new_group('Views')
  file_ref2 = views_group.new_file('VideoPlayerView.swift')
  target.source_build_phase.add_file_reference(file_ref2, true)
  project.save
  puts "Added files to Xcode project successfully."
end
