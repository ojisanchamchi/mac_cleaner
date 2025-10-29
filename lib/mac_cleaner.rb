require_relative "mac_cleaner/version"
require_relative "mac_cleaner/cli"
require_relative "mac_cleaner/cleaner"

module MacCleaner
  class Error < StandardError; end
  class TooManyOpenFilesError < Error; end
  # Your code goes here...
end
