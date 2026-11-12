# Rested Watch

<img src="media/logo.png" alt="Rested Watch logo" width="128" align="right">

A WoW Forever addon that keeps track of rested XP on all your characters, including each character's own rank of the Well Rested Legacy perk.

- Shows how full each character's rested XP is, when it fills (countdown and clock time), and how long it has sat full.
- Suggests who to play next, and how much of the way to a target level each character's rested XP covers.
- Alerts you (toast, raid warning or chat) when an alt fills up, when the rested XP runs out, and when your Cozy Sleeping Bag is ready.
- Tracks rested XP used this session and about how many double-XP kills are left.
- Warns you when you log out outside an inn or city.
- Titan Panel plugin with an aligned table tooltip and all settings in its right-click menu. Works without Titan Panel too.

The game only reports rested XP for the character you're logged in on, so log each character in and out once to record it.

## Commands

- `/rested`: list your characters in chat
- `/rested target <level|off>`: only show characters below a level
- `/rested alert <toast|raid|chat|off>`: how alerts are shown
- `/rested sort <fullness|name|level|faction>`
- `/rested hide <name>`, `/rested show <name>`
- `/rested ranks <0-5>`: set the Well Rested rank by hand, only if it can't be read

## Installing

Install it from the WowUp Hub, or download the zip from Releases and extract the `RestedWatch` folder into `_forever_\Interface\AddOns`.

## License

GPL-3.0. See [LICENSE](LICENSE).
