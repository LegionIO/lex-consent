# frozen_string_literal: true

require 'legion/extensions/consent/client'

RSpec.describe Legion::Extensions::Consent::Runners::Consent do
  let(:client) { Legion::Extensions::Consent::Client.new }

  describe '#check_consent' do
    it 'returns default tier for new domain' do
      result = client.check_consent(domain: 'email')
      expect(result[:tier]).to eq(:consult)
      expect(result[:needs_consult]).to be true
    end
  end

  describe '#record_action' do
    it 'records action outcome' do
      result = client.record_action(domain: 'email', success: true)
      expect(result[:success]).to be true
      expect(result[:total]).to eq(1)
    end

    it 'tracks success rate' do
      3.times { client.record_action(domain: 'email', success: true) }
      client.record_action(domain: 'email', success: false)
      result = client.record_action(domain: 'email', success: true)
      expect(result[:success_rate]).to eq(0.8)
    end
  end

  describe '#evaluate_tier_change' do
    it 'returns ineligible when not enough actions' do
      result = client.evaluate_tier_change(domain: 'email')
      expect(result[:recommendation]).to eq(:ineligible)
    end

    it 'recommends promotion with high success rate' do
      15.times { client.record_action(domain: 'calendar', success: true) }
      result = client.evaluate_tier_change(domain: 'calendar')
      expect(result[:recommendation]).to eq(:promote)
      expect(result[:proposed_tier]).to eq(:act_notify)
    end

    it 'recommends demotion with low success rate' do
      4.times { client.record_action(domain: 'risky', success: true) }
      8.times { client.record_action(domain: 'risky', success: false) }
      result = client.evaluate_tier_change(domain: 'risky')
      expect(result[:recommendation]).to eq(:demote)
      expect(result[:proposed_tier]).to eq(:human_only)
    end
  end

  describe '#apply_tier_change' do
    it 'changes tier' do
      result = client.apply_tier_change(domain: 'email', new_tier: :autonomous)
      expect(result[:new_tier]).to eq(:autonomous)
      expect(result[:changed]).to be true
    end

    it 'rejects invalid tier' do
      result = client.apply_tier_change(domain: 'email', new_tier: :invalid)
      expect(result[:error]).to eq(:invalid_tier)
    end
  end

  describe '#evaluate_all_tiers' do
    it 'returns zero evaluated for empty consent map' do
      result = client.evaluate_all_tiers
      expect(result[:evaluated]).to eq(0)
      expect(result[:promotions]).to eq([])
      expect(result[:demotions]).to eq([])
    end

    it 'includes promoted domains in promotions list' do
      15.times { client.record_action(domain: 'calendar', success: true) }
      result = client.evaluate_all_tiers
      expect(result[:promotions]).to include('calendar')
    end

    it 'includes demoted domains in demotions list' do
      4.times { client.record_action(domain: 'risky', success: true) }
      8.times { client.record_action(domain: 'risky', success: false) }
      result = client.evaluate_all_tiers
      expect(result[:demotions]).to include('risky')
    end

    it 'returns evaluated count matching number of known domains' do
      client.record_action(domain: 'email', success: true)
      client.record_action(domain: 'calendar', success: true)
      result = client.evaluate_all_tiers
      expect(result[:evaluated]).to eq(2)
    end

    it 'does not include ineligible domains in promotions or demotions' do
      client.record_action(domain: 'email', success: true)
      result = client.evaluate_all_tiers
      expect(result[:promotions]).not_to include('email')
      expect(result[:demotions]).not_to include('email')
    end
  end

  describe '#request_autonomous_approval' do
    it 'sets pending state for non-autonomous domain' do
      client.record_action(domain: 'email', success: true)
      result = client.request_autonomous_approval(domain: 'email')
      expect(result[:requested]).to be true
      expect(result[:proposed_tier]).to eq(:autonomous)
    end

    it 'rejects if already autonomous' do
      client.apply_tier_change(domain: 'email', new_tier: :autonomous)
      result = client.request_autonomous_approval(domain: 'email')
      expect(result[:requested]).to be false
      expect(result[:error]).to eq('already_autonomous')
    end

    it 'rejects if already pending' do
      client.request_autonomous_approval(domain: 'email')
      result = client.request_autonomous_approval(domain: 'email')
      expect(result[:requested]).to be false
      expect(result[:error]).to eq('already_pending')
    end
  end

  describe '#approve_promotion' do
    it 'applies pending tier change' do
      client.request_autonomous_approval(domain: 'email')
      result = client.approve_promotion(domain: 'email', approved_by: 'admin')
      expect(result[:approved]).to be true
      expect(result[:new_tier]).to eq(:autonomous)
      expect(result[:approved_by]).to eq('admin')
    end

    it 'rejects when no pending approval' do
      result = client.approve_promotion(domain: 'email', approved_by: 'admin')
      expect(result[:approved]).to be false
      expect(result[:error]).to eq('no_pending_approval')
    end
  end

  describe '#reject_promotion' do
    it 'clears pending state' do
      client.request_autonomous_approval(domain: 'email')
      result = client.reject_promotion(domain: 'email', rejected_by: 'admin', reason: 'not ready')
      expect(result[:rejected]).to be true
      expect(result[:reason]).to eq('not ready')
    end

    it 'rejects when no pending approval' do
      result = client.reject_promotion(domain: 'email', rejected_by: 'admin')
      expect(result[:rejected]).to be false
    end
  end

  describe '#expire_pending_approvals' do
    it 'expires stale approvals' do
      client.request_autonomous_approval(domain: 'email')
      result = client.expire_pending_approvals(timeout: 0)
      expect(result[:expired]).to eq(1)
    end

    it 'does not expire fresh approvals' do
      client.request_autonomous_approval(domain: 'email')
      result = client.expire_pending_approvals(timeout: 999_999)
      expect(result[:expired]).to eq(0)
    end
  end

  describe '#evaluate_and_apply_tiers' do
    it 'returns summary with zero counts for empty map' do
      result = client.evaluate_and_apply_tiers
      expect(result[:evaluated]).to eq(0)
      expect(result[:applied_promotions]).to eq(0)
      expect(result[:applied_demotions]).to eq(0)
      expect(result[:approval_requests]).to eq(0)
    end

    it 'auto-applies non-autonomous promotions' do
      15.times { client.record_action(domain: 'calendar', success: true) }
      result = client.evaluate_and_apply_tiers
      expect(result[:applied_promotions]).to eq(1)
      status = client.consent_status(domain: 'calendar')
      expect(status[:tier]).to eq(:act_notify)
    end

    it 'requests approval for autonomous promotions instead of auto-applying' do
      client.apply_tier_change(domain: 'calendar', new_tier: :act_notify)
      # Backdate last_changed_at to bypass the 24h cooldown
      map = client.send(:consent_map)
      map.domains['calendar'][:last_changed_at] = Time.now.utc - 100_000
      15.times { client.record_action(domain: 'calendar', success: true) }
      result = client.evaluate_and_apply_tiers
      expect(result[:approval_requests]).to eq(1)
      expect(result[:applied_promotions]).to eq(0)
      status = client.consent_status(domain: 'calendar')
      expect(status[:tier]).to eq(:act_notify)
    end

    it 'auto-applies demotions' do
      4.times { client.record_action(domain: 'risky', success: true) }
      8.times { client.record_action(domain: 'risky', success: false) }
      result = client.evaluate_and_apply_tiers
      expect(result[:applied_demotions]).to eq(1)
      status = client.consent_status(domain: 'risky')
      expect(status[:tier]).to eq(:human_only)
    end
  end

  describe '#consent_status' do
    it 'returns domain-specific status' do
      client.record_action(domain: 'email', success: true)
      result = client.consent_status(domain: 'email')
      expect(result[:tier]).to eq(:consult)
      expect(result[:total]).to eq(1)
    end

    it 'returns all domains when no domain specified' do
      client.record_action(domain: 'email', success: true)
      client.record_action(domain: 'calendar', success: true)
      result = client.consent_status
      expect(result[:count]).to eq(2)
    end
  end
end
