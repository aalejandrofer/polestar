-- Atlas: a calm skin for Polestar's guide window, through the Skin API
-- (Polestar 0.3.7 and later, Skin API 2). Polestar's own look with:
--   * the class accent softened toward grey, so a Paladin's pink reads as
--     a tint and not a highlighter;
--   * no section lines: one surface from the title to the progress.

local ADDON = ...
local Theme = Polestar and Polestar.Theme
if not (Theme and Theme.RegisterSkin and (Theme.API_VERSION or 0) >= 2) then return end
local kit = Theme.SkinKit

local function check(what, ok, message)
	if not ok then
		print(("|cffff8040%s|r: %s refused: %s"):format(ADDON, what, tostring(message)))
	elseif message then
		print(("%s: %s: %s"):format(ADDON, what, message))
	end
end

-- How far the class colour moves toward its own grey (0 keeps it, 1 is grey).
local MUTE = 0.4
local function mute(c)
	local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
	if not (r and g and b) then return nil end
	local l = 0.299 * r + 0.587 * g + 0.114 * b
	return { r + (l - r) * MUTE, g + (l - g) * MUTE, b + (l - b) * MUTE }
end

local CLEAR = { 0, 0, 0, 0 }

-- The card on top of the window: the parts Atlas takes out of the window
-- (guidePlace: While you're here) sit there, on the window's own ground and
-- joined to its top edge, and the heads-up card sits on it (guideAnchor).
-- The frame is Atlas's own, kept in the window's store, so another skin
-- hides it; the parts go back into the window by themselves then.
local TAKE = { here = true }
local taken = {}
local function topCard(window)
	local own = kit.store(window)
	if not own.top then
		local top = CreateFrame("Frame", nil, window)
		top:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 0, 0)
		top:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", 0, 0)
		top:SetHeight(1)
		top.psGuide = true
		Theme.Skin(top, "guide")
		own.top = top
	end
	return own.top
end

-- The window's own ground on the card, transparent with it.
local function dressTop(top, window)
	if top.psBare ~= window.psBare or top.psBgAlpha ~= window.psBgAlpha or top.psBgColor ~= window.psBgColor then
		top.psBare, top.psBgAlpha, top.psBgColor = window.psBare, window.psBgAlpha, window.psBgColor
		Theme.Repaint(top)
	end
end

-- Lay the parts taken at this layout under each other on the card.
local TOP_PAD = 2
local function layoutTop(parts)
	local window = parts.window
	if not window then return end
	local top = topCard(window)
	local y = TOP_PAD
	for i = 1, #taken do
		local f = taken[i]
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", top, "TOPLEFT", 0, -y)
		f:SetPoint("TOPRIGHT", top, "TOPRIGHT", 0, -y)
		y = y + (f:GetHeight() or 0)
		taken[i] = nil
	end
	if y > TOP_PAD then
		dressTop(top, window)
		top:SetHeight(y + TOP_PAD)
		top:Show()
	else
		top:Hide()
	end
end

-- While you're here on the card: the window's ground, not a tinted slab.
-- Its panel and edge are Polestar's own textures (an API gap: no hook
-- hands the panel's parts over), hidden while Atlas holds the part.
local function takeHere(frame, top)
	local body = frame.Body or frame
	for _, t in ipairs({ frame.Panel, frame.Edge }) do
		if t and t.SetAlpha then t:SetAlpha(0) end
	end
	kit.store(frame).quiet = true
	return body
end

-- The variant in use ("calm" before the player picks one).
local function variant()
	return Theme.SkinVariant and Theme.SkinVariant("atlas") or "calm"
end

-- Ledger: what a goal row would tell in a second column, on its right:
-- the quest's level on an accept or a hand-in, the distance on the arrow's
-- row. The row's count stays in its line (Polestar writes it there).
local DIST = { round = 5 }
local function ledgerRow(row, goal, info)
	local own = kit.store(row)
	if not own.meta then
		own.meta = row:CreateFontString(nil, "OVERLAY")
		Theme.Font(own.meta, "small")
		own.meta:SetJustifyH("RIGHT")
	end
	local meta = own.meta
	if variant() ~= "ledger" or info.done or info.skipped then
		meta:Hide()
		return
	end
	local text
	if info.current then
		local N = Polestar.Nav
		local d = N and N.GetDistance and N.GetDistance()
		if type(d) == "number" then text = Polestar.FormatDistance(d, DIST) end
	end
	if not text and (goal.t == "accept" or goal.t == "turnin") and goal.quest then
		local Lv, E = Polestar.Levels, Polestar.Engine
		local lvl = Lv and Lv.QuestLevel and Lv.QuestLevel(goal.quest, E and E.GetGuide and E.GetGuide() or nil)
		if type(lvl) == "number" and lvl > 0 then text = "[" .. lvl .. "]" end
	end
	if not text then
		meta:Hide()
		return
	end
	meta:ClearAllPoints()
	meta:SetPoint("TOPRIGHT", row, "TOPRIGHT", -34, -6)
	meta:SetText(text)
	meta:SetTextColor(Theme.Color(info.current and "textDim" or "textMuted"))
	meta:Show()
end

-- The variants that keep their own accent, not the softened class colour.
local OWN_ACCENT = { tooltip = true, brass = true, j = true, j2 = true }
-- The variants whose class card takes that accent (J keeps the class colour there).
local CARD_ACCENT = { tooltip = true, brass = true }

---------------------------------------------------------------------------
-- J: the saved layout (data/local mockups, guide-layouts preset J). One bar
-- that fills as the guide's progress, no tabs and no foot bar (its preset),
-- the person underlined, no accent bars, the goal the arrow is on in bold
-- with its count in gold, the quest and its level under each objective,
-- Up next on a rail that fades ahead. Its compact mode is Polestar's own
-- (compact drops Up next, the XP row and the tabs).
---------------------------------------------------------------------------

local function isJ()
	local v = variant()
	return v == "j" or v == "j2"
end

