-- Visual editor for Chords: /chords opens it.
-- Left: groups. Right: the selected group's open-key and its entries (key + spell/item/macro).
-- All edits write straight into ChordsDB and call Chords:Rebuild(); locked during combat.

local Chords = _G.Chords
local E = { drafts = {}, spells = {} }
local selected
local picker -- icon picker frame, created below
local ROW_H = 30
local rows, groupBtns = {}, {}

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true,
}

local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function locked()
    if InCombatLockdown() then
        print("|cff66ccffChords|r: can't edit during combat")
        return true
    end
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

---------------------------------------------------------------------------
-- spellbook scan
---------------------------------------------------------------------------

function E:ScanSpells()
    local list, seen = {}, {}
    local getName = GetSpellBookItemName or GetSpellName
    if not getName or not GetNumSpellTabs then self.spells = list return end
    for t = 1, GetNumSpellTabs() do
        local _, _, offset, num = GetSpellTabInfo(t)
        for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
            local name = getName(i, "spell")
            if name and not seen[name] and not (IsPassiveSpell and IsPassiveSpell(i, "spell")) then
                seen[name] = true
                local _, icon = Chords.spellKnown(name)
                list[#list + 1] = { name = name, icon = icon }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    self.spells = list
end

---------------------------------------------------------------------------
-- main frame
---------------------------------------------------------------------------

local f = CreateFrame("Frame", "ChordsEditor", UIParent, "BackdropTemplate")
f:SetSize(660, 460)
f:SetPoint("CENTER")
f:SetBackdrop(BACKDROP)
f:SetFrameStrata("HIGH")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()
tinsert(UISpecialFrames, "ChordsEditor")

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Chords")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

---------------------------------------------------------------------------
-- key capture
---------------------------------------------------------------------------

local function buildKey(key)
    local p = ""
    if IsAltKeyDown() then p = p .. "ALT-" end
    if IsControlKeyDown() then p = p .. "CTRL-" end
    if IsShiftKeyDown() then p = p .. "SHIFT-" end
    return p .. key
end

local function captureKey(btn, onKey)
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus then focus:ClearFocus() end
    btn:SetText("press a key...")
    btn:EnableKeyboard(true)
    btn:SetScript("OnKeyDown", function(self, key)
        if MODIFIER_KEYS[key] then return end
        self:SetPropagateKeyboardInput(false)
        self:EnableKeyboard(false)
        self:SetScript("OnKeyDown", nil)
        if key ~= "ESCAPE" then onKey(buildKey(key)) end
        E:Refresh()
    end)
end

---------------------------------------------------------------------------
-- spell browser + autocomplete
---------------------------------------------------------------------------

local function commitRow(r) end -- defined below

local browser = CreateFrame("Frame", "ChordsSpellBrowser", f, "BackdropTemplate")
browser:SetSize(260, 460)
browser:SetPoint("TOPLEFT", f, "TOPRIGHT", -6, 0)
browser:SetBackdrop(BACKDROP)
browser:Hide()

local bTitle = browser:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bTitle:SetPoint("TOP", 0, -18)
bTitle:SetText("Spellbook")

local bSearch = CreateFrame("EditBox", nil, browser, "InputBoxTemplate")
bSearch:SetSize(200, 22)
bSearch:SetPoint("TOP", 0, -42)
bSearch:SetAutoFocus(false)

local bScroll = CreateFrame("ScrollFrame", "ChordsSpellScroll", browser, "UIPanelScrollFrameTemplate")
bScroll:SetPoint("TOPLEFT", 18, -72)
bScroll:SetPoint("BOTTOMRIGHT", -36, 18)
local bContent = CreateFrame("Frame", nil, bScroll)
bContent:SetSize(200, 10)
bScroll:SetScrollChild(bContent)
local bBtns = {}

local function refreshBrowser()
    local q = bSearch:GetText():lower()
    local n = 0
    for _, s in ipairs(E.spells) do
        if q == "" or s.name:lower():find(q, 1, true) then
            n = n + 1
            local b = bBtns[n]
            if not b then
                b = CreateFrame("Button", nil, bContent)
                b:SetSize(200, 22)
                b:SetPoint("TOPLEFT", 0, -(n - 1) * 22)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetSize(18, 18)
                b.icon:SetPoint("LEFT", 2, 0)
                b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
                b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                b:SetScript("OnClick", function(self)
                    local r = browser.target
                    if r then
                        r.edit:SetText(self.spell)
                        commitRow(r)
                    end
                    browser:Hide()
                end)
                bBtns[n] = b
            end
            b.spell = s.name
            b.icon:SetTexture(s.icon)
            b.text:SetText(s.name)
            b:Show()
        end
    end
    for i = n + 1, #bBtns do bBtns[i]:Hide() end
    bContent:SetHeight(math.max(n * 22, 10))
end
bSearch:SetScript("OnTextChanged", function(_, user) if user then refreshBrowser() end end)
bSearch:SetScript("OnEscapePressed", bSearch.ClearFocus)

local function openBrowser(r)
    E:ScanSpells()
    if picker then picker:Hide() end
    browser.target = r
    bSearch:SetText("")
    refreshBrowser()
    browser:Show()
end

-- autocomplete dropdown under the focused action box
local dd = CreateFrame("Frame", nil, f, "BackdropTemplate")
dd:SetFrameStrata("DIALOG")
dd:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
dd:SetBackdropColor(0, 0, 0, 0.95)
dd:SetSize(240, 10)
dd:Hide()
local ddBtns = {}
for i = 1, 8 do
    local b = CreateFrame("Button", nil, dd)
    b:SetSize(230, 18)
    b:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 18)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 4, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b:SetScript("OnClick", function(self)
        local r = dd.target
        dd:Hide()
        if r then
            r.edit:SetText(self.spell)
            r.edit:ClearFocus()
            commitRow(r)
        end
    end)
    ddBtns[i] = b
