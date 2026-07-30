# Changelog

## 1.3.2 - 2026-07-30

### Added

- Added `/prt debug` as the dedicated index for Target Marks, Raid Check, Auto Match, and configuration-window diagnostics, keeping developer commands out of the normal `/prt help` output.

### Changed

- The main PRT configuration window now remembers its size and position across reloads and logouts, while safely clamping restored geometry to the current screen.
- All PRT on-screen notifications now render at the highest frame strata so they remain visible above addon configuration windows.
- Floating Group List and notification font colours now default to the addon theme colour `#3DFF8B`.
- The Settings colour picker now opens above the PRT configuration window.
- Reduced memory churn while scrolling large Target Marks Preset Groupings by caching normalized mark data, reusing a small visible-row pool, and skipping refreshes when the visible range is unchanged.
- Significantly reduced Raid Check Test Preview memory by creating rows, enabled-column cells, text, count overlays, glow textures, icon interactions, and collapsed-mode members only when required.
- Raid Check cells, rows, headers, and potion icons now reuse shared tooltip and click handlers instead of retaining separate callbacks for every UI target.
- Closing Raid Check now releases its preview snapshot and all member and aura bindings, allowing transient preview data to be collected while retaining only the reusable UI pool.
- Reduced Auto Match memory and analysis churn by deferring Alias Database windows until requested, coalescing initial refreshes, reusing name-comparison workspace, sharing row handlers, and releasing match analysis when the window closes.
- Standardized configuration dropdowns on the shared UI widget, including animated hover fades, dynamic item refreshes, class-coloured labels, reusable menus for pooled controls, and portable raid-marker icons.

### Fixed

- Fixed overall PRT Profile imports being rejected with a misleading `0` chat message when valid bundled feature-preset sections were present.
- Fixed a Target Marks editor error that could occur when changing tabs while a raid-marker dropdown was open.

## 1.3.1 - 2026-07-29

### Added

- Added three selectable Profile Float main-button labels: `Profile: ProfileName`, `P: ProfileName:`, and `ProfileName`.
- Added `!logs`, `!disallowed`, `!banned`, and `!invalid` Raid Check chat aliases for reporting detected Logs! effects and affected players.
- Added complete Alias Database import and export, including merge, automatic rename, and skip choices for duplicate alias names plus keep-or-skip handling for realm-aware characters already stored under other aliases.
- Added direct Alias Database merging with live name search, clickable suggestions, duplicate-safe character combining, and confirmation before the source alias is removed.
- Added clickable Raid Check column reports for ready responses, preparation categories, class buffs, Logs! warnings, durability, and targeted Potion icons, with context-specific Shift-click reports.

### Changed

- Reorganized the Settings tab into one scrollable page with clearly separated General Interface, Floating Group List, Group Swap Notifications, Combat Logging, and About sections.
- Condensed the Raid Groups Delete and Delete All confirmation windows to better fit their short prompts.
- Streamlined the Raid Check documentation in the public README while retaining detailed implementation notes in the development documentation.
- Dropdown menus now remain raised above their owning popup through delayed and subsequent popup focus changes, fixing the Class selector initially appearing underneath the Add Character window.
- Alias exports and imports now use the `[PRT Alias Database v2]` comma-delimited format so WoW cannot consume `|R` from `|ROGUE` as a text-formatting code.
- The Add Character Class dropdown now uses the existing fading row-hover animation and colours every class entry and selected value with its class colour; Unknown remains grey.
- Alias and character deletion now use a compact Alias Database confirmation window with concise prompts and evenly sized actions.
- The Alias Database now opens at 540x640 and can be resized down to 540x320.
- Raid Check scans now retain aura-caster names when WoW provides them and preserve each player's slot within their raid group for wrong-rank and player-specific buff reports.

## 1.3.0 - 2026-07-28

### New Major Features

- **Raid Check** — Inspect ready-check responses, World Buffs, food, flasks, Zanza effects, consumes, protection potions, class buffs, durability, and warning effects in a compact configurable raid window opened with `/prt check` or `/rt check`.
- **Raid Check chat reports** — Send preparation commands such as `!flask`, `!worldbuffs`, or `!durability` in raid, party, or instance chat and receive concise live group results, with long responses safely divided across multiple messages.
- **Invite & Loot Tools presets** — Save invitation, promotion, raid-management, loot, zone, and announcement settings as named presets that can be created, switched, imported, exported, and included in an overall PRT Profile.
- **Faster profile switching** — Switch overall PRT Profiles from a movable Profile Float or an embedded Floating Group List selector, with configurable appearance, notifications, locking, and mouse-over behaviour.
- **Expanded floating-interface customization** — Configure exact dimensions, scale, row height, fonts, opacity, text handling, selector placement, and mouse-over visibility for the Floating Group List and Profile Float.

