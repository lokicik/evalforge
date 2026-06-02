ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Work around Ruby 3.4.9 + Rails autoload issues on Windows by preloading
# Active Model validation constants before Active Record boots.
activemodel_root = Gem.loaded_specs.fetch("activemodel").full_gem_path
require "active_model"
Dir[File.join(activemodel_root, "lib/active_model/validations/*.rb")].sort.each do |file|
  require file
end
