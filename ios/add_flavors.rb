#!/usr/bin/env ruby
# This script adds iOS flavor (scheme) support to the Xcode project.
# It creates the build configurations Flutter expects when using --flavor.
#
# Usage: ruby ios/add_flavors.rb
# Requirements: gem install xcodeproj

require 'xcodeproj'

project_path = File.join(__dir__, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

flavors = ['dev', 'staging', 'prod']
base_configs = ['Debug', 'Release', 'Profile']

# --- Step 1: Add Build Configurations ---
# Flutter expects configurations named "Debug-<flavor>", "Release-<flavor>", "Profile-<flavor>"

flavors.each do |flavor|
  base_configs.each do |base|
    config_name = "#{base}-#{flavor}"
    
    # Skip if already exists
    next if project.build_configurations.any? { |c| c.name == config_name }
    
    # Find the base configuration to clone from
    base_config = project.build_configurations.find { |c| c.name == base }
    next unless base_config
    
    # Add to the project
    new_config = project.add_build_configuration(config_name, base == 'Debug' ? :debug : :release)
    new_config.build_settings.update(base_config.build_settings)
    
    puts "  Added project config: #{config_name}"
  end
end

# Add configurations to each target too
project.targets.each do |target|
  flavors.each do |flavor|
    base_configs.each do |base|
      config_name = "#{base}-#{flavor}"
      
      next if target.build_configurations.any? { |c| c.name == config_name }
      
      base_config = target.build_configurations.find { |c| c.name == base }
      next unless base_config
      
      new_config = target.add_build_configuration(config_name, base == 'Debug' ? :debug : :release)
      new_config.build_settings.update(base_config.build_settings)
      
      puts "  Added target '#{target.name}' config: #{config_name}"
    end
  end
end

project.save
puts "\n✅ Build configurations added successfully!"
puts "   Total configurations: #{project.build_configurations.count}"