### Added

- Added a dedicated **Raid Check** configuration tab with quick checks, local output, and raid or party chat reports.
- Added a sleek, compact live Raid Check window with class-coloured rows, a ready-check progress-bar header, and expanded or collapsed roster views.
- Added `/prt check` and `/rt check` to toggle the Raid Check window while preserving unrelated `/rt` subcommands.
- Added a 40-player Classic roster test preview, 35-second ready-check timing, a five-second completion hold, and a smooth two-second fade.
- Added ordered World Buffs, Zanza, Consumes, Potions, and Disallowed aura categories, including configured item-icon overrides and Supercharged Chronoboon detection.
- Added class-specific world-buff validity settings with per-class defaults and one-click restoration.
- Added per-column visibility, aura-count display, multi-icon limits, left/centre/right alignment, World Buff handling for uncounted auras, detected-only warning visibility, and configurable ordering with Player fixed first.
- Added red icon glows for low-rank class buffs and all detected Disallowed effects.
- Added Blessing of Salvation and Blessing of Light columns with normalized greater-blessing icons, including low-rank Blessing of Light warnings.
- Added an option to show the five Paladin Blessing columns only when the local player is Alliance.
- Added optional automatic display during ready checks, with leader/assistant restriction, configurable tracked columns, player sorting, window scale, frame strata defaulting to Fullscreen Dialog, and delayed closing.
- Added an enabled-by-default option to dismiss the Raid Check by right-clicking anywhere in its window.
- Added lightweight durability sharing between group members running PRT; players without a recent response remain clearly marked as unknown.
- Added self-issued Raid Check commands for raid, party, and instance chat covering flasks, World Buff duration groups, active Chronoboon counts, max-rank raid buffs, durability thresholds, Juju Chill, and protection potions.
- Added `/prt commands` plus a Raid Check configuration tooltip for discovering chat-command aliases without expanding the general `/prt help` output.
- Added safe multi-line command responses prefixed with `PRT: ` and constrained to WoW's 255-byte chat-message limit.
- Added named **Invite & Loot Tools** presets with create, rename, delete, import, and export controls.
- Added an Invite & Loot automation master switch while preserving each preset's individual settings.
- Added Invite & Loot Tools preset selection and enable defaults to overall PRT Profiles and full-profile imports/exports.
- Added a movable **Profile Float** for quickly switching overall PRT Profiles, with show, mouse-over-only, and lock settings.
- Added exact pixel width and height controls, font sizing, background opacity, and configurable long-text handling to the Profile Float.
- Added optional profile-change notifications with sound, test controls, and independently configurable screen position.
- Added configurable expand, truncate, and shrink-to-fit behavior for long composition names in the Floating Group List.
- Added an option to place the active PRT Profile selector inside the Floating Group List, where it inherits the list's appearance, position, visibility, and lock settings.
- Added exact width, row-height, font-size, scale, and background-opacity controls plus a mouse-over-only mode to the Floating Group List.
- Added a test button for the configured Group Swap notification.
- Added top or bottom placement, left/center/right text alignment, and an optional background highlight for the embedded Profile selector.
- Added a General Settings toggle for showing or hiding the minimap icon.
- Added `/prt debugui on`, `/prt debugui`, and `/prt debugui off` commands for recording and reporting main-window resize state.
- Added a second **+ Add NPC** button at the top of Target Marks groupings; it adds a row and moves the editor to the new entry.
- Added Ashenvale, The Hinterlands, Duskwood, and Feralas to the built-in loot-prompt zone list.
- Added custom loot-prompt zones, including buttons to enter a zone name or capture the player's current zone.

### Changed

