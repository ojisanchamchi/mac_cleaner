require 'spec_helper'
require 'stringio'

RSpec.describe MacCleaner::Cleaner do
  describe '#clean' do
    let(:sections) do
      [
        {
          name: "Section 1",
          sudo: false,
          targets: [
            { name: "Target 1", path: "/tmp/target1" }
          ]
        },
        {
          name: "Section 2",
          sudo: false,
          targets: [
            { name: "Target 2", path: "/tmp/target2" }
          ]
        }
      ]
    end

    before do
      stub_const("MacCleaner::Cleaner::CLEANUP_SECTIONS", sections)
    end

    it 'processes only confirmed sections in interactive mode' do
      input = StringIO.new("y\nn\n")
      cleaner = described_class.new(dry_run: true, interactive: true, input: input)

      allow(cleaner).to receive(:clean_target)

      cleaner.clean

      expect(cleaner).to have_received(:clean_target).with(sections[0][:targets][0], false).once
      expect(cleaner).not_to have_received(:clean_target).with(sections[1][:targets][0], false)
    end

    it 'skips cleanup when no sections are selected' do
      input = StringIO.new("n\nn\n")
      cleaner = described_class.new(dry_run: true, interactive: true, input: input)

      allow(cleaner).to receive(:clean_target)

      cleaner.clean

      expect(cleaner).not_to have_received(:clean_target)
    end
  end
end