---------------------------------------------------------------------------
-- J2: the second saved layout (guide-layouts presets J2 and J2c). J with the
-- step's tip under the goal the arrow is on, the Journey on a card joined
-- below the window (never in the rail) and collapsed until opened (its
-- preset), the class quest's full heads-up above the window in every mode
-- (Polestar's own) and the training reminder as a card there too, with a
-- close. Out of compact the rail starts at the current step and connects to
-- Up next. Done goals stay in place and counts sit in a column. Its
-- compact mode (J2c) is Polestar's own, with the tip kept as the strip at the
-- card's foot.
---------------------------------------------------------------------------

local function isJ2() return variant() == "j2" end
local function compact() return Polestar.Get and Polestar.Get("ui.compact") and true or false end

-- Shared type for the headers of Atlas's stacked cards.
local function capsLabel(fs)
	Theme.Font(fs, "small")
	local path, size, flags = fs:GetFont()
	if path and size then fs:SetFont(path, size - 1, flags) end
	fs:SetTextColor(Theme.Color("textMuted"))
end

local OPT_ROW, OPT_PAD = 23, 14
local optStep, optGoals, optNotes, optSig = nil, {}, {}, nil

local function takesOut(goal)
	return isJ2() and (goal.optional or goal.t == "note") and true or false
end

local function optCard(top)
	local own = kit.store(top)
	if own.opt then return own.opt end
	local L = Polestar.L or {}
	local c = CreateFrame("Frame", nil, top)
	c.Label = c:CreateFontString(nil, "OVERLAY")
	c.Label:SetText(string.upper(L["Optional"] or "Optional"))
	c.Rows, c.Notes = {}, {}
	own.opt = c
	return c
end

local function updateOptionalMeta(r)
	local goal = r.psGoal
	local C, Nav, UI = Polestar.Compat, Polestar.Nav, Polestar.UI
	local target = Nav and Nav.GetTarget and Nav.GetTarget()
	local active = not goal.previewOnly and not goal.dismissed and goal.status ~= "done" and goal.status ~= "skipped"
	local aimed = active and target and ((target.stepIndex == optStep and target.goalIndex == goal.index)
		or (r.psPoint == target))
	r.Mark:SetShown(aimed and true or false)
	local yards
	if active and C and goal.map and goal.x and goal.y then
		if aimed and Nav.GetDistance then yards = Nav.GetDistance() end
		if not yards then
			local gc, gx, gy = C.MapToWorld(goal.map, goal.x, goal.y, goal.f)
			local pc, px, py = C.GetPlayerWorldPosition()
			if gc and gc == pc then yards = math.sqrt((gx - px)^2 + (gy - py)^2) end
		end
	end
	local count = UI.GoalProgress(goal)
	local dist = yards and Polestar.FormatDistance(yards, UI.GuideFrame.HERE_DIST)
	local meta = count and dist and (count .. "  ·  " .. dist) or count or dist
	r.Meta:SetText(meta or "")
	r.Meta:SetShown(meta ~= nil)
	local right = r.psMetaRight + (meta and math.ceil(r.Meta:GetUnboundedStringWidth()) + 6 or 0)
	r.Text:SetWidth(math.max(40, r.psWidth - (OPT_PAD + 12 + 6) - right - 2))
end

local function optRow(c, i)
	local r = c.Rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, c)
	r.Mark = r:CreateTexture(nil, "ARTWORK")
	r.Mark:SetTexture(Theme.Media("white"))
	r.Mark:SetWidth(2)
	r.Mark:SetPoint("TOPLEFT", r, "TOPLEFT", OPT_PAD - 5, -2)
	r.Mark:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", OPT_PAD - 5, 2)
	r.Mark:SetVertexColor(Theme.Accent())
	r.Mark:Hide()
	r:SetScript("OnClick", function(self)
		local goal, GF = self.psGoal, Polestar.UI.GuideFrame
		if not goal or goal.previewOnly or goal.dismissed or goal.status == "done" or goal.status == "skipped" then return end
		if not GF.AimGoal(goal) and goal.map and goal.x and goal.y then
			GF.PointAt(goal, goal.text)
			local Nav = Polestar.Nav
			self.psPoint = Nav and Nav.GetTarget and Nav.GetTarget()
		end
		updateOptionalMeta(self)
	end)
	r:SetScript("OnUpdate", function(self, elapsed)
		self.psElapsed = (self.psElapsed or 0) + elapsed
		if self.psElapsed < 0.25 then return end
		self.psElapsed = 0
		updateOptionalMeta(self)
	end)
	r.Icon = r:CreateTexture(nil, "ARTWORK")
	r.Icon:SetSize(12, 12)
	r.Icon:SetPoint("LEFT", r, "LEFT", OPT_PAD, 0)
	r.Text = r:CreateFontString(nil, "OVERLAY")
	Theme.Font(r.Text, "small")
	r.Text:SetJustifyH("LEFT")
	r.Text:SetWordWrap(false)
	r.Meta = r:CreateFontString(nil, "OVERLAY")
	Theme.Font(r.Meta, "small")
	r.Meta:SetJustifyH("RIGHT")
	r.Skip = CreateFrame("Button", nil, r)
	r.Skip.Label = r.Skip:CreateFontString(nil, "OVERLAY")
	Theme.Font(r.Skip.Label, "small")
	r.Skip.Label:SetPoint("CENTER", r.Skip, "CENTER", 0, 0)
	r.Skip:SetScript("OnClick", function()
		local E = Polestar.Engine
		local goal = r.psGoal
		if E and E.SkipGoal and goal and optStep then E.SkipGoal(optStep, goal.index) end
	end)
	r.Skip:SetScript("OnEnter", function(b) b.Label:SetTextColor(Theme.Color("text")) end)
	r.Skip:SetScript("OnLeave", function(b) b.Label:SetTextColor(Theme.Color("textDim")) end)
	c.Rows[i] = r
	return r
end

-- Fill from the step on screen (guideRender); the layout comes with layoutStack.
local function fillOptional(view)
	optGoals, optNotes, optStep = {}, {}, view and view.index or nil
	local sig = {}
	if view and isJ2() then
		for _, goal in ipairs(view.goals or {}) do
			if goal.status ~= "na" and not goal.folded then
				if goal.t == "note" then
					optNotes[#optNotes + 1] = goal
				elseif goal.optional then
					optGoals[#optGoals + 1] = goal
				else
					goal = nil
				end
				if goal then sig[#sig + 1] = goal.index .. (goal.status or "") .. (goal.dismissed and "d" or "") end
			end
		end
	end
	-- The render comes after the layout: lay out again when the card's content changed.
	local now = (optStep or 0) .. ":" .. table.concat(sig, ",")
	if now ~= optSig then
		optSig = now
		local GF = Polestar.UI and Polestar.UI.GuideFrame
		if GF and GF.Layout then GF.Layout() end
	end
end

local function layoutOptional(stack, window)
	local c = optCard(stack)
	local UI, E = Polestar.UI, Polestar.Engine
	local n, m = #optGoals, #optNotes
	if n + m == 0 or not isJ2() then
		c:Hide()
		return nil
	end
	local width = window:GetWidth() or 0
	local lh = 9
	for i = 1, m do
		local fs = c.Notes[i]
		if not fs then
			fs = c:CreateFontString(nil, "OVERLAY")
			Theme.Font(fs, "label")
			fs:SetJustifyH("LEFT")
			fs:SetJustifyV("TOP")
			fs:SetWordWrap(true)
			c.Notes[i] = fs
		end
		fs:SetTextColor(Theme.Color("quest"))
		fs:SetText(UI.GoalText(optNotes[i]))
		fs:SetWidth(math.max(40, width - OPT_PAD * 2))
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", c, "TOPLEFT", OPT_PAD, -lh)
		fs:Show()
		lh = lh + math.floor(fs:GetStringHeight() + 0.5) + 3
	end
	for i = m + 1, #c.Notes do c.Notes[i]:Hide() end
	c.Label:ClearAllPoints()
	c.Label:SetPoint("TOPLEFT", c, "TOPLEFT", OPT_PAD, -lh)
	capsLabel(c.Label)
	c.Label:SetShown(n > 0)
	if n > 0 then lh = lh + math.ceil(c.Label:GetStringHeight()) + 3 end
	for i = 1, n do
		local goal = optGoals[i]
		local r = optRow(c, i)
		local done, dismissed = goal.status == "done", goal.dismissed
		if not r.psGoal or r.psGoal.index ~= goal.index or r.psStep ~= optStep then r.psPoint = nil end
		r.psGoal, r.psStep = goal, optStep
		r.Mark:SetVertexColor(Theme.Accent())
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -lh)
		r:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -lh)
		r:SetHeight(OPT_ROW)
		r.Icon:SetTexture(done and Theme.Media("check") or (dismissed and Theme.Media("skip")) or Theme.VerbIcon(goal.t))
		r.Icon:SetVertexColor(Theme.Color(done and "success" or "textDim"))
		r.Text:SetText((done or dismissed) and UI.PlainGoalText(goal) or UI.GoalText(goal))
		r.Text:SetTextColor(Theme.Color((done or dismissed) and "textMuted" or "text"))
		r.Meta:SetTextColor(Theme.Color("textMuted"))
		local right = OPT_PAD
		local L = Polestar.L or {}
		r.Skip.Label:SetText(dismissed and (L["Undo"] or "Undo") or (L["Skip"] or "Skip"))
		r.Skip.Label:SetTextColor(Theme.Color("textDim"))
		local canSkip = not done and not goal.previewOnly and E and E.SkipGoal ~= nil
		r.Skip:SetShown(canSkip and true or false)
		if canSkip then
			r.Skip:SetSize(math.floor(r.Skip.Label:GetStringWidth() + 8 + 0.5), 14)
			r.Skip:ClearAllPoints()
			r.Skip:SetPoint("RIGHT", r, "RIGHT", -right, 0)
			right = right + r.Skip:GetWidth() + 6
		end
		r.Meta:ClearAllPoints()
		r.Meta:SetPoint("RIGHT", r, "RIGHT", -right, 0)
		r.Text:ClearAllPoints()
		r.Text:SetPoint("LEFT", r.Icon, "RIGHT", 6, 0)
		r.psMetaRight, r.psWidth = right, width
		updateOptionalMeta(r)
		r:Show()
		lh = lh + OPT_ROW
	end
	for i = n + 1, #c.Rows do c.Rows[i]:Hide() end
	lh = lh + 6
	c:SetHeight(lh)
	return c
end


-- The card under the window: the Journey, joined to the window's foot.
local below = {}
local function bottomCard(window)
	local own = kit.store(window)
	if not own.bottom then
		local b = CreateFrame("Frame", nil, window)
		b:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 0, 0)
		b:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, 0)
		b:SetHeight(1)
		b.psGuide = true
		Theme.Skin(b, "guide")
		own.bottom = b
	end
	return own.bottom
