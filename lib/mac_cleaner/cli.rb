require 'thor'

module MacCleaner
  class CLI < Thor
    class_option :dry_run, type: :boolean, aliases: "-n", desc: "Perform a dry run without deleting files"
    class_option :sudo, type: :boolean, desc: "Run with sudo for system-level cleanup"
    class_option :interactive, type: :boolean, aliases: "-i", desc: "Interactively choose sections to clean before executing"

    map %w[--version -v] => :version

    desc "clean", "Clean up your Mac"
    def clean
      require_relative 'cleaner'
      cleaner = MacCleaner::Cleaner.new(
        dry_run: options[:dry_run],
        sudo: options[:sudo],
        interactive: options[:interactive]
      )
      cleaner.clean
    end

    desc "version", "Print the mac_cleaner version"
    def version
      puts MacCleaner::VERSION
    end

    desc "analyze [PATH]", "Analyze disk space"
    def analyze(path = "~")
      require_relative 'analyzer'
      analyzer = MacCleaner::Analyzer.new(path: path)
      analyzer.analyze
    end

    def self.exit_on_failure?
      false
    end
  end
end
