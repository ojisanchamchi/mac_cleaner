
require_relative "lib/mac_cleaner/version"

Gem::Specification.new do |spec|
  spec.name          = "mac_cleaner"
  spec.version       = MacCleaner::VERSION
  spec.authors       = ["ojisanchamchi"]
  spec.email         = ["ojisanchamchi@gmail.com"]

  spec.summary       = %q{A script to clean your Mac.}
  spec.description   = %q{A script to clean your Mac and analyze disk space.}
  spec.homepage      = "https://github.com/ojisanchamchi/mac_cleaner"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == File.basename(__FILE__)) ||
        f.end_with?(".gem") ||
        f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)\z})
    end
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor"

  spec.add_development_dependency "bundler", "~> 2.7"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "rspec", "~> 3.13"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