end

local function layoutBottom(parts)
	local window = parts.window
	if not window then return end
	local own = kit.store(window)
	if #below == 0 and not own.bottom then return end
	local b = bottomCard(window)
	local y = 0
	for i = 1, #below do
		local f = below[i]
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -y)
		f:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -y)
		y = y + (f:GetHeight() or 0)
		below[i] = nil
	end
	if y > 0 then
		dressTop(b, window)
		b:SetHeight(y + TOP_PAD)
		b:Show()
	else
		b:Hide()
	end
end

local function questLevel(quest)
	local Lv, E = Polestar.Levels, Polestar.Engine
	local lvl = quest and Lv and Lv.QuestLevel and Lv.QuestLevel(quest, E and E.GetGuide and E.GetGuide() or nil)
	if type(lvl) == "number" and lvl > 0 then return lvl end
end

-- The semibold face at the goal's size: Theme.Font's "number" role, read off
-- a probe once.
local boldPath
local function semibold()
	if not boldPath then
		local probe = UIParent:CreateFontString(nil, "OVERLAY")
		Theme.Font(probe, "number")
		boldPath = probe:GetFont()
		probe:Hide()
	end
	return boldPath
end

local function plainText(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function jRow(row, goal, info)
	local own = kit.store(row)
	if own.boldFrom then
		row.Text:SetFont(own.boldFrom[1], own.boldFrom[2], own.boldFrom[3])
		own.boldFrom = nil
	end
	if own.level then own.level:Hide() end
	row.psLevelWidth = nil
	if own.singleLine then
		row.Text:SetWordWrap(true)
		row.Text:SetMaxLines(2)
		own.singleLine = nil
	end
	if not isJ() then
		if row.Mark then row.Mark:SetAlpha(1) end
		return
	end
	local text = row.Text:GetText() or ""
	local live = info.current and not info.done and not info.skipped
	if isJ2() then
		own.singleLine = true
		row.Text:SetWordWrap(false)
		row.Text:SetMaxLines(1)
	end
	if live or isJ2() then
		local path, size, flags = row.Text:GetFont()
		if path and size then
			own.boldFrom = { path, size, flags }
			row.Text:SetFont((live and semibold()) or path, isJ2() and math.max(8, size - 2) or size, flags)
		end
		if live and goal.progress then
			text = text:gsub("|c%x%x%x%x%x%x%x%x(%d+/%d+)|r", "|c" .. Theme.Hex("accent") .. "%1|r")
		end
	end
	local muted = Theme.Hex("textMuted")
	if info.skipped or not goal.quest then
		row.Text:SetText(text)
		return
	end
	local lvl = questLevel(goal.quest)
	if goal.t == "accept" or goal.t == "turnin" then
		-- The line names the quest already: its level after it.
		if lvl and isJ2() then
			if not own.level then own.level = row:CreateFontString(nil, "OVERLAY") end
			local label = own.level
			Theme.Font(label, "small")
			label:SetTextColor(Theme.Color("textMuted"))
			label:SetText("[" .. lvl .. "]")
			label:ClearAllPoints()
			label:SetPoint("LEFT", row.Text, "RIGHT", 5, 0)
			label:Show()
			row.psLevelWidth = math.ceil(label:GetUnboundedStringWidth()) + 6
		elseif lvl then
			text = text .. "  |c" .. muted .. "[" .. lvl .. "]|r"
		end
		row.Text:SetText(text)
		return
	end
	row.Text:SetText(text)
	-- An objective: its quest and level on the line under it.
	local title = Polestar.UI and Polestar.UI.QuestTitle and Polestar.UI.QuestTitle(goal.quest)
	if not title then return end
	local sub = row.Sub:IsShown() and row.Sub:GetText() or nil
	if sub and plainText(sub):find(title, 1, true) then return end
	local line = title .. (lvl and ("  |c" .. muted .. "[" .. lvl .. "]|r") or "")
	row.Sub:SetText((sub and sub ~= "") and (line .. "\n" .. sub) or line)
	row.Sub:Show()
end

-- The bar fills as the guide's progress: a soft wash in the accent, a 2px
-- accent edge along its foot.
local function navFill()
	local parts = Theme.GuideParts()
	local nav = parts and parts.nav
	if not nav then return end
	local own = kit.store(nav)
	-- The transparent window has no bar to fill.
	if not isJ() or (parts.window and parts.window.psBare) then
		if own.fill then own.fill:Hide(); own.edge:Hide() end
		return
	end
	if not own.fill then
		own.fill = nav:CreateTexture(nil, "BACKGROUND", nil, 2)
		own.fill:SetTexture(Theme.Media("white"))
		own.edge = nav:CreateTexture(nil, "ARTWORK")
		own.edge:SetTexture(Theme.Media("white"))
	end
	-- The counter already accounts for the step in view and catch-up.
	local at, total = (nav.Steps.Count:GetText() or ""):match("^(%d+) / (%d+)$")
	at, total = tonumber(at), tonumber(total)
	local frac = total and total > 0 and at / total or 0
	local w = math.max(0.01, (nav:GetWidth() or 0) * math.min(1, math.max(0, frac or 0)))
	local r, g, b = Theme.Accent()
	own.fill:ClearAllPoints()
	own.fill:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
	own.fill:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 0, 0)
	own.fill:SetWidth(w)
	own.fill:SetVertexColor(r, g, b, 0.10)
	own.edge:ClearAllPoints()
	own.edge:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 0, 0)
	own.edge:SetSize(w, 2 * (Theme.Pixel and Theme.Pixel(nav) or 1))
	own.edge:SetVertexColor(r, g, b, 1)
	own.fill:Show()
	own.edge:Show()
end

-- Underline the person heading.
local function jPerson(parts)
	local person = parts.person
	if not person then return end
	local own = kit.store(person)
	if not isJ() then
		if own.under then own.under:Hide() end
		return
	end
	if not own.under then
		own.under = person:CreateTexture(nil, "ARTWORK")
		own.under:SetTexture(Theme.Media("white"))
	end
	local r, g, b = Theme.Color("textMuted")
	own.under:ClearAllPoints()
	own.under:SetPoint("BOTTOMLEFT", person, "BOTTOMLEFT", 12, 0)
	own.under:SetPoint("BOTTOMRIGHT", person, "BOTTOMRIGHT", -12, 0)
	own.under:SetHeight(Theme.Pixel and Theme.Pixel(person) or 1)
	own.under:SetVertexColor(r, g, b, 0.35)
	own.under:Show()
