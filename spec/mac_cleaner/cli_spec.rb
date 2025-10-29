require 'spec_helper'

RSpec.describe MacCleaner::CLI do
  describe '--version' do
    it 'prints the current version' do
      expect { described_class.start(['--version']) }.to output("#{MacCleaner::VERSION}\n").to_stdout
    end
  end
end