- The Flask check now accepts only Flask of the Titans, Flask of Distilled Wisdom, Flask of Supreme Power, and Flask of Chromatic Resistance.
- Persistent elixir and consumable effects now appear under Consumes, while protection potion effects and Frozen Rune appear under Potions. Flask of Petrification is tracked separately and does not satisfy the live Flask check.
- The ready-check header now uses a smooth teal progress bar with a fading edge and a more descriptive Ready, Not Ready, and Awaiting Response summary.
- Live and preview title bars now begin with `PRT Raid Check`.
- Raid Check player rows now use class-colour gradients, outlined names, a narrower Player area, tighter class-buff columns, and a GotW column label.
- Collapsed Raid Check names now use their player class colours.
- Aura icons now fill the result-row height without inset spacing, while header icons, header text, and cell contents follow each column's configured alignment.
- Column-header text now uses physical left, centre, or right edge anchoring so every category visibly follows its configured alignment on Classic clients.
- Aura counts now remain immediately to the right of the final displayed icon instead of following the column alignment.
- Uncounted World Buffs can now be shown normally, faded, or hidden without changing the detected or valid totals; this control now lives beside the World Buff Validity settings.
- Column Order configuration now fits each category and all of its applicable controls on one row.
- Both Might of Stormwind aura IDs are now valid by default for every class.
- The former AP column is now DF BS, is described as Diamond Flask Battle Shout, and detects only aura `25101`.
- Test previews now randomize detected preparation auras while guaranteeing examples that reach the configured World Buff, Consumes, and Potions icon limits and retaining uncommon warning states.
- Test-preview World Buffs now follow realistic exclusivity rules: one Sayge fortune per player, Warchief's Blessing or Might of Stormwind but never both, and either active World Buffs or Chronoboon but never both.
- The warning column is now labelled Logs!, obtains its icon directly from Traces of Silithyst, and also detects AV Fire Shield and Soul Revival.
- Zanza no longer displays a redundant aura count.
- World Buff and Chronoboon row icons now resolve directly from their spell IDs.
- World Buff display priority now places counted Sayge fortunes first, followed by Dragonslayer, Zandalar, Warchief's Blessing, Might of Stormwind, Songflower, Fengus, Mol'dar, and Slip'kik; counted buffs always occupy available icon slots before shown or faded uncounted buffs.
- World Buff columns can now display up to seven selected icons with only a compact 15-pixel trailing allowance for their count and margin.
- Friendship Gift effects and normal Consumes now resolve row icons from their exact aura spell IDs while retaining configured item-icon exceptions.
- Bogling Root now displays the texture from item `5206` instead of aura `5665`.
- The Raid Check chat-command tooltip is wider, keeps each command description on one line, and colours command syntax for faster scanning.
- Player-buff rows and test previews now use the exact detected aura's spell icon, allowing single-target and group variants to remain visually distinct; configured Salvation and Light overrides are preserved.
- Durability values below 25% now use red text.
- Single-icon aura columns now use the same spacing as class-buff columns; each additional configured icon adds one icon width.
- Class sorting now follows Warrior, Rogue, Hunter, Mage, Warlock, Druid, Paladin, Priest, and Shaman priority, with separate then-name and then-group modes.
- New Raid Check settings now default to scale 1.00, class-then-group sorting, automatic leader/assistant ready-check display, a five-second completion hold and fade, an expanded ready-status view, and fading uncounted World Buffs. The default column order, visibility, alignment, counts, and icon limits now match the supplied compact raid layout.
- Loot method, master-looter assignment, and loot threshold changes are now evaluated and applied independently.
- The loot confirmation prompt now identifies the current master looter when the configured setting is **Keep current**.
- Raid-entry status notifications now include the active overall PRT Profile without producing a second competing notification.
- The entire Profiles tab is now scrollable, and standalone Profile Float appearance controls are disabled while its selector is embedded in the Floating Group List.
- Reduced the minimum width and height available to both floating interfaces.
- Invite & Loot preset exports include invite keywords, queued raid-invite settings, promotion rules, loot settings, built-in and custom zones, and Loot to Chat settings. The realm-aware invite block list remains global.
- Floating Group List composition rows now use the same smooth hover feedback as other PRT selection lists.
- The embedded Profile selector now uses aligned white text and a dropdown indicator, making it distinct from raid compositions.
- The embedded Profile dropdown now inherits the Floating Group List's effective scale, width, row height, font size, outline, and text handling.

### Fixed

- Applying configured Master Loot no longer fails when automatic master-looter assignment is disabled and no master looter is currently active; the game now chooses its normal default.
- Applying an already-active Master Loot configuration no longer reapplies the loot method and accidentally replaces the current master looter.
- Unchanged loot methods and thresholds no longer generate unnecessary API calls.
- Fixed a Profile Float initialization error when updating its active-profile label.
- Floating Group List composition tooltips now avoid covering the list and choose a screen-aware side that keeps them visible near screen edges and corners.
- Removed the ineffective text-wrapping choice from both floating interfaces and migrated saved uses of it to truncation.
- Fixed the main configuration resize grip fighting the frame-size clamp during slower drags.
- Corrected vertical text alignment throughout both floating interfaces and their profile menus.
- Fixed embedded Profile dropdowns opening away from the Floating Group List's outer edge or overlapping it by the selector row's inner padding.
- Fixed the minimap visibility setting leaving a non-interactive slot visible when HidingBar controlled the button frame.
- Fixed main-window resizing collapsing the sidebar, content area, and tab panels to zero dimensions.
- Reduced live-resize flashing by preserving established anchors, skipping unchanged physical-pixel sizes, and resizing only the visible tab panel during the drag.
- Fixed fractional UI scaling causing recursive one- or two-pixel resize corrections and unstable layouts at particular window sizes.
- Fixed the resize grip disappearing or becoming unusable after completing a drag.
- Fixed Raid Check class-colour gradients and gradient timer tails not rendering because their textures lacked an initialized colour surface.

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