end

---------------------------------------------------------------------------
-- J2 on a timeline (guide-layouts preset J2): the step sits on a rail
-- that starts at the current step and connects to the next three (hollow
-- nodes, fainter ahead); the card is set in from the rail (guideInset); done goals
-- stay in place (guideShows "done"), the counts in a column on the right;
-- the bar holds the guide's emblem and title on the left, the step count
-- and the menu on the right (Skip is in the menu); While you're here and the training
-- reminder are cards above the window. Compact mode (J2c) keeps the cards
-- and the bar, not the rail (no Up next there).
---------------------------------------------------------------------------

local function tl() return isJ2() and not compact() end
local CARD_X, UP_X, RAIL = 22, 13, 15 -- the card's and Up next's insets, the rail's x (window)
local TITLE_PAD = 10
local TITLE_UP = 1 -- the step title over the goal lines, in px
local FADE = { 0.9, 0.65, 0.4 } -- the steps ahead, fainter further on

local function tr(s)
	local L = Polestar.L
	return (L and L[s]) or s
end

-- A role's face, size and flags, read off a probe of Atlas's own.
local probeFs
local function probe(role)
	if not probeFs then
		probeFs = UIParent:CreateFontString(nil, "OVERLAY")
		probeFs:Hide()
	end
	Theme.Font(probeFs, role)
	local path, size, flags = probeFs:GetFont()
	return path, size or 12, flags
end

-- A step's line on the rail: its first goal that is not a walk ("Hand in A
-- New Threat", the quest in its colour), and the zone it is in.
local function stepLine(v)
	local UI = Polestar.UI
	local first, place
	for _, g in ipairs(v.goals or {}) do
		if g.status ~= "na" then
			if not place and g.map and UI.MapName then place = UI.MapName(g.map) end
			if not first and g.t ~= "goto" then first = g end
		end
	end
	first = first or (v.goals and v.goals[1])
	local text = first and UI.GoalText and UI.GoalText(first) or (UI.StepSummary and UI.StepSummary(v)) or ""
	return text, place, first and first.t or "note"
end

-- A node: a disc, with a ring of the ground round it (the current one) or a
-- hollow middle (the steps ahead).
local function node(own, key, parent)
	local n = own[key]
	if n then return n end
	n = {}
	for _, part in ipairs({ "ring", "disc", "hole" }) do
		local t = parent:CreateTexture(nil, "OVERLAY", nil, part == "ring" and 1 or part == "disc" and 2 or 3)
		t:SetTexture(Theme.Media("circle"))
		n[part] = t
	end
	own[key] = n
	return n
end

local function paintNode(n, kind, alpha)
	local bg = { Theme.Color("bg") }
	local size = kind == "cur" and 10 or 8
	n.ring:SetSize(size + 6, size + 6)
	n.ring:SetVertexColor(bg[1], bg[2], bg[3], kind == "cur" and 1 or 0)
	n.disc:SetSize(size, size)
	n.hole:SetSize(size - 2, size - 2)
	if kind == "cur" then
		local r, g, b = Theme.Accent()
		n.disc:SetVertexColor(r, g, b, 1)
		n.hole:SetVertexColor(0, 0, 0, 0)
	else
		n.disc:SetVertexColor(1, 1, 1, 0.42 * alpha)
		n.hole:SetVertexColor(bg[1], bg[2], bg[3], 1)
	end
end

local function placeNode(n, rel, point, x, y)
	for _, part in ipairs({ "ring", "disc", "hole" }) do
		local t = n[part]
		t:ClearAllPoints()
		t:SetPoint("CENTER", rel, point, x, y)
		t:Show()
	end
end

local function hideNode(n)
	if n then n.ring:Hide(); n.disc:Hide(); n.hole:Hide() end
end

