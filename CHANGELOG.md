# Changelog

## 1.0.0
- Chord groups: one key opens a group, a follow-up key casts a spell, uses an item, runs a macro or opens a sub-group.
- Only the group's own entry keys are intercepted; every other key keeps working.
- Only one chord can be open at a time, so groups can share keys.
- Flyout of clickable icons (like the totem bar) attached to the group's button, with the real spell/item tooltip on hover.
- Spell ranks: flyout icons and editor rows show the rank that will be cast (gold when downranked), and the tooltip shows "Rank N" like the spellbook. Type `Name(Rank N)` to downrank.
- Cooldown and GCD swipes on flyout icons, like action bar buttons.
- Per-group "Stay open after cast": casting doesn't close the chord, so a press that fails on the GCD costs nothing. Close with Esc or the open key.
- Visual editor (`/chords`): groups, key capture, spell autocomplete, icon picker, and a spellbook browser that also lists on-use items from your bags and worn gear, with a "Show ranks" checkbox.
- Icons picked in the default macro window are kept for the group.
- Per-group "Separate action bar": on the movable Chords bar, or as an account-wide macro for your normal bars.
- Masque support, and EllesmereUI-style icon borders when EllesmereUI is installed.
- Works in combat (secure handlers). No timeout, by design.
