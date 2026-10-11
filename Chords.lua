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

-- on-screen bar: a movable strip of visible group buttons (no macro slot needed)
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local bar = CreateFrame("Frame", "ChordsBar", UIParent)
bar:SetSize(10, 10)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:SetPoint("CENTER", UIParent, "CENTER", 0, -200)

local function restoreBarPos()
    local p = ChordsDB.bar
    if p and p.point then
        bar:ClearAllPoints()
        bar:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    end
end
local function saveBarPos()
    local point, _, _, x, y = bar:GetPoint()
    ChordsDB.bar = ChordsDB.bar or {}
    ChordsDB.bar.point, ChordsDB.bar.x, ChordsDB.bar.y = point, x, y
end
local wrapped = {}   -- frames that carry wraps from the last rebuild
local hints = {}     -- group name -> hint text
local hintFrame

local CLOSE_SNIPPET = [[
    self:ClearBindings()
    local n = self:GetAttribute("ecount") or 0
    for i = 1, n do
        if self:GetAttribute("eshow" .. i) then
            local b = self:GetFrameRef("eb" .. i)
            if b then b:Hide() end
        end
    end
]]
local CLOSE_CALL = 'control:RunAttribute("close")'

local GROUP_SNIPPET = [[
    self:RunAttribute("close")
    if (self:GetAttribute("ecount") or 0) == 0 then return end
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
    local toggle = self:GetAttribute("toggle")
    if toggle then self:SetBindingClick(true, toggle, self:GetAttribute("cancel")) end
    self:SetBindingClick(true, "ESCAPE", self:GetAttribute("cancel"))
    for i = 1, n do
        if self:GetAttribute("eshow" .. i) then
            local b = self:GetFrameRef("eb" .. i)
            if b then b:Show() end
        end
    end
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
            for _, m in ipairs(mods) do
                local key = m .. b
                local action = GetBindingAction(key)
                if action and action ~= "" then out[#out + 1] = key end
            end
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
    -- this client's SecureHandlerWrapScript rejects a nil pre-body, so pass empty strings
    -- postBody only runs if preBody returns (newbutton, message) with a non-nil message,
    -- and the snippets see the header as `control`, not `owner`.
    if post and not pre then pre = 'return nil, "x"' end
    SecureHandlerWrapScript(f, "OnClick", header, pre or "", post or "")
    wrapped[#wrapped + 1] = f
end

---------------------------------------------------------------------------
-- hint popup (insecure, purely cosmetic)
---------------------------------------------------------------------------

local function hideHint()
    if hintFrame then hintFrame:Hide() end
end

local function showHint(group)
    if Chords.hasFlyout and Chords.hasFlyout[group] then return end
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
        f = CreateFrame("Button", "ChordsGroup_" .. g, bar, "SecureHandlerClickTemplate")
        f:RegisterForClicks("AnyUp")
        f:SetAttribute("_onclick", GROUP_SNIPPET)
        f:SetAttribute("close", CLOSE_SNIPPET)
        f:HookScript("OnClick", function() showHint(g) end)
        f:Hide()
        f.icon = f:CreateTexture(nil, "BACKGROUND")
        f.icon:SetAllPoints()
        f.keyText = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        f.keyText:SetPoint("TOPRIGHT", -2, -3)
        f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        f:RegisterForDrag("LeftButton")
        f:HookScript("OnDragStart", function()
            if IsShiftKeyDown() and not InCombatLockdown() then bar:StartMoving() end
        end)
        f:HookScript("OnDragStop", function() bar:StopMovingOrSizing() saveBarPos() end)
        f:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(hints[g] or g)
            GameTooltip:AddLine("Shift-drag to move the bar", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        f:HookScript("OnLeave", function() GameTooltip:Hide() end)
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
        f:SetFrameStrata("DIALOG")
        f:Hide() -- shown by the group's secure snippet while the group is open
        f.icon = f:CreateTexture(nil, "BACKGROUND")
        f.icon:SetAllPoints()
        f.keyText = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        f.keyText:SetPoint("TOPRIGHT", -2, -3)
        f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        f:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label or "")
            GameTooltip:Show()
        end)
        f:HookScript("OnLeave", function() GameTooltip:Hide() end)
        entryFrames[g][i] = f
    end
    return f
end

local function resetAction(f)
    for _, a in ipairs({ "type", "spell", "item", "macrotext" }) do f:SetAttribute(a, nil) end
    f:SetAttribute("useOnKeyDown", false)
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

local function shortKey(k)
    return (k:gsub("SHIFT%-", "S-"):gsub("CTRL%-", "C-"):gsub("ALT%-", "A-"))
end

local function actionIcon(act)
    local icon
    if act.spell then
        local _, i = spellKnown(act.spell)
        icon = i
    elseif act.item then
        icon = select(10, GetItemInfo(act.item))
    elseif act.macro then
        icon = "Interface\\Icons\\INV_Misc_Note_01"
    end
    return icon or DEFAULT_ICON
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
    local size = ChordsDB.barSize or 40
    self.hasFlyout = {}
    for _, list in pairs(entryFrames) do
        for _, ef in pairs(list) do ef:Hide() end
    end
    ClearOverrideBindings(binder)

    local blocked = blockList()
    self.lastBlocked = blocked
    -- make sure every referenced sub-group has a frame
    for g, grp in pairs(ChordsDB.groups) do
        for _, act in pairs(grp.entries) do
            if act.group and ChordsDB.groups[act.group] then groupFrame(act.group) end
        end
    end

    for g, grp in pairs(ChordsDB.groups) do
        local gf = groupFrame(g)
        local cf = cancelFrame(g)
        wrap(cf, gf, nil, CLOSE_CALL)
        gf:SetAttribute("cancel", cf:GetName())
        local keys = {}
        for k in pairs(grp.entries) do keys[#keys + 1] = k end
        table.sort(keys)

        local mine = {}
        for _, k in ipairs(keys) do mine[k] = true end
        local kept = {}
        for key in blocked:gmatch("%S+") do
            if not mine[key] then kept[#kept + 1] = key end
        end
        gf:SetAttribute("bkeys", #kept > 0 and table.concat(kept, " ") or nil)
        gf:SetAttribute("toggle", grp.enter)

        local lines = { "|cffffd100" .. g .. "|r" }
        local n, ne = 0, 0
        for _, k in ipairs(keys) do
            local act = grp.entries[k]
            local btn, isIcon
            if act.group then
                if ChordsDB.groups[act.group] then
                    btn = groupFrame(act.group)
                    -- opening a sub-group closes this group's layer first
                    wrap(btn, gf, CLOSE_CALL, nil)
                end
                isIcon = false
            else
                n = n + 1
                btn = entryFrame(g, n)
                setAction(btn, act)
                wrap(btn, gf, nil, CLOSE_CALL)
                -- flyout icon, stacked upward from the group button
                btn:SetSize(size, size)
                btn:ClearAllPoints()
                btn:SetPoint("BOTTOM", gf, "TOP", 0, 6 + (n - 1) * (size + 4))
                btn.icon:SetTexture(actionIcon(act))
                btn.keyText:SetText(shortKey(k))
                btn.label = describe(act)
                self.hasFlyout[g] = true
                isIcon = true
            end
            if btn then
                ne = ne + 1
                lines[#lines + 1] = ("|cff00ff00%s|r  %s"):format(k, describe(act))
                gf:SetAttribute("ekey" .. ne, k)
                gf:SetAttribute("ebtn" .. ne, btn:GetName())
                gf:SetAttribute("eshow" .. ne, isIcon or nil)
                gf:SetFrameRef("eb" .. ne, btn)
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
            gf:Hide()
        end
    end

    -- lay out the on-screen bar
    restoreBarPos()
    local names = {}
    for g in pairs(ChordsDB.groups) do names[#names + 1] = g end
    table.sort(names)
    local x = 0
    for _, g in ipairs(names) do
        local grp, gf = ChordsDB.groups[g], groupFrames[g]
        if grp.show then
            gf:ClearAllPoints()
            gf:SetSize(size, size)
            gf:SetPoint("LEFT", bar, "LEFT", x, 0)
            gf.icon:SetTexture(grp.icon or DEFAULT_ICON)
            gf.keyText:SetText(grp.enter and grp.enter:gsub("SHIFT%-", "S-"):gsub("CTRL%-", "C-"):gsub("ALT%-", "A-") or "")
            gf:Show()
            x = x + size + 4
        else
            gf:ClearAllPoints()
            gf:SetSize(size, size)
            gf:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
            gf:Hide()
        end
    end
    bar:SetSize(math.max(x - 4, 10), size)
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
    print("  /chords bar size <20-80>            -- size of the on-screen buttons")
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

-- Create or update the "/click" macro that launches a group (name = group name, icon = group icon).
function Chords.SyncMacro(g, pickup)
    local grp = ChordsDB.groups[g]
    if not grp then return false, "no such group" end
    if InCombatLockdown() then return false, "not in combat" end
    local name = g:sub(1, 16)
    local icon = grp.icon or "INV_Misc_QuestionMark"
    local body = "/click ChordsGroup_" .. g
    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        EditMacro(idx, name, icon, body)
    else
        local ok, err = pcall(CreateMacro, name, icon, body, nil)
        if not ok then return false, tostring(err) end
    end
    if pickup then PickupMacro(name) end
    return true
end

function Chords.RenameGroup(old, new)
    new = normGroup(new)
    if new == "" or new == old or not ChordsDB.groups[old] then return false end
    if ChordsDB.groups[new] then say("a group named '" .. new .. "' already exists") return false end
    if InCombatLockdown() then say("not in combat") return false end
    local idx = GetMacroIndexByName(old:sub(1, 16))
    ChordsDB.groups[new], ChordsDB.groups[old] = ChordsDB.groups[old], nil
    for _, grp in pairs(ChordsDB.groups) do
        for _, act in pairs(grp.entries) do
            if act.group == old then act.group = new end
        end
    end
    if idx and idx > 0 then
        EditMacro(idx, new:sub(1, 16), ChordsDB.groups[new].icon or "INV_Misc_QuestionMark", "/click ChordsGroup_" .. new)
    end
    Chords:Rebuild()
    return true
end

function handlers.debug()
    for g, gf in pairs(groupFrames) do
        if ChordsDB.groups[g] then
            local bk = gf:GetAttribute("bkeys")
            say(("%s: entries=%s blocked=%s cancel=%s"):format(g, tostring(gf:GetAttribute("ecount")),
                bk and select(2, bk:gsub(" ", " ")) + 1 or 0, tostring(gf:GetAttribute("cancel"))))
            for i = 1, gf:GetAttribute("ecount") or 0 do
                local b = _G[gf:GetAttribute("ebtn" .. i) or ""]
                print(("   %s -> %s type=%s spell=%s keydown=%s"):format(tostring(gf:GetAttribute("ekey" .. i)),
                    tostring(gf:GetAttribute("ebtn" .. i)), tostring(b and b:GetAttribute("type")),
                    tostring(b and b:GetAttribute("spell")), tostring(b and b:GetAttribute("useOnKeyDown"))))
            end
        end
    end
    local sample = {}
    for key in blockList():gmatch("%S+") do
        if #sample < 12 then sample[#sample + 1] = key end
    end
    say("blocked keys (first 12): " .. table.concat(sample, " "))
    say("ActionButtonUseKeyDown = " .. tostring(GetCVar("ActionButtonUseKeyDown")))
end

function handlers.reset()
    ClearOverrideBindings(binder)
    for _, gf in pairs(groupFrames) do
        if not InCombatLockdown() then gf:SetAttribute("ecount", 0) end
    end
    say("cleared. /reload to fully restore your bindings.")
end

function handlers.bar(args)
    local n = tonumber(args:match("^size%s+(%d+)"))
    if n then
        ChordsDB.barSize = math.min(math.max(n, 20), 80)
        Chords:Rebuild()
    else
        say("/chords bar size <20-80>. Tick 'On screen' for a group in the editor; shift-drag a button to move the bar.")
    end
end

function handlers.macro(args)
    local g = normGroup(args or "")
    local ok, err = Chords.SyncMacro(g, false)
    if ok then
        say(("macro '%s' ready (open /macro, drag it onto the slot that has your key)."):format(g:sub(1, 16)))
    else
        say("|cffff5555macro failed:|r " .. err)
    end
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
ev:RegisterEvent("UPDATE_BINDINGS")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Chords" then
        ChordsDB = ChordsDB or {}
        ChordsDB.groups = ChordsDB.groups or {}
        ChordsDB.passthrough = ChordsDB.passthrough or {}
    elseif event == "PLAYER_LOGIN" then
        Chords:Rebuild()
    elseif event == "UPDATE_BINDINGS" then
        if ChordsDB and ChordsDB.groups then
            C_Timer.After(0.5, function()
                if blockList() ~= Chords.lastBlocked then Chords:Rebuild() end
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Chords.pending then Chords:Rebuild() end
    end
end)
