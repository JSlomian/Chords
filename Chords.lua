-- Chords: group keys that open a temporary layer of follow-up keys.
--
-- Mechanism: every group is a SecureHandlerClickTemplate button. Clicking it (via a
-- "/click ChordsGroup_<name>" macro on an action bar slot, or a direct "enter" key)
-- runs a restricted snippet that sets priority override bindings:
--   1. every key in the block list -> ChordsNoop (so nothing else fires),
--   2. each entry key -> its own secure action button (spell/item/macro) or sub-group,
--   3. ESCAPE -> cancel.
-- Entry/cancel buttons are wrapped so that after they fire the group's bindings are cleared.
-- Binding changes in combat are only allowed from this secure code, so all frames and
-- attributes are (re)built out of combat only.

local Chords = {}
_G.Chords = Chords

local PREFIX = "|cff66ccffChords|r: "
local function say(msg) print(PREFIX .. msg) end

local binder = CreateFrame("Frame") -- owner of the persistent "enter" override bindings
local groupFrames, entryFrames, cancelFrames = {}, {}, {}
local wrapped = {}   -- frames that carry wraps from the last rebuild
local hints = {}     -- group name -> hint text
local hintFrame

local GROUP_SNIPPET = [[
    self:ClearBindings()
    local keys = self:GetAttribute("bkeys")
    if keys then
        local t = newtable(strsplit(" ", keys))
        for i = 1, #t do
            self:SetBindingClick(true, t[i], "ChordsNoop")
        end
    end
    local n = self:GetAttribute("ecount") or 0
    for i = 1, n do
        self:SetBindingClick(true, self:GetAttribute("ekey" .. i), self:GetAttribute("ebtn" .. i))
    end
    self:SetBindingClick(true, "ESCAPE", self:GetAttribute("cancel"))
]]

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function normKey(k)
    return (k:upper():gsub("%s", ""))
end

local function normGroup(g)
    return (g:gsub("[^%w]", ""))
end

