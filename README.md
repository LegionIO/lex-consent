# lex-consent

Four-tier consent gradient with earned autonomy for brain-modeled agentic AI. Tracks the agent's authorization level per domain and manages tier promotion and demotion based on demonstrated reliability.

## Overview

`lex-consent` implements the agent's self-governance layer for action authorization. Instead of fixed permissions, autonomy is earned: the agent starts at `:consult` for any new domain, and its tier changes based on its track record of successes and failures. This creates a system where trust is demonstrated, not assumed.

## Consent Tiers

| Tier | Meaning | Actions Allowed |
|------|---------|----------------|
| `:autonomous` | Full autonomy | Act without notification |
| `:act_notify` | Act then notify | Act, but inform human after |
| `:consult` | Consult first | Must get human input before acting |
| `:human_only` | Human-only | No autonomous action permitted |

New domains start at `:consult`. Tier changes require minimum 10 actions and a 24-hour cooldown between changes.

## Promotion/Demotion Thresholds

| Event | Threshold |
|-------|-----------|
| Promote to higher autonomy | >= 80% success rate |
| Demote to lower autonomy | < 50% success rate |
| Minimum actions before change | 10 |
| Cooldown between changes | 24 hours |

## Installation

Add to your Gemfile:

```ruby
gem 'lex-consent'
```

## Usage

### Checking Consent

```ruby
require 'legion/extensions/consent'

# Check if an action is allowed in a domain
result = Legion::Extensions::Consent::Runners::Consent.check_consent(domain: :file_system)
# => { domain: :file_system, tier: :consult, allowed: false,
#      needs_notify: false, needs_consult: true, human_only: false }
```

### Recording Outcomes

```ruby
# Record a successful action (updates success/failure counters)
Legion::Extensions::Consent::Runners::Consent.record_action(domain: :file_system, success: true)
# => { domain: :file_system, success: true, success_rate: 0.85, total: 12 }
```

### Evaluating Tier Changes

```ruby
# Check if the domain is eligible for a tier change
Legion::Extensions::Consent::Runners::Consent.evaluate_tier_change(domain: :file_system)
# => { domain: :file_system, current_tier: :consult, recommendation: :promote,
#      proposed_tier: :act_notify, success_rate: 0.85 }

# Apply the change
Legion::Extensions::Consent::Runners::Consent.apply_tier_change(
  domain: :file_system, new_tier: :act_notify
)
# => { domain: :file_system, old_tier: :consult, new_tier: :act_notify, changed: true }
```

### Status

```ruby
# Single domain
Legion::Extensions::Consent::Runners::Consent.consent_status(domain: :file_system)

# All domains
Legion::Extensions::Consent::Runners::Consent.consent_status
```

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT
