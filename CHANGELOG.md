# Changelog

## Unreleased

### Added

- Added an explicit All Rights Reserved license.
- Added tag-driven automatic packaging metadata for CurseForge releases.

## 1.1.0 - 2026-07-26

### Added

- Added realm-aware raid identities so same-name characters on different realms remain distinct in Raid Groups, reordering, and Player Auto Marking.
- Added an optional `Retry unavailable players` queue to each Player Auto Marking rule, with selectable durations from 1 to 10 seconds.
- Added Lua 5.1 regression tests for duplicate character names across realms and queued mark assignments.

### Changed

- Replaced the sequential Force Positions implementation with the validated
  planned and batched exact-position sorter.
- Shift + Left Click now performs the supported exact group-and-position
  sort; ordinary Left Click remains the fast membership-only sort.
- Position routes are selected using bounded exact scheduling, wall-time-aware
  scoring, and the tested 50-action rolling allowance.
- Renamed the diagnostic module and log from experimental sorting to position
  sorting.
- Updated Classic Era compatibility metadata to interface `11509`.
- Player Auto Marking now verifies the observed raid marker before considering an assignment successful.
- Smart Assign group-swap rules apply to stable character identities before reordering, verify again after reordering, and clear existing marks at most once per rule application.
- Failed assignments can remain pending when the rule queue is enabled, while addressable players are still marked immediately.
- Player Auto Marking rule and preset imports/exports now preserve queue enablement and duration.

### Removed

- Removed the temporary Ctrl-click exact-sort and Alt-click scramble bindings.
- Removed the scramble implementation and its floating-window tooltip text.
- Removed the old one-position-at-a-time bridge sorter.

### Known Limitation

- Classic Era 1.15.9 can reject raid-marker API calls for raid members whose unit is not currently addressable to the raid leader's client. The retry queue can catch temporary availability changes but cannot mark a player who remains unavailable for its full duration.

## 1.0.0 - 2026-07-24

- Initial public release of PugzRaidTools.
