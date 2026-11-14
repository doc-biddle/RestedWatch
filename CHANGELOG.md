# Rested Watch changelog

Versions follow semantic versioning: MAJOR.MINOR.PATCH.
MAJOR for changes that break saved settings or commands, MINOR for new features, PATCH for fixes.

## 1.4.4 (2026-11-14)
- With the Cozy Sleeping Bag's buff up, logging out no longer warns that you're not in an inn or city, and the character is recorded as resting, so its projection uses the inn rate. The bag counts as an inn even when the game doesn't report you as resting.

## 1.4.3 (2026-11-12)
- First release on CurseForge, uploaded automatically by the release pipeline. No changes to the addon itself.
- New logo, also used as the project icon on GitLab, GitHub, Wago and CurseForge.

## 1.4.2 (2026-11-12)
- First release on Wago (addons.wago.io), imported automatically from the GitHub release. No changes to the addon itself.
- The toc now has `X-Wago-ID`, so WowUp and Wago can match an installed copy to its Wago project.

## 1.4.1 (2026-11-12)
- No changes to the addon itself: this release moves it to the BigWigs packager.
- Releases are now published on GitLab (gitlab.com/docbiddle/RestedWatch) and GitHub (github.com/doc-biddle/RestedWatch), each with a `-forever.zip` and `release.json` for WowUp. Wago is next.
- The version shown in the AddOn List now comes from the release tag.
- Licensed under GPL-3.0.

## 1.4.0 (2026-11-12)
- Clock times: when each character fills ("today 18:40", "tomorrow 09:15", "Fri 14:20"), in a new "Full at" column and in the chat list.
- Session burn for the character you're playing: rested XP used this session and about how many kills are left at double XP. Shown at the bottom of the Titan tooltip and in `/rested`. Survives `/reload`.
- Alert when the rested XP runs out.
- Cozy Sleeping Bag: status (ready, buff time left, cooldown) and a reminder when it comes off cooldown, unless you're in combat, in a dungeon, already full, or past your target level.
- The Titan menu "When an alt fills up" is now "Alerts": how alerts are shown, plus a switch for each kind.

## 1.3.1 (2026-11-12)
- Icon and version number in the game's AddOn List.

## 1.3.0 (2026-11-12)
- Alert when an alt fills up while you play: a toast at the top of the screen (default), a raid warning, a chat message only, or nothing. Set it in the Titan menu under "When an alt fills up" (with a "Test it" button) or with `/rested alert toast|raid|chat|off`.
- "To <target>" column: how much of the way to your target level each character's rested XP covers. "Play next" now picks by this when a target is set.
- "Wasted" column: total time each character has spent sitting on full rested XP.
- Sort the list by how full, name, level or faction (Titan menu "Sort by", or `/rested sort`).

## 1.2.0 (2026-11-12)
- Titan tooltip drawn as an aligned table (LibQTip): faction, class, name, level, Well Rested rank, bar, percentage, time.
- Settings in the Titan right-click menu: target level, which characters to show, what the button shows, logout warning, login messages.
- Logout warning when leaving outside an inn or city.
- "Play next" suggestion and target level (`/rested target`).
- Login message naming characters that filled up while you were away.
- Progress bars in the tooltip; faction and class crests; full character names.

## 1.1.0 (2026-11-11)
- Native Titan Panel plugin; LibDataBroker fallback without Titan.
- Well Rested rank read per character from the Legacy tree.
- Fixed characters being saved with no XP data at logout.

## 1.0.0 (2026-11-11)
- First version: per-character rested XP projection, `/rested` list, self-calibration.
