# frozen_string_literal: true

module Legion
  module Extensions
    module Consent
      module Helpers
        class ConsentMap
          attr_reader :domains

          def initialize
            @domains = Hash.new do |h, k|
              h[k] = {
                tier:            Tiers::DEFAULT_TIER,
                success_count:   0,
                failure_count:   0,
                total_actions:   0,
                last_changed_at: nil,
                history:         []
              }
            end
          end

          def get_tier(domain)
            @domains[domain][:tier]
          end

          def set_tier(domain, tier)
            return unless Tiers.valid_tier?(tier)

            entry = @domains[domain]
            old_tier = entry[:tier]
            entry[:tier] = tier
            entry[:last_changed_at] = Time.now.utc
            entry[:history] << { from: old_tier, to: tier, at: Time.now.utc }
            entry[:history].shift while entry[:history].size > 50
          end

          def record_outcome(domain, success:)
            entry = @domains[domain]
            entry[:total_actions] += 1
            if success
              entry[:success_count] += 1
            else
              entry[:failure_count] += 1
            end
          end

          def success_rate(domain)
            entry = @domains[domain]
            return 0.0 if entry[:total_actions].zero?

            entry[:success_count].to_f / entry[:total_actions]
          end

          def eligible_for_change?(domain)
            entry = @domains[domain]
            return false if entry[:total_actions] < Tiers::MIN_ACTIONS_TO_PROMOTE

            if entry[:last_changed_at]
              (Time.now.utc - entry[:last_changed_at]) >= Tiers::PROMOTION_COOLDOWN
            else
              true
            end
          end

          def evaluate_promotion(domain)
            return :ineligible unless eligible_for_change?(domain)

            rate = success_rate(domain)
            current = get_tier(domain)

            if rate >= Tiers::PROMOTION_THRESHOLD
              promoted = Tiers.promote(current)
              return :already_max if promoted == current

              :promote
            elsif rate < Tiers::DEMOTION_THRESHOLD
              demoted = Tiers.demote(current)
              return :already_min if demoted == current

              :demote
            else
              :maintain
            end
          end

          def domain_count
            @domains.size
          end

          def to_h
            @domains.transform_values do |v|
              { tier: v[:tier], success_rate: success_rate_from(v), total_actions: v[:total_actions] }
            end
          end

          private

          def success_rate_from(entry)
            return 0.0 if entry[:total_actions].zero?

            entry[:success_count].to_f / entry[:total_actions]
          end
        end
      end
    end
  end
end
