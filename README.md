# Chords

Vim-style key chords for World of Warcraft Classic. Press a key that opens a **group**, then a
follow-up key to cast. `X` → `1` for Searing Totem, `X` → `Q` for Magma Totem, without
firing whatever those keys normally do.

- Groups hold spells, items, macros or other groups.
- Opening a group shows a flyout of clickable icons next to its button, like the totem bar.
- Only the group's own keys are intercepted. Pressing the group's key again, Escape, or using an entry closes it.
- Works in combat: everything runs through Blizzard's secure handlers.

## Use

`/chords` opens the editor.

1. Create a group (name = macro name, max 16 letters) and pick an icon.
2. Add entries: click the key button, press the key, type a spell (autocomplete) or use `...` for the spellbook list.
3. Place the group:
   - **"Separate action bar" unchecked** (default): an account-wide macro is created. Click **Pick up macro** and drop it on a normal action bar slot. The flyout attaches to that slot.
   - **Checked**: the group appears as a button on the movable Chords bar (Shift-drag to move) and uses no macro slot.
   - Or set **Open with key** to bind a key straight to the group.

Entries can also be `item:Name`, `macro:/cast ...` or `group:othername`.

## Commands

    /chords                         open the editor
    /chords list
    /chords add <group> <key> <spell | item:Name | macro:... | group:name>
    /chords del <group> [key]
    /chords enter <group> <key|none>
    /chords macro <group>
    /chords bar size <20-80>
    /chords reset                   clear temporary bindings if something sticks
    /chords debug

## Limits

- Group edits are not possible in combat (Blizzard restricts it).
- No timeout: closing a group means changing key bindings, which only secure code may do in combat, and secure code has no timers.
- Sub-group entries open by key but are not drawn as flyout icons.

MIT licensed.
