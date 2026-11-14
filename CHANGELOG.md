# Changelog

## Unreleased
- Icons picked in the default macro window are now kept for the group.
- Only one chord can be open at a time, so groups can share keys.
- Flyout icons show the real spell/item tooltip on hover.
- Masque support, and EllesmereUI-style icon borders when EllesmereUI is installed.

## 1.0.0
- Chord groups: one key opens a group, a follow-up key casts a spell, uses an item, runs a macro or opens a sub-group.
- Only the group's own entry keys are intercepted; every other key keeps working.
- Flyout of clickable icons (like the totem bar) attached to the group's button.
- Visual editor (`/chords`): groups, key capture, spell autocomplete, spellbook browser, icon picker.
- Per-group "Separate action bar": on the movable Chords bar, or as an account-wide macro for your normal bars.
- Works in combat (secure handlers). No timeout, by design.
