# frozen_string_literal: true

require 'json'

module Legion
  module Extensions
    module Consent
      module Helpers
        class ConsentMap
          APPROVAL_TIMEOUT = 259_200 # 72 hours

          attr_reader :domains

          def initialize
            @domains = Hash.new do |h, k|
              h[k] = {
                tier:                 Tiers::DEFAULT_TIER,
                success_count:        0,
                failure_count:        0,
                total_actions:        0,
                last_changed_at:      nil,
                history:              [],
                pending_tier:         nil,
                pending_since:        nil,
                pending_requested_by: nil
              }
            end
            load_from_local
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
              { tier: v[:tier], success_rate: success_rate_from(v), total_actions: v[:total_actions],
                pending_tier: v[:pending_tier], pending_since: v[:pending_since] }
            end
          end

          def set_pending(domain, proposed_tier:, requested_by: 'system')
            entry = @domains[domain]
            entry[:pending_tier] = proposed_tier
            entry[:pending_since] = Time.now
            entry[:pending_requested_by] = requested_by
            entry
          end

          def clear_pending(domain)
            entry = @domains[domain]
            entry[:pending_tier] = nil
            entry[:pending_since] = nil
            entry[:pending_requested_by] = nil
            entry
          end

          def pending?(domain)
            !@domains[domain][:pending_tier].nil?
          end

          def pending_expired?(domain, timeout: APPROVAL_TIMEOUT)
            entry = @domains[domain]
            return false unless entry[:pending_since]

            Time.now - entry[:pending_since] > timeout
          end

          def save_to_local
            return unless defined?(Legion::Data::Local) && Legion::Data::Local.connected?

            dataset = Legion::Data::Local.connection[:consent_domains]
            @domains.each do |domain_key, entry|
              row = {
                domain_key:      domain_key,
                tier:            entry[:tier].to_s,
                success_count:   entry[:success_count],
                failure_count:   entry[:failure_count],
                total_actions:   entry[:total_actions],
                last_changed_at: entry[:last_changed_at],
                history:         ::JSON.generate(entry[:history].map { |h| h.transform_values(&:to_s) })
              }
              existing = dataset.where(domain_key: domain_key).first
              if existing
                dataset.where(domain_key: domain_key).update(row.except(:domain_key))
              else
                dataset.insert(row)
              end
            end
          rescue StandardError => e
            Legion::Logging.warn "[consent] save_to_local failed: #{e.message}" if defined?(Legion::Logging)
          end

          def load_from_local
            return unless defined?(Legion::Data::Local) && Legion::Data::Local.connected?

            Legion::Data::Local.connection[:consent_domains].each do |row|
              key = row[:domain_key]
              history = begin
                ::JSON.parse(row[:history] || '[]', symbolize_names: false).map do |h|
                  { from: h['from'].to_sym, to: h['to'].to_sym, at: h['at'] }
                end
              rescue StandardError
                []
              end

              @domains[key] = {
                tier:            row[:tier].to_sym,
                success_count:   row[:success_count].to_i,
                failure_count:   row[:failure_count].to_i,
                total_actions:   row[:total_actions].to_i,
                last_changed_at: row[:last_changed_at],
                history:         history
              }
            end
          rescue StandardError => e
            Legion::Logging.warn "[consent] load_from_local failed: #{e.message}" if defined?(Legion::Logging)
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
