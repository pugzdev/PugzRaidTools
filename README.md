# PugzRaidTools

**PugzRaidTools (PRT)** is a raid-management addon for **World of Warcraft Classic Era**. It gives raid leaders and assistants one place to build raid compositions, move players between groups, automate encounter-specific group swaps, configure player and NPC raid marks, and share complete setups with other users.

I originally built this addon as an automation tool for speedrunning in the guild [cooked](https://vanilla.warcraftlogs.com/zone/rankings/2006?metric=speed). It serves as a very powerful tool for both marking and for automating group composition swaps based on customizable triggers. It allows for simplicity across raid resets by allowing Group Auto Swaps and Player Auto Marks to dynamically update by reusing the same Raid Group Composition names. It also includes probably the fastest and most lightweight Target Marking tool I know of in the game.

Open the addon with:

```text
/prt
```

## Raid Groups

Build and save complete 40-player raid compositions in an eight-group roster editor.

- Create, rename, delete, reorder, import, and export raid compositions.
- Apply a saved composition to the current raid.
- Optionally force players into exact positions within each group.
- Quickly identify missing players and players who are not part of the selected roster.
- Import several named compositions from a single text block.
- Export one roster as plain names or export every saved roster with composition headers.
- Automatically refresh roster information as players join or leave the raid.

### Floating Raid Group List

The optional floating list keeps saved compositions accessible without opening the full configuration window.

- Left-click a composition for a fast group swap.
- Shift + left-click to force exact raid positions.
- Hover over a composition to compare it with the current raid.
- Toggle Group Auto Swap and Player Auto Marking directly from the floating window.
- Move, scale, lock, show, or hide the list.

## Auto Name Matcher and Alias Database

Imported rosters do not always use the same character names that players bring to the raid. The Auto Name Matcher helps reconcile those differences.

- Compare unresolved imported names against the current live raid.
- Detect exact character matches, known aliases, and likely name variations.
- Adjust the confidence threshold for suggested matches.
- Accept matches individually or apply all accepted matches together.
- Drag unmatched live characters onto unresolved roster positions for manual matching.
- Save multiple characters under one player alias.
- Store character name, realm, and class information separately.
- Search and manage saved aliases from the Alias Database window.

For example, an alias named `Pugz` can contain characters such as `Pugz`, `Pugzqt`, and `Pugzz`, allowing any known character to satisfy a roster position assigned to that player.

## Group Auto Swap

Automatically load a saved raid composition when configured NPC death conditions are met.

- Create multiple named Auto Swap presets.
- Trigger a composition after a specific NPC dies.
- Require multiple kills before a trigger fires.
- Configure repeating or one-time triggers.
- Restrict each preset to a particular raid instance.
- Allow activation anywhere for testing.
- Reset kill counters manually, after leaving a configured zone, or after a configured NPC death count.
- Import and export full presets or trigger collections.

## Player Auto Marking

Automatically apply raid icons to players when configured encounter events occur.

- Organize marking rules into named presets.
- Trigger rules from NPC deaths or Group Auto Swap events.
- Apply rules when any trigger, all triggers, or custom trigger conditions are satisfied.
- Assign marks by player name or raid position.
- Use Smart Assign to resolve a raid position through a saved Raid Group composition.
- Clear existing marks before applying a rule.
- Configure repeatable rules and reusable mark sets.
- Optionally retry temporarily unavailable players for a configurable duration.
- Restrict presets to selected raid instances or enable them anywhere for testing.
- Import and export complete presets or individual marking rules.

## Target Marks

Apply raid icons to NPCs by holding a configured modifier and moving the mouse over a target.

- Configure a main modifier and two alternative modifiers.
- Give the same NPC different mark priorities for each modifier.
- Add several possible marks to one NPC without duplicating its NPC ID.
- Cycle through available marks across multiple mobs of the same type.
- Organize NPC rules into named groupings such as raids, dungeons, or encounter sections.
- Store all groupings inside shareable presets.
- Import and export complete presets or individual groupings.

## Overall PRT Profiles

PRT Profiles combine the three automation features into one shareable setup.

Each overall profile selects:

- One Group Auto Swap preset.
- One Player Auto Marking preset.
- One Target Marks preset.
- Whether each feature should be enabled when that overall profile is selected.

Switching profiles loads the three assigned presets and applies their enabled defaults once. Features can still be toggled manually afterward without changing the saved profile defaults.

A single profile export contains the complete data for all three selected feature presets, making it easier to share or restore a full raid setup in one import.

## Raid Status Notifications

When entering a raid instance, PRT displays the current status of Group Auto Swap and Player Auto Marking, including:

- Whether each feature is enabled.
- Which preset is selected.
- Whether the selected preset is active in the current zone.

Manual feature toggles also produce a focused on-screen status notification.

## Additional Features

- Optional automatic combat logging inside raid instances.
- Resizable configuration window with screen-bound size limits.
- Minimap button for quick access.
- Class-coloured player and alias information.
- Customizable floating-list font, scale, color, outline, and background opacity.
- Configurable notification size, position, duration, and color, with optional sounds.
- Dependency-free installation.

## Slash Commands

| Command | Description |
|---|---|
| `/prt` | Open or close the configuration window. |
| `/prt help` | Display the available commands. |
| `/prt list` | Toggle the floating Raid Group list. |
| `/prt lock` | Lock or unlock the floating list. |
| `/prt groups show` | Show the floating list. |
| `/prt groups hide` | Hide the floating list. |
| `/prt autoswap on` | Enable Group Auto Swap. |
| `/prt autoswap off` | Disable Group Auto Swap. |
| `/prt automark on` | Enable Player Auto Marking. |
| `/prt automark off` | Disable Player Auto Marking. |
| `/prt targetmarks on` | Enable Target Marks. |
| `/prt targetmarks off` | Disable Target Marks. |
| `/prt sortlog` | Open the latest exact-position sort log. |
| `/prt reset` | Reset Group Auto Swap kill counters. |
| `/prt markreset` | Reset Player Auto Marking counters. |
| `/prt resetframe` | Restore the configuration window to its default size. |
| `/prt who CharacterName` | Find the alias containing a stored character. |
| `/prt alias AliasName` | List the characters stored under an alias. |

Character and alias names containing spaces can optionally be wrapped in quotation marks.

## Permissions and Compatibility

PugzRaidTools is designed for **WoW Classic Era**. Actions that rearrange raid groups or apply raid markers require the permissions normally required by the World of Warcraft client, such as raid leader or raid assistant.

The addon uses only the standard in-game API and does not require Ace3 or any other external addon library.
