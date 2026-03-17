# frozen_string_literal: true

module Legion
  module Extensions
    module Consent
      module Runners
        module Consent
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)

          def check_consent(domain:, _action_type: :general, **)
            tier = consent_map.get_tier(domain)
            Legion::Logging.debug "[consent] check: domain=#{domain} tier=#{tier} allowed=#{tier == :autonomous}"

            {
              domain:        domain,
              tier:          tier,
              allowed:       tier == :autonomous,
              needs_notify:  tier == :act_notify,
              needs_consult: tier == :consult,
              human_only:    tier == :human_only
            }
          end

          def record_action(domain:, success:, **)
            consent_map.record_outcome(domain, success: success)
            rate = consent_map.success_rate(domain)
            total = consent_map.domains[domain][:total_actions]
            Legion::Logging.info "[consent] action recorded: domain=#{domain} success=#{success} rate=#{rate.round(2)} total=#{total}"

            {
              domain:       domain,
              success:      success,
              success_rate: rate,
              total:        total
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
              Legion::Logging.info "[consent] tier change: domain=#{domain} recommend=promote from=#{current} to=#{result[:proposed_tier]}"
            when :demote
              result[:proposed_tier] = Helpers::Tiers.demote(current)
              Legion::Logging.warn "[consent] tier change: domain=#{domain} recommend=demote from=#{current} to=#{result[:proposed_tier]}"
            else
              Legion::Logging.debug "[consent] tier eval: domain=#{domain} current=#{current} recommendation=#{recommendation}"
            end

            result
          end

          def apply_tier_change(domain:, new_tier:, **)
            return { error: :invalid_tier, valid_tiers: Helpers::Tiers::TIERS } unless Helpers::Tiers.valid_tier?(new_tier)

            old_tier = consent_map.get_tier(domain)
            consent_map.set_tier(domain, new_tier)
            changed = old_tier != new_tier
            Legion::Logging.info "[consent] tier applied: domain=#{domain} old=#{old_tier} new=#{new_tier} changed=#{changed}"
            { domain: domain, old_tier: old_tier, new_tier: new_tier, changed: changed }
          end

          def evaluate_all_tiers(**)
            promotions = []
            demotions = []

            consent_map.domains.each_key do |domain|
              result = consent_map.evaluate_promotion(domain)
              promotions << domain if result == :promote
              demotions << domain if result == :demote
            end

            evaluated = consent_map.domain_count
            Legion::Logging.debug "[consent] tier evaluation sweep: domains=#{evaluated} " \
                                  "promotions=#{promotions.size} demotions=#{demotions.size}"

            { evaluated: evaluated, promotions: promotions, demotions: demotions }
          end

          def request_autonomous_approval(domain:, **)
            map = consent_map
            current_tier = map.get_tier(domain)

            return { requested: false, error: 'already_autonomous' } if current_tier == :autonomous
            return { requested: false, error: 'already_pending' } if map.pending?(domain)

            map.set_pending(domain, proposed_tier: :autonomous, requested_by: 'tier_evaluation')

            if defined?(Legion::Events)
              rate = map.success_rate(domain)
              total = map.domains[domain][:total_actions]
              Legion::Events.emit('consent.approval_required', {
                                    domain:        domain,
                                    current_tier:  current_tier,
                                    proposed_tier: :autonomous,
                                    success_rate:  rate,
                                    total_actions: total,
                                    requested_at:  Time.now.utc
                                  })
            end

            { requested: true, domain: domain, current_tier: current_tier, proposed_tier: :autonomous }
          end

          def approve_promotion(domain:, approved_by:, **)
            map = consent_map
            return { approved: false, error: 'no_pending_approval' } unless map.pending?(domain)

            pending_tier = map.domains[domain][:pending_tier]
            old_tier = map.get_tier(domain)
            map.clear_pending(domain)
            map.set_tier(domain, pending_tier)

            if defined?(Legion::Events)
              Legion::Events.emit('consent.promotion_approved', {
                                    domain: domain, old_tier: old_tier, new_tier: pending_tier,
                                    approved_by: approved_by, at: Time.now.utc
                                  })
            end

            { approved: true, domain: domain, old_tier: old_tier, new_tier: pending_tier, approved_by: approved_by }
          end

          def reject_promotion(domain:, rejected_by:, reason: nil, **)
            map = consent_map
            return { rejected: false, error: 'no_pending_approval' } unless map.pending?(domain)

            map.clear_pending(domain)

            if defined?(Legion::Events)
              Legion::Events.emit('consent.promotion_rejected', {
                                    domain: domain, rejected_by: rejected_by, reason: reason, at: Time.now.utc
                                  })
            end

            { rejected: true, domain: domain, rejected_by: rejected_by, reason: reason }
          end

          def expire_pending_approvals(timeout: Helpers::ConsentMap::APPROVAL_TIMEOUT, **)
            map = consent_map
            expired = 0

            map.domains.each_key do |domain|
              next unless map.pending?(domain)
              next unless map.pending_expired?(domain, timeout: timeout)

              map.clear_pending(domain)
              expired += 1
            end

            { expired: expired }
          end

          def evaluate_and_apply_tiers(**)
            candidates = evaluate_all_tiers
            applied_promotions = 0
            applied_demotions = 0
            approval_requests = 0

            Array(candidates[:promotions]).each do |domain|
              current = consent_map.get_tier(domain)
              proposed = Helpers::Tiers.promote(current)

              if proposed == :autonomous
                result = request_autonomous_approval(domain: domain)
                approval_requests += 1 if result[:requested]
              else
                apply_tier_change(domain: domain, new_tier: proposed)
                applied_promotions += 1
              end
            end

            Array(candidates[:demotions]).each do |domain|
              current = consent_map.get_tier(domain)
              proposed = Helpers::Tiers.demote(current)
              apply_tier_change(domain: domain, new_tier: proposed)
              applied_demotions += 1
            end

            expired = expire_pending_approvals

            { evaluated: candidates[:evaluated], applied_promotions: applied_promotions,
              applied_demotions: applied_demotions, approval_requests: approval_requests,
              expired_approvals: expired[:expired] }
          end

          def consent_status(domain: nil, **)
            if domain
              entry = consent_map.domains[domain]
              Legion::Logging.debug "[consent] status: domain=#{domain} tier=#{entry[:tier]} total=#{entry[:total_actions]}"
              {
                domain:       domain,
                tier:         entry[:tier],
                success_rate: consent_map.success_rate(domain),
                total:        entry[:total_actions],
                eligible:     consent_map.eligible_for_change?(domain)
              }
            else
              Legion::Logging.debug "[consent] status: domains=#{consent_map.domain_count}"
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
