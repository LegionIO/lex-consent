# Changelog

## [0.2.0] - 2026-03-16

### Added
- Human-in-the-loop gate for autonomous tier promotion: `request_autonomous_approval`, `approve_promotion`, `reject_promotion`, `expire_pending_approvals`
- `evaluate_and_apply_tiers` orchestrator: auto-applies non-autonomous promotions/demotions, gates autonomous with approval request, expires stale approvals
- Pending approval state in ConsentMap: `set_pending`, `clear_pending`, `pending?`, `pending_expired?`
- `APPROVAL_TIMEOUT` constant (72 hours) for stale approval expiration
- Event emission for `consent.approval_required`, `consent.promotion_approved`, `consent.promotion_rejected`

### Changed
- `TierEvaluation` actor now calls `evaluate_and_apply_tiers` instead of `evaluate_all_tiers`

## [0.1.1] - 2026-03-14

### Added
- `TierEvaluation` actor (Every 3600s): periodic re-evaluation of consent tiers based on accumulated interaction history via `evaluate_all_tiers` in `runners/consent.rb`

## [0.1.0] - 2026-03-13

### Added
- Initial release
