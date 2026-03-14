# lex-consent

**Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-agentic/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Four-tier consent gradient with earned autonomy for the LegionIO cognitive architecture. Manages per-domain authorization tiers, tracks action outcomes, and evaluates tier promotions/demotions based on demonstrated reliability.

## Gem Info

- **Gem name**: `lex-consent`
- **Version**: `0.1.0`
- **Module**: `Legion::Extensions::Consent`
- **Ruby**: `>= 3.4`
- **License**: MIT

## File Structure

```
lib/legion/extensions/consent/
  version.rb
  helpers/
    tiers.rb        # TIERS, TIER_ORDER, thresholds, promote/demote helpers
    consent_map.rb  # ConsentMap class - per-domain state and history
  runners/
    consent.rb      # check_consent, record_action, evaluate_tier_change, apply_tier_change, consent_status
spec/
  legion/extensions/consent/
    helpers/
      tiers_spec.rb
    runners/
      consent_spec.rb
    client_spec.rb
```

## Key Constants (Helpers::Tiers)

```ruby
TIERS                 = %i[autonomous act_notify consult human_only]
DEFAULT_TIER          = :consult
PROMOTION_THRESHOLD   = 0.8    # success rate needed to promote
DEMOTION_THRESHOLD    = 0.5    # success rate below which demotion occurs
MIN_ACTIONS_TO_PROMOTE = 10
PROMOTION_COOLDOWN    = 86_400  # 24h between tier changes
TIER_ORDER = { autonomous: 0, act_notify: 1, consult: 2, human_only: 3 }
```

## ConsentMap Class

`Helpers::ConsentMap` holds per-domain state using a default-populating Hash. Each domain entry:
```ruby
{
  tier:            :consult,      # current tier
  success_count:   0,
  failure_count:   0,
  total_actions:   0,
  last_changed_at: nil,
  history:         []             # capped at 50 tier changes
}
```

`eligible_for_change?` returns false if `total_actions < MIN_ACTIONS_TO_PROMOTE` or cooldown not elapsed.

`evaluate_promotion` returns: `:ineligible`, `:already_max`, `:already_min`, `:promote`, `:demote`, or `:maintain`.

## Tier Direction

Lower TIER_ORDER index = more autonomous. `Tiers.promote` decrements index, `Tiers.demote` increments. Both are no-ops at the boundary values.

## Runner Logic

- `check_consent` - reads tier, computes boolean flags (`allowed`, `needs_notify`, `needs_consult`, `human_only`)
- `record_action` - updates success/failure counters without changing tier
- `evaluate_tier_change` - calls `evaluate_promotion`, optionally appends `proposed_tier`
- `apply_tier_change` - validates tier, calls `set_tier` (which updates history and cooldown timestamp)
- `consent_status` - without `domain:` returns all domains via `to_h`

## Integration Points

- **lex-coldstart**: imprint window uses `:consult` tier (`IMPRINT_CONSENT_TIER`)
- **lex-tick**: `action_selection` phase checks consent before executing actions
- **lex-governance**: governance proposals can force tier overrides

## Development Notes

- `@consent_map` is per-runner-instance; multiple runner instances would have independent state
- The `_action_type:` parameter in `check_consent` is intentionally ignored (reserved for future use)
- History is capped at 50 entries via `shift while size > 50`
