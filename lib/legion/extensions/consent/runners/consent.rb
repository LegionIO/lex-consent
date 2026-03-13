# frozen_string_literal: true

module Legion
  module Extensions
    module Consent
      module Runners
        module Consent
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)

          def check_consent(domain:, action_type: :general, **)
            tier = consent_map.get_tier(domain)
            {
              domain:      domain,
              tier:        tier,
              allowed:     tier == :autonomous,
              needs_notify: tier == :act_notify,
              needs_consult: tier == :consult,
              human_only:  tier == :human_only
            }
          end

          def record_action(domain:, success:, **)
            consent_map.record_outcome(domain, success: success)
            {
              domain:       domain,
              success:      success,
              success_rate: consent_map.success_rate(domain),
              total:        consent_map.domains[domain][:total_actions]
            }
          end

          def evaluate_tier_change(domain:, **)
            recommendation = consent_map.evaluate_promotion(domain)
            current = consent_map.get_tier(domain)

            result = {
              domain:         domain,
              current_tier:   current,
              recommendation: recommendation,
              success_rate:   consent_map.success_rate(domain)
            }

            case recommendation
            when :promote
              result[:proposed_tier] = Helpers::Tiers.promote(current)
            when :demote
              result[:proposed_tier] = Helpers::Tiers.demote(current)
            end

            result
          end

          def apply_tier_change(domain:, new_tier:, **)
            unless Helpers::Tiers.valid_tier?(new_tier)
              return { error: :invalid_tier, valid_tiers: Helpers::Tiers::TIERS }
            end

            old_tier = consent_map.get_tier(domain)
            consent_map.set_tier(domain, new_tier)
            { domain: domain, old_tier: old_tier, new_tier: new_tier, changed: old_tier != new_tier }
          end

          def consent_status(domain: nil, **)
            if domain
              entry = consent_map.domains[domain]
              {
                domain:       domain,
                tier:         entry[:tier],
                success_rate: consent_map.success_rate(domain),
                total:        entry[:total_actions],
                eligible:     consent_map.eligible_for_change?(domain)
              }
            else
              { domains: consent_map.to_h, count: consent_map.domain_count }
            end
          end

          private

          def consent_map
            @consent_map ||= Helpers::ConsentMap.new
          end
        end
      end
    end
  end
end
