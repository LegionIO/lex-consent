# lex-consent

**Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-agentic/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Four-tier consent gradient with earned autonomy for the LegionIO cognitive architecture. Manages per-domain authorization tiers, tracks action outcomes, and evaluates tier promotions/demotions based on demonstrated reliability.

## Gem Info

- **Gem name**: `lex-consent`
- **Version**: `0.2.0`
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
    consent.rb      # check_consent, record_action, evaluate_tier_change, apply_tier_change, consent_status, evaluate_all_tiers, request_autonomous_approval, approve_promotion, reject_promotion, expire_pending_approvals, evaluate_and_apply_tiers
  actors/
    tier_evaluation.rb  # TierEvaluation - Every 3600s, sweeps all domains for eligible tier changes
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
  tier:                 :consult,      # current tier
  success_count:        0,
  failure_count:        0,
  total_actions:        0,
  last_changed_at:      nil,
  history:              [],            # capped at 50 tier changes
  pending_tier:         nil,           # proposed tier awaiting human approval
  pending_since:        nil,           # timestamp of approval request
  pending_requested_by: nil            # who requested the promotion
}
```

`APPROVAL_TIMEOUT = 259_200` (72 hours) — stale pending approvals are expired by `expire_pending_approvals`.

`eligible_for_change?` returns false if `total_actions < MIN_ACTIONS_TO_PROMOTE` or cooldown not elapsed.

`evaluate_promotion` returns: `:ineligible`, `:already_max`, `:already_min`, `:promote`, `:demote`, or `:maintain`.

## Tier Direction

Lower TIER_ORDER index = more autonomous. `Tiers.promote` decrements index, `Tiers.demote` increments. Both are no-ops at the boundary values.

## Actors

| Actor | Interval | Runner | Method | Purpose |
|---|---|---|---|---|
| `TierEvaluation` | Every 3600s | `Runners::Consent` | `evaluate_and_apply_tiers` | Sweeps all domains, auto-applies non-autonomous tier changes, gates autonomous promotions with human approval |

### TierEvaluation

Hourly sweep that orchestrates the full tier lifecycle:
1. Calls `evaluate_all_tiers` to identify promotion/demotion candidates
2. Auto-applies non-autonomous promotions (e.g., `consult` -> `act_notify`)
3. For promotions to `autonomous`, calls `request_autonomous_approval` instead of auto-applying
4. Auto-applies all demotions
5. Expires stale pending approvals (>72 hours)

Returns `{ evaluated:, applied_promotions:, applied_demotions:, approval_requests:, expired_approvals: }`.

## Runner Logic

- `check_consent` - reads tier, computes boolean flags (`allowed`, `needs_notify`, `needs_consult`, `human_only`)
- `record_action` - updates success/failure counters without changing tier
- `evaluate_tier_change` - calls `evaluate_promotion`, optionally appends `proposed_tier`
- `apply_tier_change` - validates tier, calls `set_tier` (which updates history and cooldown timestamp)
- `consent_status` - without `domain:` returns all domains via `to_h`
- `evaluate_all_tiers` - sweeps all domains and returns promotion/demotion candidate lists without applying changes
- `request_autonomous_approval` - sets pending state, emits `consent.approval_required` event
- `approve_promotion` - applies pending tier, emits `consent.promotion_approved` event
- `reject_promotion` - clears pending state, emits `consent.promotion_rejected` event
- `expire_pending_approvals` - clears stale approvals past 72h timeout
- `evaluate_and_apply_tiers` - full orchestration: evaluate, auto-apply non-autonomous changes, gate autonomous with approval, expire stale

## Integration Points

- **lex-coldstart**: imprint window uses `:consult` tier (`IMPRINT_CONSENT_TIER`)
- **lex-tick**: `action_selection` phase checks consent before executing actions
- **lex-governance**: governance proposals can force tier overrides

## Development Notes

- `@consent_map` is per-runner-instance; multiple runner instances would have independent state
- The `_action_type:` parameter in `check_consent` is intentionally ignored (reserved for future use)
- History is capped at 50 entries via `shift while size > 50`
- `evaluate_all_tiers` reads from `consent_map.domains.each_key` — only domains that have been previously accessed (auto-populated by the default Hash) are evaluated; domains never touched are not in the sweep
