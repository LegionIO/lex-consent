# frozen_string_literal: true

require 'legion/extensions/consent/client'

RSpec.describe Legion::Extensions::Consent::Client do
  let(:client) { described_class.new }

  it 'responds to consent runner methods' do
    expect(client).to respond_to(:check_consent)
    expect(client).to respond_to(:record_action)
    expect(client).to respond_to(:evaluate_tier_change)
    expect(client).to respond_to(:apply_tier_change)
    expect(client).to respond_to(:consent_status)
  end

  it 'round-trips earned autonomy lifecycle' do
    # Start with consult
    check = client.check_consent(domain: 'scheduling')
    expect(check[:tier]).to eq(:consult)

    # Build track record
    12.times { client.record_action(domain: 'scheduling', success: true) }

    # Evaluate
    eval_result = client.evaluate_tier_change(domain: 'scheduling')
    expect(eval_result[:recommendation]).to eq(:promote)

    # Apply
    client.apply_tier_change(domain: 'scheduling', new_tier: eval_result[:proposed_tier])
    check = client.check_consent(domain: 'scheduling')
    expect(check[:tier]).to eq(:act_notify)
  end
end