end

local function showSuggest(r)
    local text = trim(r.edit:GetText()):lower()
    if text == "" or text:find(":", 1, true) then dd:Hide() return end
    if #E.spells == 0 then E:ScanSpells() end
    local starts, contains = {}, {}
    for _, s in ipairs(E.spells) do
        local n = s.name:lower()
        if n == text then
            -- exact match: nothing to suggest
        elseif n:sub(1, #text) == text then starts[#starts + 1] = s.name
        elseif n:find(text, 1, true) then contains[#contains + 1] = s.name end
    end
    for _, n in ipairs(contains) do starts[#starts + 1] = n end
    local shown = math.min(#starts, 8)
    if shown == 0 then dd:Hide() return end
    for i = 1, 8 do
        local b = ddBtns[i]
        if i <= shown then b.spell = starts[i]; b.text:SetText(starts[i]); b:Show() else b:Hide() end
    end
    dd:SetHeight(shown * 18 + 10)
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", r.edit, "BOTTOMLEFT", -4, 0)
    dd.target = r
    dd:Show()
end

---------------------------------------------------------------------------
-- entry rows
---------------------------------------------------------------------------

local scroll = CreateFrame("ScrollFrame", "ChordsEntryScroll", f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 200, -128)
scroll:SetPoint("BOTTOMRIGHT", -38, 56)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(400, 10)
scroll:SetScrollChild(content)

local function actionIcon(act)
    if act.spell then
        local _, icon = Chords.spellKnown(act.spell)
        return icon
    elseif act.item then
        return select(10, GetItemInfo(act.item))
    elseif act.macro then
        return "Interface\\Icons\\INV_Misc_Note_01"
    elseif act.group then
        return "Interface\\Icons\\INV_Misc_Book_09"
    end
end

local function validAction(g, act)
    if not act then return false end
    if act.spell then return Chords.spellKnown(act.spell) ~= nil end
    if act.group then return act.group ~= g and ChordsDB.groups[act.group] ~= nil end
    return true
end

function commitRow(r)
    if locked() then return end
    local g = selected
    local grp = g and ChordsDB.groups[g]
    if not grp then return end
    local text = trim(r.edit:GetText())
    local act = text ~= "" and Chords.parseAction(text) or nil
    local ok = validAction(g, act)
    r.edit:SetTextColor(ok and 1 or 1, ok and 1 or 0.35, ok and 1 or 0.35)
    if r.draft then
        r.draft.text = text
        if ok and r.draft.key and not grp.entries[r.draft.key] then
            grp.entries[r.draft.key] = act
            for i, d in ipairs(E.drafts[g]) do
                if d == r.draft then table.remove(E.drafts[g], i) break end
            end
            Chords:Rebuild()
            E:Refresh()
        end
    elseif ok then
        grp.entries[r.entryKey] = act
        Chords:Rebuild()
        E:Refresh()
    end
end

local function makeRow(i)
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(400, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

    r.keyBtn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.keyBtn:SetSize(92, 24)
    r.keyBtn:SetPoint("LEFT", 0, 0)
    r.keyBtn:SetScript("OnClick", function()
        if locked() then return end
        captureKey(r.keyBtn, function(key)
            local grp = ChordsDB.groups[selected]
            if r.draft then
                r.draft.key = key
                commitRow(r)
            elseif key ~= r.entryKey and not grp.entries[key] then
                grp.entries[key] = grp.entries[r.entryKey]
                grp.entries[r.entryKey] = nil
                Chords:Rebuild()
            end
        end)
    end)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", r.keyBtn, "RIGHT", 6, 0)

    r.edit = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
    r.edit:SetSize(190, 22)
    r.edit:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.edit:SetAutoFocus(false)
    r.edit:SetScript("OnTextChanged", function(_, user) if user then showSuggest(r) end end)
    r.edit:SetScript("OnEnterPressed", function(self) dd:Hide() self:ClearFocus() commitRow(r) end)
    r.edit:SetScript("OnEscapePressed", function(self) dd:Hide() self:ClearFocus() E:Refresh() end)
    r.edit:SetScript("OnEditFocusLost", function()
        commitRow(r)
        C_Timer.After(0.2, function() if not dd:IsMouseOver() then dd:Hide() end end)
    end)

    r.browse = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.browse:SetSize(26, 24)
    r.browse:SetPoint("LEFT", r.edit, "RIGHT", 6, 0)
    r.browse:SetText("...")
    r.browse:SetScript("OnClick", function() openBrowser(r) end)

    r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.del:SetSize(26, 24)
    r.del:SetPoint("LEFT", r.browse, "RIGHT", 2, 0)
    r.del:SetText("X")
    r.del:SetScript("OnClick", function()
        if locked() then return end
        local g = selected
        if r.draft then
            for i2, d in ipairs(E.drafts[g]) do
                if d == r.draft then table.remove(E.drafts[g], i2) break end
            end
        else
            ChordsDB.groups[g].entries[r.entryKey] = nil
            Chords:Rebuild()
        end
        E:Refresh()
    end)
    return r
end

---------------------------------------------------------------------------
-- icon picker (spellbook icons first, then the client's macro icons; paged)
---------------------------------------------------------------------------

local PAGE, COLS = 48, 8
picker = CreateFrame("Frame", "ChordsIconPicker", f, "BackdropTemplate")
picker:SetSize(8 * 38 + 44, 6 * 38 + 110)
picker:SetPoint("TOPLEFT", f, "TOPRIGHT", -6, 0)
picker:SetBackdrop(BACKDROP)
picker:SetFrameStrata("DIALOG")
picker:Hide()
picker.page, picker.icons = 1, {}
local pTitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pTitle:SetPoint("TOP", 0, -18)
pTitle:SetText("Pick an icon")
local pPage = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pPage:SetPoint("BOTTOM", 0, 22)
local pBtns = {}

local function refreshPicker()
    local total = #picker.icons
    local pages = math.max(1, math.ceil(total / PAGE))
    picker.page = math.min(math.max(picker.page, 1), pages)
    pPage:SetText(("page %d / %d"):format(picker.page, pages))
    for i = 1, PAGE do
        local b = pBtns[i]
        if not b then
            b = CreateFrame("Button", nil, picker)
            b:SetSize(36, 36)
            b:SetPoint("TOPLEFT", 22 + ((i - 1) % COLS) * 38, -46 - math.floor((i - 1) / COLS) * 38)
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints()
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
            b:SetScript("OnClick", function(self)
                if locked() or not selected then return end
                ChordsDB.groups[selected].icon = self.icon
                local idx = GetMacroIndexByName(selected:sub(1, 16))
                if idx and idx > 0 then Chords.SyncMacro(selected, false) end
                picker:Hide()
                E:Refresh()
            end)
            pBtns[i] = b
        end
        local icon = picker.icons[(picker.page - 1) * PAGE + i]
        if icon then b.icon = icon; b.tex:SetTexture(icon); b:Show() else b:Hide() end
    end
end

local prev = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
prev:SetSize(60, 22); prev:SetPoint("BOTTOMLEFT", 24, 18); prev:SetText("Prev")
prev:SetScript("OnClick", function() picker.page = picker.page - 1 refreshPicker() end)
local nxt = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
nxt:SetSize(60, 22); nxt:SetPoint("BOTTOMRIGHT", -24, 18); nxt:SetText("Next")
nxt:SetScript("OnClick", function() picker.page = picker.page + 1 refreshPicker() end)

function E:OpenIconPicker()
    if not selected then return end
    self:ScanSpells()
    browser:Hide()
    local icons, seen = {}, {}
    for _, sp in ipairs(self.spells) do
        if sp.icon and not seen[sp.icon] then seen[sp.icon] = true; icons[#icons + 1] = sp.icon end
    end
    for _, getter in ipairs({ GetMacroIcons, GetMacroItemIcons }) do
        local t = {}
        pcall(getter, t)
        for _, ic in ipairs(t) do
            if not seen[ic] then seen[ic] = true; icons[#icons + 1] = ic end
        end
    end
    picker.icons, picker.page = icons, 1
    refreshPicker()
    picker:Show()
end

---------------------------------------------------------------------------
-- header (selected group)
---------------------------------------------------------------------------

local noGroup = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
noGroup:SetPoint("CENTER", f, "CENTER", 80, 0)
noGroup:SetText("Create or select a group on the left")

local iconBtn = CreateFrame("Button", nil, f)
iconBtn:SetSize(40, 40)
iconBtn:SetPoint("TOPLEFT", 204, -42)
iconBtn.tex = iconBtn:CreateTexture(nil, "ARTWORK")
iconBtn.tex:SetAllPoints()
iconBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
iconBtn:SetScript("OnClick", function() E:OpenIconPicker() end)

local gName = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
gName:SetSize(150, 22)
gName:SetPoint("TOPLEFT", 256, -52)
gName:SetAutoFocus(false)
gName:SetMaxLetters(16)
local function renameFromBox(self)
    if selected and not locked() then
        if Chords.RenameGroup(selected, self:GetText()) then selected = Chords.normGroup(self:GetText()) end
    end
    E:Refresh()
end
gName:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
gName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
gName:SetScript("OnEditFocusLost", renameFromBox)

local nameHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
nameHint:SetPoint("LEFT", gName, "RIGHT", 8, 0)
nameHint:SetText("macro name")

local enterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
enterLabel:SetPoint("TOPLEFT", 200, -94)
enterLabel:SetText("Open with key:")

local enterBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
enterBtn:SetSize(110, 24)
enterBtn:SetPoint("LEFT", enterLabel, "RIGHT", 8, 0)
enterBtn:SetScript("OnClick", function()
    if locked() then return end
    captureKey(enterBtn, function(key)
        ChordsDB.groups[selected].enter = key
        Chords:Rebuild()
    end)
end)

local enterClear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
enterClear:SetSize(26, 24)
enterClear:SetPoint("LEFT", enterBtn, "RIGHT", 2, 0)
enterClear:SetText("X")
enterClear:SetScript("OnClick", function()
    if locked() then return end
    ChordsDB.groups[selected].enter = nil
    Chords:Rebuild()
    E:Refresh()
end)

local macroBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
macroBtn:SetSize(110, 24)
macroBtn:SetPoint("LEFT", enterClear, "RIGHT", 10, 0)
macroBtn:SetText("Make macro")
macroBtn:SetScript("OnClick", function()
    if not selected or locked() then return end
    local ok, err = Chords.SyncMacro(selected, true)
    if ok then
        print("|cff66ccffChords|r: macro '" .. selected:sub(1, 16) .. "' is on your cursor, click an action bar slot to place it")
    else
        print("|cff66ccffChords|r: |cffff5555macro failed:|r " .. err)
    end
end)

local delGroup = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
delGroup:SetSize(100, 24)
delGroup:SetPoint("BOTTOMLEFT", 200, 22)
delGroup:SetText("Delete group")

StaticPopupDialogs["CHORDS_DELETE_GROUP"] = {
    text = "Delete chord group '%s'?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        if locked() then return end
        ChordsDB.groups[selected] = nil
        E.drafts[selected] = nil
        selected = nil
        Chords:Rebuild()
        E:Refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
delGroup:SetScript("OnClick", function()
    if selected then StaticPopup_Show("CHORDS_DELETE_GROUP", selected) end
end)

local addEntry = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
addEntry:SetSize(110, 24)
addEntry:SetPoint("BOTTOMRIGHT", -40, 22)
addEntry:SetText("Add entry")
addEntry:SetScript("OnClick", function()
    if locked() or not selected then return end
    E.drafts[selected] = E.drafts[selected] or {}
    table.insert(E.drafts[selected], { text = "" })
    E:Refresh()
end)

---------------------------------------------------------------------------
-- group list (left)
---------------------------------------------------------------------------

local newName = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
newName:SetSize(110, 22)
newName:SetPoint("BOTTOMLEFT", 26, 24)
newName:SetAutoFocus(false)

local function createGroup()
    if locked() then return end
    local g = Chords.normGroup(newName:GetText())
    if g == "" then return end
    ChordsDB.groups[g] = ChordsDB.groups[g] or { entries = {} }
    selected = g
    newName:SetText("")
    newName:ClearFocus()
    Chords:Rebuild()
    E:Refresh()
end
newName:SetScript("OnEnterPressed", createGroup)
newName:SetScript("OnEscapePressed", newName.ClearFocus)

local newBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
newBtn:SetSize(26, 24)
newBtn:SetPoint("LEFT", newName, "RIGHT", 4, 0)
newBtn:SetText("+")
newBtn:SetScript("OnClick", createGroup)

local glabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
glabel:SetPoint("TOPLEFT", 26, -48)
glabel:SetText("Groups")

---------------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------------

function E:Refresh()
    -- group list
    local names = {}
    for g in pairs(ChordsDB.groups) do names[#names + 1] = g end
    table.sort(names)
    if selected and not ChordsDB.groups[selected] then selected = nil end
    if not selected then selected = names[1] end
    for i, g in ipairs(names) do
        local b = groupBtns[i]
        if not b then
            b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(150, 22)
            b:SetPoint("TOPLEFT", 22, -72 - (i - 1) * 24)
            b:SetScript("OnClick", function(self)
                selected = self.group
                dd:Hide()
                E:Refresh()
            end)
            groupBtns[i] = b
        end
        b.group = g
        local enter = ChordsDB.groups[g].enter
        b:SetText(enter and (g .. "  [" .. enter .. "]") or g)
        if g == selected then b:LockHighlight() else b:UnlockHighlight() end
        b:Show()
    end
    for i = #names + 1, #groupBtns do groupBtns[i]:Hide() end

    -- header
    local grp = selected and ChordsDB.groups[selected]
    noGroup:SetShown(not grp)
    for _, w in ipairs({ iconBtn, gName, nameHint, enterLabel, enterBtn, enterClear, macroBtn, delGroup, addEntry, scroll }) do
        w:SetShown(grp ~= nil)
    end
    if not grp then
        for _, r in ipairs(rows) do r:Hide() end
        return
    end
    gName:SetText(selected)
    iconBtn.tex:SetTexture(grp.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    enterBtn:SetText(grp.enter or "(none)")

    -- entries
    local keys = {}
    for k in pairs(grp.entries) do keys[#keys + 1] = k end
    table.sort(keys)
    local n = 0
    local function row()
        n = n + 1
        rows[n] = rows[n] or makeRow(n)
        rows[n]:Show()
        return rows[n]
    end
    for _, k in ipairs(keys) do
        local r = row()
        local act = grp.entries[k]
        r.entryKey, r.draft = k, nil
        r.keyBtn:SetText(k)
        r.edit:SetText(act.spell or (act.item and ("item:" .. act.item))
            or (act.macro and ("macro:" .. act.macro)) or (act.group and ("group:" .. act.group)) or "")
        r.edit:SetCursorPosition(0)
        r.edit:SetTextColor(1, 1, 1)
        r.icon:SetTexture(actionIcon(act))
    end
    for _, d in ipairs(E.drafts[selected] or {}) do
        local r = row()
        r.entryKey, r.draft = nil, d
        r.keyBtn:SetText(d.key or "set key")
        r.edit:SetText(d.text or "")
        r.edit:SetTextColor(1, 1, 1)
        r.icon:SetTexture(nil)
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(n * ROW_H, 10))
end

f:SetScript("OnShow", function() E:ScanSpells() E:Refresh() end)
f:SetScript("OnHide", function() dd:Hide() browser:Hide() picker:Hide() end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function() f:Hide() end)

function Chords.ToggleEditor()
    if f:IsShown() then f:Hide() else f:Show() end
end