-- The rail and its nodes, on a layer of Atlas's own over the window.
local function rail(parts)
	local window, person, upnext = parts.window, parts.person, parts.upnext
	if not window then return end
	local own = kit.store(window)
	if not own.tl then
		own.tl = CreateFrame("Frame", nil, window)
		own.tl:SetAllPoints(window)
		own.tl.dots = {}
	end
	local layer = own.tl
	layer:SetFrameLevel(window:GetFrameLevel() + 8)
	local onStep = tl() and person and person:IsShown() and person:GetParent() and person:GetParent():IsShown()
	if not onStep then
		layer:Hide()
		return
	end
	layer:Show()
	local cn = node(layer, "cur", layer)
	paintNode(cn, "cur", 1)
	local nameY = -(TITLE_PAD + person.Name:GetStringHeight() / 2)
	placeNode(cn, person, "TOPLEFT", RAIL - CARD_X, nameY)
	local top, bottom = cn.disc, cn.disc
	local rows = {}
	if upnext and upnext:IsShown() then
		for _, r in ipairs({ upnext:GetChildren() }) do
			if type(r.Num) == "table" and r.psIndex and r:IsShown() then rows[#rows + 1] = r end
		end
		table.sort(rows, function(a, b) return a.psIndex < b.psIndex end)
	end
	for i = 1, math.max(#rows, #layer.dots) do
		local d = node(layer.dots, i, layer)
		local r = rows[i]
		if r then
			local a = FADE[i] or FADE[#FADE]
			paintNode(d, "next", a)
			placeNode(d, r, "TOPLEFT", RAIL - UP_X, -12)
			bottom = d.disc
		else
			hideNode(d)
		end
	end
	if not layer.line then
		layer.line = layer:CreateTexture(nil, "ARTWORK")
		layer.line:SetTexture(Theme.Media("white"))
		layer.line:SetWidth(1)
	end
	layer.line:ClearAllPoints()
	layer.line:SetPoint("TOP", top, "CENTER", 0, 0)
	layer.line:SetPoint("BOTTOM", bottom, "CENTER", 0, 0)
	layer.line:SetVertexColor(1, 1, 1, 0.2)
	layer.line:SetShown(top ~= bottom)
end

-- An Up next row on the rail: its first goal on one line, its zone on the
-- right, fainter ahead (guideUpRow; Polestar sets the row again at every
-- fill, so another look gets its own back).
local function upRow(row, v, index)
	local own = kit.store(row)
	-- On the rail Up next has no heading to open it by: its rows always show.
	if tl() then row:Show() end
	if not tl() then
		row.Text:SetMaxLines(2)
		if own.zone then own.zone:Hide() end
		return
	end
	local text, place = stepLine(v)
	row.Text:SetText(text)
	row.Text:SetTextColor(Theme.Color("textDim"))
	row.Text:SetMaxLines(1)
	if not own.zone then
		own.zone = row:CreateFontString(nil, "OVERLAY")
		Theme.Font(own.zone, "label")
		own.zone:SetJustifyH("RIGHT")
		own.zone:SetWordWrap(false)
	end
	own.zone:SetText(place or "")
	own.zone:SetTextColor(Theme.Color("textMuted"))
	own.zone:ClearAllPoints()
	own.zone:SetPoint("RIGHT", row, "TOPRIGHT", -14, -12)
	own.zone:SetShown(place ~= nil)
	row:Show()
end

-- After the rows are laid out: each text stops short of its zone.
local function upFit(frame)
	if not tl() then return end
	local i = 0
	local rows = {}
	for _, r in ipairs({ frame:GetChildren() }) do
		if type(r.Num) == "table" and r.psIndex and r:IsShown() then rows[#rows + 1] = r end
	end
	table.sort(rows, function(a, b) return a.psIndex < b.psIndex end)
	for _, r in ipairs(rows) do
		i = i + 1
		r:SetAlpha(FADE[i] or FADE[#FADE])
		local zone = kit.store(r).zone
		local zw = (zone and zone:IsShown()) and math.min(zone:GetStringWidth() + 1, 110) or 0
		if zone then zone:SetWidth(zw) end
		local left = 59 -- Polestar's text column in the row (TEXT_X - 2 + 13 + 9)
		r.Text:SetWidth(math.max(40, (r:GetWidth() or 300) - left - 14 - (zw > 0 and zw + 8 or 0)))
	end
end

-- Goal rows: the count in a column on the right. The tick stays laid out
-- (its room keeps the column clear) but unseen and off; Polestar paints it
-- again at every fill.
local COUNT = "|c%x%x%x%x%x%x%x%x(%d+/%d+)|r"
local function countColumn(row, goal, info)
	local own = kit.store(row)
	if own.count then own.count:Hide() end
	if not isJ2() then return end
	if row.Check:IsShown() then
		row.Check:SetAlpha(0)
		row.Check:Disable()
	end
	local text = row.Text:GetText() or ""
	local count = text:match(COUNT) or text:match("%s(%d+/%d+)%s*$")
	if not count then return end
	text = text:gsub("%s*" .. COUNT, "", 1)
	if text == row.Text:GetText() then text = text:gsub("%s+%d+/%d+%s*$", "", 1) end
	row.Text:SetText(text)
	if not own.count then
		own.count = row:CreateFontString(nil, "OVERLAY")
		own.count:SetJustifyH("RIGHT")
	end
	local path, size, flags = row.Text:GetFont()
	own.count:SetFont(path, size, flags)
	own.count:SetText(count)
	local live = info.current and not info.done and not info.skipped
	if live then
		own.count:SetTextColor(Theme.Accent())
	else
		own.count:SetTextColor(Theme.Color(info.done and "textMuted" or "textDim"))
	end
	own.count:ClearAllPoints()
	own.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -4)
	own.count:Show()
end

-- After the rows are laid out: "Other" (the next spot) in the count's
-- column, on the line under the count; the row's text stops short of both.
local function altBeside(parts)
	if not isJ2() then return end
	for _, row in ipairs(parts.rows or {}) do
		local count = kit.store(row).count
		local alt = row.Alt
		if row:IsShown() and alt and alt:IsShown() then
			-- Align the glyph's visible edge with the count, allowing for its click area.
			local inset = (alt:GetWidth() - alt.Icon:GetWidth()) / 2
			alt:ClearAllPoints()
			if count and count:IsShown() then
				alt:SetPoint("TOPRIGHT", count, "BOTTOMRIGHT", inset, -1)
			else
				alt:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14 + inset, -2)
			end
		end
	end
end

-- J2: the class guide on offer is the heads-up card above the window (×,
-- Later), not a banner in it. Shown once per notice; its buttons are the
-- banner's own (open the guide in a tab, Later).
local cqShown
local function classHeadsUp(n)
	local UI = Polestar.UI
	local CT, GF = UI and UI.ClassToast, UI and UI.GuideFrame
	if not (CT and CT.ShowCard and GF) then return false end
	if cqShown == n then return true end
	cqShown = n
	CT.ShowCard({
		head = string.upper(tr("Class quest")),
		title = n.title or "",
		giver = n.heads, route = n.why,
		icon = Theme.Media("icon-train"), iconColor = "accent",
		act = { label = tr("Open in a tab"), run = function() GF.TakeBanner(); CT.Hide() end },
		later = { label = tr("Later"), run = function() GF.LaterBanner() end },
	})
	return true
end

-- The bar: the guide's emblem and title on the left; the step count and
-- the menu on the right; no Skip, Report, Nearby or Lookup there (the menu
-- has them).
local function navBack(nav)
	local own = nav and kit.store(nav)
	if not (own and own.j2) then return end
	own.j2 = nil
	if own.emblem then own.emblem:Hide() end
	Theme.Font(nav.Steps.Count, "number")
	nav.Steps:ClearAllPoints()
	nav.Steps:SetPoint("LEFT", nav, "LEFT", 8, 0)
	nav.Skip.Label:Show()
	nav.Skip:SetWidth(math.floor(7 + 11 + 5 + nav.Skip.Label:GetStringWidth() + 8 + 0.5))
	nav.Lookup:Show()
	nav.Nearby:SetShown(Polestar.Get and Polestar.Get("nav.nearbyButton") ~= false)
	Theme.Font(nav.Title, "small")
end

local function navJ2(parts)
	local nav = parts.nav
	if not nav then return end
	if not isJ2() then
		navBack(nav)
		return
	end
	local own = kit.store(nav)
	own.j2 = true
	if not own.emblem then
		own.emblem = nav:CreateTexture(nil, "ARTWORK")
		own.emblem:SetTexture(Theme.Media("emblem"))
		own.emblem:SetSize(16, 16)
	end
	own.emblem:ClearAllPoints()
	own.emblem:SetPoint("LEFT", nav, "LEFT", 10, 0)
	own.emblem:Show()
	nav.Report:Hide()
	nav.Nearby:Hide()
	nav.Lookup:Hide()
	-- Skip lives in the menu only (it is there already): no button for it.
	nav.Skip:Hide()
	local path, size, flags = probe("note")
	nav.Steps.Count:SetFont(path, size + 2, flags)
	local cw = math.max(40, math.ceil(nav.Steps.Count:GetUnboundedStringWidth()) + 1)
	nav.Steps.Count:SetWidth(cw)
	nav.Steps:SetWidth(24 + cw + 24)
	nav.Steps:ClearAllPoints()
	nav.Steps:SetPoint("RIGHT", nav.Menu, "LEFT", -2, 0)
	Theme.Font(nav.Title, "goal")
	nav.Title:SetTextColor(Theme.Color("textDim"))
	nav.Title:ClearAllPoints()
	nav.Title:SetPoint("LEFT", own.emblem, "RIGHT", 8, 0)
	nav.Title:SetPoint("RIGHT", nav.Steps, "LEFT", -8, 0)
	nav.Title:SetJustifyH("LEFT")
	nav.Title:SetWordWrap(false)
	local text = nav.Title:GetText()
	nav.Title:SetShown(text ~= nil and text ~= "")
	if nav.Title.Hit then nav.Title.Hit:SetShown(nav.Title:IsShown()) end
end

-- The tip: an "i" and a line over it, its text on one line until opened.
local function tipJ2(tip, off)
	local own = kit.store(tip)
	if not own.rule then
		own.rule = tip:CreateTexture(nil, "ARTWORK")
		own.rule:SetTexture(Theme.Media("white"))
	end
	local on = not off and tl()
	own.rule:SetShown(on)
	if not on then return end
	tip.Toggle.Icon:SetTexture(Theme.Media("info"))
	own.rule:ClearAllPoints()
	own.rule:SetPoint("TOPLEFT", tip, "TOPLEFT", 11, 0)
	own.rule:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -12, 0)
	own.rule:SetHeight(Theme.Pixel and Theme.Pixel(tip) or 1)
	local r, g, b = Theme.Color("textMuted")
	own.rule:SetVertexColor(r, g, b, 0.35)
end

-- The XP row: "Level 4 · 62% · " before what Polestar says, a gold star.
local function xpJ2(xp, off)
	local on = not off and tl()
	local line = xp.psLine
	if not on then
		if kit.store(xp).j2 then
			kit.store(xp).j2 = nil
			if line then xp.Text:SetText(line) end
			xp.Icon:SetTexture(Theme.Media("icon-level"))
			xp.Icon:SetVertexColor(Theme.Color("textMuted"))
		end
		return
	end
	kit.store(xp).j2 = true
	local level = UnitLevel and UnitLevel("player")
	local cur, max = UnitXP and UnitXP("player"), UnitXPMax and UnitXPMax("player")
	local head = {}
	if type(level) == "number" and level > 0 then head[#head + 1] = string.format(tr("Level %d"), level) end
	if type(cur) == "number" and type(max) == "number" and max > 0 then head[#head + 1] = math.floor(cur / max * 100) .. "%" end
	if line then head[#head + 1] = line end
	xp.Text:SetText(table.concat(head, "  \194\183  "))
	xp.Icon:SetTexture(Theme.Media("star"))
	xp.Icon:SetVertexColor(Theme.Accent())
end

-- The cards above the window (J2): each part on a card of its own, the
-- window's ground and edge, a caps label, 5 apart.
local GAP = 5
local slots = {}

local function stackFrame(window)
	local own = kit.store(window)
	if not own.stack then
		own.stack = CreateFrame("Frame", nil, window)
		own.stack:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 0, GAP)
		own.stack:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", 0, GAP)
		own.stack:SetHeight(1)
		own.stack.cards = {}
	end
	return own.stack
end

local function backing(stack, i)
	local b = stack.cards[i]
	if not b then
		b = CreateFrame("Frame", nil, stack)
		b.psGuide = true
		Theme.Skin(b, "guide")
		b:SetFrameLevel(stack:GetFrameLevel())
		stack.cards[i] = b
	end
	return b
end

-- The training reminder as a card: "TRAINING DUE", the trainer line and the
-- place on its right, × as Later.
local function trainCard(stack)
	if stack.train then return stack.train end
	local f = CreateFrame("Button", nil, stack)
	f.Label = f:CreateFontString(nil, "OVERLAY")
	f.Icon = f:CreateTexture(nil, "ARTWORK")
	f.Icon:SetSize(15, 15)
	f.Text = f:CreateFontString(nil, "OVERLAY")
	f.Text:SetWordWrap(false)
	f.Text:SetJustifyH("LEFT")
	f.Place = f:CreateFontString(nil, "OVERLAY")
	f.Place:SetJustifyH("RIGHT")
	f.Place:SetWordWrap(false)
	f.Close = CreateFrame("Button", nil, f)
	f.Close:SetSize(18, 18)
	f.Close.Icon = f.Close:CreateTexture(nil, "ARTWORK")
	f.Close.Icon:SetTexture(Theme.Media("close"))
	f.Close.Icon:SetSize(10, 10)
	f.Close.Icon:SetPoint("CENTER")
	f.Close:SetScript("OnClick", function()
		local GF = Polestar.UI and Polestar.UI.GuideFrame
		if GF and GF.LaterBanner then GF.LaterBanner() end
	end)
	f:SetScript("OnClick", function()
		local GF = Polestar.UI and Polestar.UI.GuideFrame
		if f.psTrainer and GF and GF.TakeBanner then GF.TakeBanner() end
	end)
	stack.train = f
	return f
end

-- J2: the class-quest card (UI/ClassCard.lua) is a card above the window,
-- with a × that puts its chain away for the session.
local classShut = {}
local function classClose(f, on)
	if not f.psAtlasX then
		local x = CreateFrame("Button", nil, f)
		x:SetSize(18, 18)
		x.Icon = x:CreateTexture(nil, "ARTWORK")
		x.Icon:SetTexture(Theme.Media("close"))
		x.Icon:SetSize(10, 10)
		x.Icon:SetPoint("CENTER")
		x:SetScript("OnClick", function()
			local CC = Polestar.UI and Polestar.UI.ClassCard
			local key = CC and CC.shown and CC.shown.key
			if key then classShut[key] = true end
			local GF = Polestar.UI and Polestar.UI.GuideFrame
			if GF and GF.Layout then GF.Layout() end
		end)
		f.psAtlasX = x
	end
	local x = f.psAtlasX
	x:SetShown(on and true or false)
	if not on then return end
	x.Icon:SetVertexColor(Theme.Color("textMuted"))
	x:ClearAllPoints()
	x:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
	x:SetFrameLevel(f:GetFrameLevel() + 5)
	-- The badge steps left of the ×.
	if f.Badge and f.Badge:IsShown() then
		f.Badge:ClearAllPoints()
		f.Badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", -26, -10)
	end
end

local function fillTrain(f, width)
	local E = Polestar.Engine
	local advice = E and E.TrainingAdvice and E.TrainingAdvice() or {}
	local trainer = not advice.guide and advice.trainer or nil
	local UI = Polestar.UI
	local place = (advice.title and advice.title ~= "" and advice.title)
		or (trainer and (trainer.npcName or (trainer.map and UI.MapName and UI.MapName(trainer.map)))) or nil
	f.psTrainer = trainer
	capsLabel(f.Label)
	f.Label:SetText(string.upper(tr("Training due")))
	f.Label:ClearAllPoints()
	f.Label:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -8)
	Theme.Font(f.Text, "small")
	f.Text:SetTextColor(Theme.Color("text"))
	f.Text:SetText(tr("New spells at your class trainer"))
	Theme.Font(f.Place, "small")
	f.Place:SetTextColor(Theme.Color("textMuted"))
	f.Place:SetText(place or "")
	f.Place:SetShown(place ~= nil)
	f.Icon:SetTexture(Theme.VerbIcon("talk"))
	f.Icon:SetVertexColor(Theme.Color("npc"))
	f.Close.Icon:SetVertexColor(Theme.Color("textMuted"))
	local rowY = -8 - f.Label:GetStringHeight() - 4
	f.Close:ClearAllPoints()
	f.Close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -4)
	f.Icon:ClearAllPoints()
	f.Icon:SetPoint("CENTER", f, "TOPLEFT", 14 + 7.5, rowY - 10)
	f.Place:ClearAllPoints()
	f.Place:SetPoint("RIGHT", f, "TOPRIGHT", -14, rowY - 10)
	f.Place:SetWidth(math.min(f.Place:GetStringWidth() + 1, 120))
	f.Text:ClearAllPoints()
	f.Text:SetPoint("LEFT", f, "TOPLEFT", 39, rowY - 10)
	f.Text:SetPoint("RIGHT", f.Place, "LEFT", -8, 0)
	local h = math.floor(8 + f.Label:GetStringHeight() + 4 + 20 + 6 + 0.5)
	f:SetSize(width, h)
	return f
end

local function layoutStack(parts)
	local window = parts.window
	if not window then return end
	local stack = stackFrame(window)
	local list = {}
	if slots.class then list[#list + 1] = slots.class end
	if slots.here then list[#list + 1] = slots.here end
	local optional = layoutOptional(stack, window)
	if optional then list[#list + 1] = optional end
	if slots.train then list[#list + 1] = slots.train end
	slots.class, slots.here, slots.train = nil, nil, nil
	local width = window:GetWidth() or 300
	local y = 0
	for i = #list, 1, -1 do
		local f = list[i]
		local h = f:GetHeight() or 0
		local b = backing(stack, i)
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", stack, "BOTTOMLEFT", 0, y)
		b:SetSize(width, h)
		dressTop(b, window)
		b:Show()
		f:SetParent(b)
		f:SetFrameLevel(b:GetFrameLevel() + 1)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		f:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
		f:Show()
		y = y + h + GAP
	end
	for i = #list + 1, #stack.cards do stack.cards[i]:Hide() end
	local trainIn = false
	for _, f in ipairs(list) do if f == stack.train then trainIn = true end end
	if stack.train and not trainIn then stack.train:Hide() end
	if #list > 0 then
		stack:SetHeight(y - GAP)
		stack:Show()
	else
		stack:Hide()
	end
end

-- While you're here's label in caps, as the other cards'.
local function hereLabel(here, on)
	if not here.Label then return end
	local own = kit.store(here)
	if on then
		own.label = own.label or here.Label:GetText()
		capsLabel(here.Label)
		here.Label:SetText(string.upper(own.label or ""))
	elseif own.label then
		Theme.Font(here.Label, "small")
		here.Label:SetText(own.label)
		here.Label:SetTextColor(Theme.Accent())
		own.label = nil
	end
end

-- J's step title as the mockup draws it: the name in the medium face at
-- 13, on one line; its zone at the right of the same row; no verb icon and
-- no level line. The core's own look comes back under another variant or
-- skin (headerBack).
local function headerBack(person)
	local own = person and kit.store(person)
	local was = own and own.header
	if not was then return end
	own.header = nil
	Theme.Font(person.Name, "name")
	person.Name:SetWordWrap(was.wrap)
	person.Name:ClearAllPoints()
	person.Name:SetPoint(unpack(was.name))
	person.Where:ClearAllPoints()
	person.Where:SetPoint(unpack(was.where))
	person.Where:SetJustifyH(was.justify)
	Theme.Font(person.Where, "small")
	person.Where:SetTextColor(Theme.Color("textDim"))
	if person.Icon then person.Icon:SetAlpha(1) end
end

local function jHeader(person, width, h)
	if not isJ() then
		headerBack(person)
		return nil
	end
	local own = kit.store(person)
	if not own.header then
		own.header = {
			wrap = person.Name:CanWordWrap(),
			name = { person.Name:GetPoint(1) },
			where = { person.Where:GetPoint(1) },
			justify = person.Where:GetJustifyH(),
		}
	end
	Theme.Font(person.Name, "label")
	local path, size, flags = person.Name:GetFont()
	if isJ2() then
		-- J2: the title two sizes over the goal lines, the zone at their size.
		local _, goalSize = probe("goal")
		person.Name:SetFont(semibold() or path, goalSize + TITLE_UP, flags)
		Theme.Font(person.Where, "goal")
		person.Where:SetTextColor(Theme.Color("textMuted"))
	else
		person.Name:SetFont(path, (size or 12) + 1, flags)
	end
	person.Name:SetWordWrap(false)
	if person.Icon then person.Icon:SetAlpha(0) end
	person.Level:Hide()
	local pad = tl() and 11 or 14
	local top = TITLE_PAD
	local whereW = 0
	if person.Where:IsShown() then
		whereW = math.min(person.Where:GetUnboundedStringWidth() + 1, math.floor(width * 0.45))
		person.Where:SetWidth(whereW)
		person.Where:SetJustifyH("RIGHT")
	end
	person.Name:ClearAllPoints()
	person.Name:SetPoint("TOPLEFT", person, "TOPLEFT", pad, -top)
	person.Name:SetWidth(width - (whereW > 0 and whereW + 10 or 0))
	-- The zone sits on the name's row: centred on it, at the right edge.
	if whereW > 0 then
		person.Where:ClearAllPoints()
		person.Where:SetPoint("TOP", person.Name, "TOP", 0, 0)
		person.Where:SetPoint("RIGHT", person, "RIGHT", -pad, 0)
		person.Where:SetPoint("BOTTOM", person.Name, "BOTTOM", 0, 0)
	end
	local nh = top + person.Name:GetStringHeight()
	if person.Why:IsShown() then
		person.Why:SetWidth(width)
		person.Why:ClearAllPoints()
		person.Why:SetPoint("TOPLEFT", person.Name, "BOTTOMLEFT", 0, -3)
		nh = nh + 3 + person.Why:GetStringHeight()
	end
	return nh + 8
end

-- Up next on a rail: a node at each step, the steps further ahead fainter.
local RAIL_X = 5
local function timeline(frame)
	local own = kit.store(frame)
	own.dots = own.dots or {}
	local rows = {}
	for _, r in ipairs({ frame:GetChildren() }) do
		if type(r.Num) == "table" and r.Num.GetPoint and r.psIndex and r:IsShown() then rows[#rows + 1] = r end
	end
	for _, d in ipairs(own.dots) do d:Hide() end
	if own.rail then own.rail:Hide() end
	-- J2 draws its rail over the whole window (rail, upFit).
	if not isJ() or isJ2() then
		for _, r in ipairs(rows) do r:SetAlpha(1) end
		return
	end
	local r, g, b = Theme.Color("textMuted")
	for i, row in ipairs(rows) do
		row:SetAlpha(FADE[i] or FADE[#FADE])
		local d = own.dots[i]
		if not d then
			d = frame:CreateTexture(nil, "OVERLAY")
			d:SetTexture(Theme.Media("white"))
			d:SetSize(5, 5)
			own.dots[i] = d
		end
		-- On the number's line (Polestar sets it at the row's TOPLEFT, half a row down).
		local _, _, _, _, ny = row.Num:GetPoint(1)
		own.y = type(ny) == "number" and ny or -9
		d:ClearAllPoints()
		d:SetPoint("CENTER", row, "TOPLEFT", RAIL_X, own.y)
		d:SetVertexColor(r, g, b, FADE[i] or FADE[#FADE])
		d:Show()
	end
	if #rows > 1 then
		if not own.rail then
			own.rail = frame:CreateTexture(nil, "ARTWORK")
			own.rail:SetTexture(Theme.Media("white"))
			own.rail:SetWidth(1)
		end
		own.rail:ClearAllPoints()
		own.rail:SetPoint("TOPLEFT", rows[1], "TOPLEFT", RAIL_X - 0.5, own.y)
		own.rail:SetPoint("BOTTOMLEFT", rows[#rows], "TOPLEFT", RAIL_X - 0.5, own.y)
		own.rail:SetVertexColor(r, g, b, 0.35)
		own.rail:Show()
	end
end

-- With the foot bar off, room under the window's last part.
local function jFootRoom()
	if not isJ() then return 0 end
	local get = Polestar.Get
	return (get and get("guideWindow.progress") == false) and 8 or 0
end

check("skin atlas", Theme.RegisterSkin("atlas", {
	api = 2,
	name = "Atlas",
	addon = ADDON,
	author = "TTik3r",
	version = "0.1",
	desc = "One calm surface: a softened class accent, no section lines, the next step numbered.",
	base = "polestar",
	tokens = {
		divider = CLEAR, separator = CLEAR, rowLine = CLEAR,
		-- The menu keeps its group lines: no section lines in the window only.
		menuLine = "#ffffff1f",
	},
	variants = {
		{ id = "calm", name = "Calm", desc = "One surface in your scheme, your class colour softened." },
		{ id = "ledger", name = "Ledger", desc = "Calm, with the quest's level and the distance on each goal's row." },
		{ id = "tooltip", name = "Tooltip", desc = "Near-black, a blue-grey edge and a gold title, as the game's tooltips.",
			tokens = {
				bg = "#07090f", panel = "#0b0e17", panelAlt = "#131826", sky = "#07090f", star = "#ffffff00",
				windowBorder = "#5b6a8c", accent = "#8fa3c8", title = "#e6c36a", personName = "#e6c36a",
				text = "#eef0f6", textDim = "#b9bfcc", textMuted = "#8e95a6",
			} },
		{ id = "brass", name = "Muted brass", desc = "Warm dark ground, a bronze edge, brass on the bar and the progress.",
			tokens = {
				bg = "#17110c", panel = "#1d160f", panelAlt = "#261d13", sky = "#17110c", star = "#ffffff00",
				windowBorder = "#5e4a2c", accent = "#b99a58", quest = "#c9ad6e", npc = "#a9c6de",
				text = "#f3ead8", textDim = "#cbbd9f", textMuted = "#a39578",
			} },
		{ id = "j", name = "J: one bar", desc = "One bar that fills as you go, no tabs or foot bar, the live goal in bold with a gold count, quest and level under each goal, Up next on a fading rail. Compact mode drops Up next and the XP row.",
			tokens = { accent = "#e6ba66" },
			preset = { ["guideWindow.tabs"] = false, ["guideWindow.progress"] = false, ["ui.upcoming"] = 3, ["ui.upcomingOpen"] = true } },
		{ id = "j2", name = "J2: one bar, timeline", desc = "J with the steps on a rail: done goals kept in place, the counts in a column, the tip as a strip at the card's foot and Up next on the rail. The Journey is a card below the window, collapsed. Training and the class quest come up as cards above the window. Compact mode keeps the tip strip.",
			tokens = { accent = "#e6ba66" },
			preset = { ["guideWindow.tabs"] = false, ["guideWindow.progress"] = false, ["nav.journeyOpen"] = false, ["ui.upcoming"] = 3, ["ui.upcomingOpen"] = true } },
	},
	defaultVariant = "calm",
	resolve = function(ctx)
		if OWN_ACCENT[ctx.variant] then return nil end
		local c = ctx.classColor and mute(ctx.classColor)
		if c then return { accent = c } end
	end,
	hooks = {
		-- No rule under the step bar.
		guideTitle = function(nav, parts)
			if parts.rule then parts.rule:Hide() end
			-- J: no backdrop behind the bar.
			if isJ() then
				if parts.band then parts.band:Hide() end
				if parts.bar then parts.bar:Hide() end
			end
		end,
		guideProgress = navFill,
		guidePlace = function(name, frame, width, height)
			if name == "after" then
				-- J2's rail shows the next step already.
				if tl() then
					frame:Hide()
					return true
				end
			end
			if name == "upnext" then
				timeline(frame)
				upFit(frame)
			end
			if name == "tip" then tipJ2(frame) end
			if name == "xp" then xpJ2(frame) end
			-- J2: the class guide on offer is the heads-up above the window.
			if name == "banner" and isJ2() and frame.psKind == "classQuest" then
				local GF = Polestar.UI and Polestar.UI.GuideFrame
				local kind, n
				if GF and GF.BannerNotice then kind, n = GF.BannerNotice() end
				if n and classHeadsUp(n) then
					frame:Hide()
					return true
				end
			end
			-- J2: the training reminder is a card above the window, × as Later.
			if name == "banner" and isJ2() and frame.psKind == "train" then
				local parts = Theme.GuideParts()
				if parts and parts.window then
					local stack = stackFrame(parts.window)
					slots.train = fillTrain(trainCard(stack), parts.window:GetWidth() or width)
					frame:Hide()
					return true
				end
			end
			if name == "classCard" then
				if not isJ2() then
					classClose(frame, false)
				else
					local CC = Polestar.UI and Polestar.UI.ClassCard
					local key = CC and CC.shown and CC.shown.key
					if key and classShut[key] then
						frame:Hide()
						return true
					end
					frame:SetHeight(frame:GetHeight())
					classClose(frame, true)
					slots.class = frame
					return true
				end
			end
			if name == "journey" and isJ2() then
				local parts = Theme.GuideParts()
				if parts and parts.window then
					frame:SetParent(bottomCard(parts.window))
					frame:SetHeight(height)
					below[#below + 1] = frame
					return true
				end
			end
			if name == "here" then hereLabel(frame, isJ2()) end
			if name == "here" and isJ2() then
				takeHere(frame)
				frame:SetHeight(height)
				slots.here = frame
				return true
			end
			if TAKE[name] then
				local parts = Theme.GuideParts()
				local top = parts and parts.window and topCard(parts.window)
				if top then
					if name == "here" then takeHere(frame, top) end
					frame:SetParent(top)
					taken[#taken + 1] = frame
					return true
				end
			end
			return false
		end,
		guideRow = function(row, goal, info)
			ledgerRow(row, goal, info)
			jRow(row, goal, info)
			countColumn(row, goal, info)
		end,
		guideUpRow = function(row, v, index) upRow(row, v, index) end,
		guideInset = function(name)
			if not tl() then return nil end
			if name == "card" then return CARD_X end
			if name == "upnext" then return UP_X end
		end,
		-- Brass and Tooltip: the class card in the variant's accent, not the class colour.
		card = function(frame, kind, parts)
			if kind == "headsupCompact" or kind == "hereCompact" then return isJ2() end
			if kind == "headsupGap" then return isJ2() and GAP or nil end
			if kind == "headsupAboveOnly" then return isJ2() end
			if kind == "headsupRewardGlyph" then return isJ2() and Theme.Media("icon-train") or nil end
			if not CARD_ACCENT[variant()] then return end
			local r, g, b = Theme.Accent()
			for _, region in ipairs(parts.accents or {}) do
				if region.SetTextColor then
					region:SetTextColor(r, g, b)
				elseif region.SetVertexColor then
					local _, _, _, a = region:GetVertexColor()
					region:SetVertexColor(r, g, b, a or 1)
				end
			end
		end,
		guideLayout = function(parts, width, y)
			layoutTop(parts)
			layoutStack(parts)
			layoutBottom(parts)
			navJ2(parts)
			altBeside(parts)
			rail(parts)
			return jFootRoom()
		end,
		-- J2c: compact mode keeps the tip, as the strip at the card's foot.
		-- J2: done goals stay in place; Up next has no heading on the rail.
		guideShows = function(name, shown)
			if name == "tip" then return isJ2() end
			if name == "done" then return isJ2() end
			if name == "goalScroll" then return not isJ2() end
			if name == "upnextHead" then return not tl() end
			-- The class-quest card on the chain's first step only.
			if name == "classCardLater" then return false end
			return shown
		end,
		guidePerson = function(person, width, h) return jHeader(person, width, h) end,
		guideAnchor = function()
			local parts = Theme.GuideParts()
			local own = parts and parts.window and kit.store(parts.window)
			if own and own.stack and own.stack:IsShown() then return own.stack end
			local top = own and own.top
			if top and top:IsShown() then return top end
		end,
		guideTakes = takesOut,
		guideRender = function(view, parts)
			fillOptional(view)
			jPerson(parts)
			-- The render shows Skip again after the layout: J2 keeps it in the menu.
			if isJ2() and parts.nav then parts.nav.Skip:Hide() end
		end,
	},
	-- Under another skin: While you're here gets its own panel back, the
	-- accent bars and Up next's rows their alpha, the live goal its font.
	-- (The pieces Atlas made itself hide by themselves.)
	onLeave = function()
		local parts = Theme.GuideParts()
		if not parts then return end
		local here = parts.here
		if here then
			for _, t in ipairs({ here.Panel, here.Edge }) do
				if t and t.SetAlpha then t:SetAlpha(1) end
			end
		end
		if parts.person and parts.person.Mark then parts.person.Mark:SetAlpha(1) end
		headerBack(parts.person)
		navBack(parts.nav)
		local CC = Polestar.UI and Polestar.UI.ClassCard
		local cf = CC and CC.Frame and CC.Frame()
		if cf then classClose(cf, false) end
		if here then hereLabel(here, false) end
		if parts.tip then tipJ2(parts.tip, true) end
		local GF = Polestar.UI and Polestar.UI.GuideFrame
		if GF and GF.xp then xpJ2(GF.xp, true) end
		for _, row in ipairs(parts.rows or {}) do
			if row.Mark then row.Mark:SetAlpha(1) end
			local own = kit.store(row)
			if own.level then own.level:Hide() end
			row.psLevelWidth = nil
			if own.singleLine then
				row.Text:SetWordWrap(true)
				row.Text:SetMaxLines(2)
				own.singleLine = nil
			end
			if own.boldFrom then
				row.Text:SetFont(own.boldFrom[1], own.boldFrom[2], own.boldFrom[3])
				own.boldFrom = nil
			end
		end
		if parts.upnext then
			for _, r in ipairs({ parts.upnext:GetChildren() }) do r:SetAlpha(1) end
		end
	end,
}))
