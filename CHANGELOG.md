# Changelog

## 1.2.1 - 2026-07-27

### Added

- Added realm-aware duplicate-character warnings to the Raid Groups editor, including highlighted slot borders, alert icons, and tooltips listing every duplicate group and slot.
- Added selectable `2-column`, `8-column`, `1-column`, and PRT layouts to individual Raid Group exports.

### Changed

- Added clearer tooltips to the Target Marks Preset Grouping import/export buttons, distinguishing single-group transfers from complete preset transfers.
- Improved menu feedback with smooth hover highlight animations in the sidebar, Raid Groups Quick Load list, and Player Auto Marking rule list.

### Fixed

- Fixed the main configuration window background covering its outer border at higher opacity settings.
- Fixed individual Raid Group exports using a row layout that did not correspond to the selected shaped importer.
- Preserved empty raid slots during shaped export/import round trips with explicit `-` placeholders.
- Replaced visible tab glyphs in multi-column Raid Group exports with ordinary spaces while retaining tab-compatible spreadsheet imports.

## 1.2.0 - 2026-07-27

### Added

- Added the **Invite & Loot Tools** tab for raid invitations, assistant promotion, raid management, loot setup, and loot announcements.
- Added multiple exact-match, case-insensitive auto-invite keywords.
- Added optional guild-only keyword invites.
- Added automatic acceptance of group invites from character friends, Battle.net friends, and guild members.
- Added realm-aware auto-invite blocking with `/prt ban PlayerName[-Realm]`, `/prt unban PlayerName[-Realm]`, `/prt banlist`, and a blocked-player management window.
- Added queued Raid Invites that reserve the initial party slots, automatically convert to a raid when another auto-invite is requested, and retry held or pending players after conversion.
- Added `/prt invites on` and `/prt invites off` controls for the queued Raid Invites feature.
- Added automatic assistant promotion by explicit player name or guild-rank threshold while respecting manual demotions for the current session.
- Added `/prt disband`, which saves a realm-aware snapshot of the current group before disbanding it.
- Added `/prt reinv`, which later invites players from the saved disband snapshot.
- Added one-shot loot setup prompts when entering selected zones as group leader or receiving group leadership there.
- Added loot prompt support for Naxxramas, Ahn'Qiraj, Blackwing Lair, Molten Core, Zul'Gurub, Ruins of Ahn'Qiraj, Blasted Lands, and Azshara.
- Added an option to restrict loot setup prompts to raid groups.
- Added configurable loot methods and quality-coloured thresholds, including Common (White).
- Added optional automatic assignment of a configured master looter.
- Added safe master-looter preservation when automatic assignment is disabled, preventing a blank setting from silently assigning the group leader.
- Added a reusable settings-comparison prompt showing configured and current loot method, threshold, and master looter when applicable.
- Added **Apply Configured** and **Keep Current Settings** actions to the loot prompt.
- Added automatic Epic-or-higher raid-loot announcements with duplicate-source protection and optional item levels.
- Added `/prt loot` to manually link every item in the current loot window to the appropriate group chat.
- Added an explicit All Rights Reserved license.
- Added tag-driven automatic packaging metadata for CurseForge releases.

### Changed

- Renamed the tab from **Invite Tools** to **Invite & Loot Tools**.
- Reorganized the tab into clearly separated invite, raid-management, promotion, loot-distribution, and Loot to Chat sections.
- Loot settings are prompted once rather than continuously enforced, so later manual changes remain untouched.
- Loot prompts are centered and dynamically size themselves to the settings being displayed.
- Slash-command parsing now tolerates capitalization and repeated internal whitespace.

### Fixed

- Reduced party-to-raid conversion delays by processing waiting invite requests as soon as conversion becomes possible.
- Prevented queued or pending auto-invite requests from being lost when the initial party reaches its player limit.
- Fixed `/prt invites off` falling through to the unknown-command response when its whitespace was not normalized.

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