local function spellKnown(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        if info then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local n, _, icon = GetSpellInfo(name)
        return n, icon
    end
end

local function blockList()
    local bases = {}
    for c = 65, 90 do bases[#bases + 1] = string.char(c) end
    for d = 0, 9 do bases[#bases + 1] = tostring(d) end
    for f = 1, 12 do bases[#bases + 1] = "F" .. f end
    for _, k in ipairs({ "-", "=", "[", "]", ";", "'", ",", ".", "/", "\\", "`", "SPACE", "TAB" }) do
        bases[#bases + 1] = k
    end
    local mods = { "", "SHIFT-", "CTRL-", "SHIFT-CTRL-", "ALT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }
    local pass = {}
    for _, k in ipairs(ChordsDB.passthrough or {}) do pass[normKey(k)] = true end
    local out = {}
    for _, b in ipairs(bases) do
        if not pass[b] then
            for _, m in ipairs(mods) do out[#out + 1] = m .. b end
        end
    end
    return table.concat(out, " ")
end

local function unwrapAll()
    for _, f in ipairs(wrapped) do
        while true do
            local pre, post = SecureHandlerUnwrapScript(f, "OnClick")
            if pre == nil and post == nil then break end
        end
    end
    wipe(wrapped)
end

local function wrap(f, header, pre, post)
    SecureHandlerWrapScript(f, "OnClick", header, pre, post)
    wrapped[#wrapped + 1] = f
end

---------------------------------------------------------------------------
-- hint popup (insecure, purely cosmetic)
---------------------------------------------------------------------------

local function hideHint()
    if hintFrame then hintFrame:Hide() end
end

local function showHint(group)
    if not hintFrame then
        hintFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        hintFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
        hintFrame:SetFrameStrata("DIALOG")
        hintFrame.text = hintFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hintFrame.text:SetPoint("CENTER")
        hintFrame.text:SetJustifyH("LEFT")
        if hintFrame.SetBackdrop then
            hintFrame:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            hintFrame:SetBackdropColor(0, 0, 0, 0.8)
        end
    end
    hintFrame.text:SetText(hints[group] or group)
    hintFrame:SetSize(hintFrame.text:GetStringWidth() + 24, hintFrame.text:GetStringHeight() + 20)
    hintFrame:Show()
end

---------------------------------------------------------------------------
-- frame factories (created once, reused across rebuilds)
---------------------------------------------------------------------------

local noop = CreateFrame("Button", "ChordsNoop", UIParent, "SecureActionButtonTemplate")
noop:RegisterForClicks("AnyUp")

local function groupFrame(g)
    local f = groupFrames[g]
    if not f then
        f = CreateFrame("Button", "ChordsGroup_" .. g, UIParent, "SecureHandlerClickTemplate")
        f:RegisterForClicks("AnyUp")
        f:SetAttribute("_onclick", GROUP_SNIPPET)
        f:HookScript("OnClick", function() showHint(g) end)
        groupFrames[g] = f
    end
    return f
end

local function cancelFrame(g)
    local f = cancelFrames[g]
    if not f then
        f = CreateFrame("Button", "ChordsCancel_" .. g, UIParent, "SecureActionButtonTemplate")
        f:RegisterForClicks("AnyUp")
        f:HookScript("OnClick", hideHint)
        cancelFrames[g] = f
    end
    return f
end

local function entryFrame(g, i)
    entryFrames[g] = entryFrames[g] or {}
    local f = entryFrames[g][i]
    if not f then
        f = CreateFrame("Button", "ChordsEntry_" .. g .. "_" .. i, UIParent, "SecureActionButtonTemplate")
        f:RegisterForClicks("AnyUp")
        f:HookScript("OnClick", hideHint)
        entryFrames[g][i] = f
    end
    return f
end

local function resetAction(f)
    for _, a in ipairs({ "type", "spell", "item", "macrotext" }) do f:SetAttribute(a, nil) end
end

local function setAction(f, act)
    resetAction(f)
    if act.spell then
        f:SetAttribute("type", "spell"); f:SetAttribute("spell", act.spell)
    elseif act.item then
        f:SetAttribute("type", "item"); f:SetAttribute("item", act.item)
    elseif act.macro then
        f:SetAttribute("type", "macro"); f:SetAttribute("macrotext", act.macro)
    end
end

local function describe(act)
    return act.spell or (act.item and ("item: " .. act.item)) or (act.macro and "macro")
        or (act.group and ("group: " .. act.group)) or "?"
end

---------------------------------------------------------------------------
-- rebuild
---------------------------------------------------------------------------

function Chords:Rebuild()
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = false
    unwrapAll()
    ClearOverrideBindings(binder)

    local blocked = blockList()
    -- make sure every referenced sub-group has a frame
    for g, grp in pairs(ChordsDB.groups) do
        for _, act in pairs(grp.entries) do
            if act.group and ChordsDB.groups[act.group] then groupFrame(act.group) end
        end
    end

    for g, grp in pairs(ChordsDB.groups) do
        local gf = groupFrame(g)
        local cf = cancelFrame(g)
        wrap(cf, gf, nil, "owner:ClearBindings()")
        gf:SetAttribute("cancel", cf:GetName())
        gf:SetAttribute("bkeys", blocked)

        local keys = {}
        for k in pairs(grp.entries) do keys[#keys + 1] = k end
        table.sort(keys)

        local lines = { "|cffffd100" .. g .. "|r" }
        local n, ne = 0, 0
        for _, k in ipairs(keys) do
            local act = grp.entries[k]
            local btn
            if act.group then
                if ChordsDB.groups[act.group] then
                    btn = groupFrame(act.group)
                    -- opening a sub-group closes this group's layer first
                    wrap(btn, gf, "owner:ClearBindings()", nil)
                end
            else
                n = n + 1
                btn = entryFrame(g, n)
                setAction(btn, act)
                wrap(btn, gf, nil, "owner:ClearBindings()")
            end
            if btn then
                ne = ne + 1
                lines[#lines + 1] = ("|cff00ff00%s|r  %s"):format(k, describe(act))
                gf:SetAttribute("ekey" .. ne, k)
                gf:SetAttribute("ebtn" .. ne, btn:GetName())
            end
        end
        gf:SetAttribute("ecount", ne)
        hints[g] = table.concat(lines, "\n")

        if grp.enter then
            SetOverrideBindingClick(binder, true, grp.enter, gf:GetName(), "LeftButton")
        end
    end

    -- stale groups: neutralise so a leftover macro does nothing
    for g, gf in pairs(groupFrames) do
        if not ChordsDB.groups[g] then
            gf:SetAttribute("ecount", 0)
            gf:SetAttribute("bkeys", nil)
        end
    end
end

---------------------------------------------------------------------------
-- slash commands
---------------------------------------------------------------------------

local function parseAction(text)
    local kind, rest = text:match("^(%a+):(.+)$")
    if kind == "item" then return { item = rest }
    elseif kind == "macro" then return { macro = rest }
    elseif kind == "group" then return { group = normGroup(rest) }
    end
    return { spell = text }
end

local function help()
    say("commands:")
    print("  /chords                              -- open the visual editor")
    print("  /chords list")
    print("  /chords add <group> <key> <spell name | item:Name | macro:/cast ... | group:other>")
    print("  /chords del <group> [key]")
    print("  /chords enter <group> <key|none>   -- bind a key directly (or use the macro)")
    print("  /chords macro <group>               -- create a '/click' macro to drag onto a bar")
    print("  /chords pass <key> [<key>...]       -- keys NOT blocked while a group is open (e.g. W A S D)")
end

local handlers = {}

-- shared with Editor.lua
Chords.normKey, Chords.normGroup, Chords.parseAction = normKey, normGroup, parseAction
Chords.spellKnown, Chords.describe = spellKnown, describe

function handlers.list()
    if not next(ChordsDB.groups) then say("no groups yet. /chords add fire 1 Searing Totem") return end
    for g, grp in pairs(ChordsDB.groups) do
        print(("|cffffd100%s|r  enter: %s  click: /click ChordsGroup_%s"):format(g, grp.enter or "(macro)", g))
        local keys = {}
        for k in pairs(grp.entries) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do print(("   %s  %s"):format(k, describe(grp.entries[k]))) end
    end
end

function handlers.add(args)
    local g, k, text = args:match("^(%S+)%s+(%S+)%s+(.+)$")
    if not g then return help() end
    g, k = normGroup(g), normKey(k)
    local act = parseAction(text)
    if act.spell then
        local name = spellKnown(act.spell)
        if not name then say("|cffff5555unknown spell:|r " .. act.spell) return end
        act.spell = act.spell -- keep what the user typed (supports "Name(Rank 2)")
    end
    ChordsDB.groups[g] = ChordsDB.groups[g] or { entries = {} }
    ChordsDB.groups[g].entries[k] = act
    say(("%s %s -> %s"):format(g, k, describe(act)))
    Chords:Rebuild()
end

function handlers.del(args)
    local g, k = args:match("^(%S+)%s*(%S*)$")
    if not g then return help() end
    g = normGroup(g)
    local grp = ChordsDB.groups[g]
    if not grp then say("no such group") return end
    if k == "" then ChordsDB.groups[g] = nil else grp.entries[normKey(k)] = nil end
    Chords:Rebuild()
end

function handlers.enter(args)
    local g, k = args:match("^(%S+)%s+(%S+)$")
    if not g then return help() end
    g = normGroup(g)
    if not ChordsDB.groups[g] then say("no such group") return end
    ChordsDB.groups[g].enter = (k:lower() ~= "none") and normKey(k) or nil
    Chords:Rebuild()
end

function handlers.pass(args)
    ChordsDB.passthrough = {}
    for k in args:gmatch("%S+") do table.insert(ChordsDB.passthrough, normKey(k)) end
    say("pass-through keys: " .. (#ChordsDB.passthrough > 0 and table.concat(ChordsDB.passthrough, " ") or "(none)"))
    Chords:Rebuild()
end

function handlers.macro(args)
    local g = normGroup(args or "")
    if not ChordsDB.groups[g] then say("no such group") return end
    if InCombatLockdown() then say("not in combat") return end
    local name = "C_" .. g:sub(1, 14)
    local body = "/click ChordsGroup_" .. g
    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        EditMacro(idx, name, "INV_Misc_QuestionMark", body)
    else
        local ok, err = pcall(CreateMacro, name, "INV_Misc_QuestionMark", body, nil)
        if not ok then say("|cffff5555could not create macro:|r " .. tostring(err)) return end
    end
    say(("macro '%s' ready (open /macro, drag it onto the slot that has your key)."):format(name))
end

SLASH_CHORDS1 = "/chords"
SlashCmdList.CHORDS = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    local h = handlers[cmd:lower()]
    if h then h(rest)
    elseif cmd == "" and Chords.ToggleEditor then Chords.ToggleEditor()
    else help() end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Chords" then
        ChordsDB = ChordsDB or {}
        ChordsDB.groups = ChordsDB.groups or {}
        ChordsDB.passthrough = ChordsDB.passthrough or {}
    elseif event == "PLAYER_LOGIN" then
        Chords:Rebuild()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Chords.pending then Chords:Rebuild() end
    end
end)
