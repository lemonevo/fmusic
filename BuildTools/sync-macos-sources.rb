#!/usr/bin/env ruby
# Adds every Swift source under fmusic-macOS/ to the fmusic-macOS target and
# removes references to files that no longer exist. Keeps the generated Xcode
# project usable while the AppKit app grows file by file.
#
# Usage: ruby BuildTools/sync-macos-sources.rb

require "xcodeproj"

PBXGroup = Xcodeproj::Project::Object::PBXGroup

PROJECT = File.expand_path("../fmusic.xcodeproj", __dir__)
ROOT = File.expand_path("..", __dir__)
APP_DIR = "fmusic-macOS"
TARGET_NAME = "fmusic-macOS"

project = Xcodeproj::Project.open(PROJECT)
target = project.targets.find { |t| t.name == TARGET_NAME }
abort("target #{TARGET_NAME} not found") unless target
group = project.main_group.children.find { |c|
  c.is_a?(PBXGroup) && c.display_name == APP_DIR
}
abort("group #{APP_DIR} not found") unless group

on_disk = Dir.chdir(ROOT) do
  Dir.glob("#{APP_DIR}/**/*.swift").sort
end
disk_relative = on_disk.map { |path| path.delete_prefix("#{APP_DIR}/") }

# Remove refs whose files disappeared.
target.source_build_phase.files.dup.each do |build_file|
  ref = build_file.file_ref
  next unless ref
  path = ref.real_path.to_s
  next unless path.include?("/#{APP_DIR}/")
  relative = path.split("/#{APP_DIR}/", 2).last
  next if disk_relative.include?(relative)

  target.source_build_phase.files.delete(build_file)
  build_file.remove_from_project
  ref.remove_from_project
end

# Add missing refs (rebuilding the nested groups from the disk layout).
existing = {}
target.source_build_phase.files.each do |build_file|
  ref = build_file.file_ref
  next unless ref && ref.real_path.to_s.include?("/#{APP_DIR}/")
  existing[ref.real_path.to_s] = ref
end

disk_relative.each do |relative|
  absolute = File.join(ROOT, APP_DIR, relative)
  next if existing[absolute]

  parts = relative.split("/")
  parent = group
  parts[0..-2].each do |part|
    child = parent.children.find { |c| c.is_a?(PBXGroup) && c.display_name == part }
    child ||= parent.new_group(part, part)
    parent = child
  end
  ref = parent.new_file(parts.last)
  target.add_file_references([ref])
  puts "added #{relative}"
end

project.save
puts "sources: #{target.source_build_phase.files.count}"
