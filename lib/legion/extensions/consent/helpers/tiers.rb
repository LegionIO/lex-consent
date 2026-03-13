# frozen_string_literal: true

module Legion
  module Extensions
    module Consent
      module Helpers
        module Tiers
          # Four consent tiers (spec: consent-gradient-spec.md)
          TIERS = %i[autonomous act_notify consult human_only].freeze

          # Default starting tier for new domains
          DEFAULT_TIER = :consult

          # Thresholds for tier promotion/demotion
          PROMOTION_THRESHOLD   = 0.8  # success rate needed to promote
          DEMOTION_THRESHOLD    = 0.5  # success rate below which demotion occurs
          MIN_ACTIONS_TO_PROMOTE = 10  # minimum actions before tier change
          PROMOTION_COOLDOWN    = 86_400 # seconds between tier changes (24h)

          # Tier ordering (lower index = more autonomy)
          TIER_ORDER = { autonomous: 0, act_notify: 1, consult: 2, human_only: 3 }.freeze

          module_function

          def valid_tier?(tier)
            TIERS.include?(tier)
          end

          def more_autonomous?(tier_a, tier_b)
            TIER_ORDER.fetch(tier_a, 99) < TIER_ORDER.fetch(tier_b, 99)
          end

          def promote(current_tier)
            idx = TIER_ORDER.fetch(current_tier, 2)
            return current_tier if idx.zero?

            TIER_ORDER.key(idx - 1) || current_tier
          end

          def demote(current_tier)
            idx = TIER_ORDER.fetch(current_tier, 2)
            return current_tier if idx >= 3

            TIER_ORDER.key(idx + 1) || current_tier
          end
        end
      end
    end
  end
end
