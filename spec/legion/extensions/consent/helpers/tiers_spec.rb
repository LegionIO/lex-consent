# frozen_string_literal: true

RSpec.describe Legion::Extensions::Consent::Helpers::Tiers do
  describe '.valid_tier?' do
    it 'accepts valid tiers' do
      %i[autonomous act_notify consult human_only].each do |tier|
        expect(described_class.valid_tier?(tier)).to be true
      end
    end

    it 'rejects invalid tiers' do
      expect(described_class.valid_tier?(:invalid)).to be false
    end
  end

  describe '.promote' do
    it 'promotes consult to act_notify' do
      expect(described_class.promote(:consult)).to eq(:act_notify)
    end

    it 'promotes act_notify to autonomous' do
      expect(described_class.promote(:act_notify)).to eq(:autonomous)
    end

    it 'cannot promote beyond autonomous' do
      expect(described_class.promote(:autonomous)).to eq(:autonomous)
    end
  end

  describe '.demote' do
    it 'demotes consult to human_only' do
      expect(described_class.demote(:consult)).to eq(:human_only)
    end

    it 'cannot demote beyond human_only' do
      expect(described_class.demote(:human_only)).to eq(:human_only)
    end
  end

  describe '.more_autonomous?' do
    it 'returns true when first tier is more autonomous' do
      expect(described_class.more_autonomous?(:autonomous, :consult)).to be true
    end

    it 'returns false when second tier is more autonomous' do
      expect(described_class.more_autonomous?(:human_only, :consult)).to be false
    end
  end
end
