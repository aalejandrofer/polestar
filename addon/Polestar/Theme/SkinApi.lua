-- The Skin API, the part a skin for the guide window needs: another addon
-- registers a skin built on one of Polestar's looks, with its own tokens,
-- variants and hooks, and the player picks it with /polestar skin. A skin's
-- resolver and hooks run under pcall: the first error turns the skin off
-- for the session and its base look stands in.
--   Theme.RegisterSkin(id, spec) -> ok, message
-- spec: api (2), name, addon, author, version, desc, base (a built-in look,
-- "polestar" when left out), tokens ({ name = "#rrggbb[aa]" | { r, g, b[, a] } }),
-- variants ({ { id, name, desc, tokens, preset }, ... }), defaultVariant,
-- resolve(ctx) -> tokens (ctx: variant, class, classColor), hooks
-- ({ surface = fn }, the surfaces in HOOKS), onApply(), onLeave().

local _, ns = ...
local Theme = ns.Theme
local L = ns.L
local format, ipairs, pairs, pcall, tonumber, tostring, type = string.format, ipairs, pairs, pcall, tonumber, tostring, type

Theme.API_VERSION = 2

-- The hooks the guide window and its heads-up card hand to the skin in use
-- (Theme.SkinHook), after Polestar's own look is on: the window's title
-- (guideTitle), a goal row once painted (guideRow), room of the skin's own
-- under the window's parts (guideLayout), the step on screen (guideRender),
-- the guide's progress (guideProgress), the frame the heads-up card sits on
-- (guideAnchor), a part the skin places itself (guidePlace), a part the
-- window's mode leaves out that the skin keeps (guideShows: "tip" in compact
-- mode, "done" goals in place of their fold line), a goal the skin shows in a
-- card of its own (guideTakes), the step's header
-- (guidePerson), a part set in from the left (guideInset), an Up next row
-- (guideUpRow) and the class quest heads-up (card).
local HOOKS = { guideTitle = true, guideRow = true, guideLayout = true, guideRender = true, guideProgress = true,
	guideAnchor = true, guidePlace = true, guideShows = true, guideTakes = true, guidePerson = true, guideInset = true, guideUpRow = true,
	card = true }

local SKINS, FAILED, ORDER = {}, {}, {}

-- The built-in looks a skin may be drawn from.
local function builtin(id)
	return id == "polestar" or (type(id) == "string" and Theme.SKIN_PALETTES[id] ~= nil)
end

-- "#rrggbb", "#rrggbbaa" or { r, g, b[, a] } (0 to 1) -> { r, g, b, a } | nil
local function readColor(c)
	if type(c) == "string" then
		local hex = c:match("^#(%x+)$")
		if not hex or (#hex ~= 6 and #hex ~= 8) then return nil end
		local function at(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
		return { at(1), at(3), at(5), #hex == 8 and at(7) or 1 }
	elseif type(c) == "table" then
		local r, g, b, a = c[1], c[2], c[3], c[4] or 1
		for _, x in ipairs({ r, g, b, a }) do
			if type(x) ~= "number" or x < 0 or x > 1 then return nil end
		end
		return { r, g, b, a }
	end
end

-- A token table read into colours. -> tokens | nil, why
local function readTokens(t, what)
	if t == nil then return nil end
	if type(t) ~= "table" then return nil, what .. " are not a table" end
	local out = {}
	for name, c in pairs(t) do
		local col = type(name) == "string" and readColor(c)
		if not col then return nil, format("%s: %s is not a colour", what, tostring(name)) end
		out[name] = col
	end
	return out
end

local function report(id, msg)
	if ns.Debug then ns.Debug(format("skin %s: %s", tostring(id), msg)) end
end

-- Register skin `id`. -> ok, message (the refusal, or what was left out)
function Theme.RegisterSkin(id, spec)
	local why
	if type(id) ~= "string" or not id:match("^[%w_%-]+$") then
		why = "the id must be a word"
	elseif builtin(id) then
		why = "the id is one of Polestar's own looks"
	elseif type(spec) ~= "table" then
		why = "the spec is not a table"
	elseif spec.api ~= nil and (type(spec.api) ~= "number" or spec.api > Theme.API_VERSION) then
		why = "it needs Skin API " .. tostring(spec.api) .. "; this Polestar has " .. Theme.API_VERSION
	elseif type(spec.name) ~= "string" or spec.name == "" then
		why = "it has no name"
	elseif spec.base ~= nil and not builtin(spec.base) then
		why = "its base is not one of Polestar's looks"
	end
	local s = not why and { id = id, name = spec.name, addon = spec.addon, author = spec.author, version = spec.version,
		desc = spec.desc, base = spec.base or "polestar", api = spec.api or 1, hooks = {} } or nil
	if s then s.tokens, why = readTokens(spec.tokens, "its tokens") end
	if s and not why and spec.variants ~= nil then
		if type(spec.variants) ~= "table" or #spec.variants == 0 then
			why = "its variants are not a list"
		else
			s.variants, s.variantBy = {}, {}
			for i, v in ipairs(spec.variants) do
				if type(v) ~= "table" or type(v.id) ~= "string" or s.variantBy[v.id] then
					why = "variant " .. i .. " has no id of its own"
					break
				end
				local vt
				vt, why = readTokens(v.tokens, "variant " .. v.id .. "'s tokens")
				if why then break end
				if v.preset ~= nil and type(v.preset) ~= "table" then
					why = "variant " .. v.id .. "'s preset is not a table"
					break
				end
				s.variants[i] = v.id
				s.variantBy[v.id] = { id = v.id, name = v.name or v.id, desc = v.desc, tokens = vt, preset = v.preset }
			end
			s.defaultVariant = s.variantBy[spec.defaultVariant] and spec.defaultVariant or s.variants[1]
		end
	end
	for _, k in ipairs({ "resolve", "onApply", "onLeave" }) do
		if s and not why and spec[k] ~= nil and type(spec[k]) ~= "function" then why = k .. " is not a function" end
	end
	local skipped = {}
	if s and not why and spec.hooks ~= nil then
		if type(spec.hooks) ~= "table" then
			why = "its hooks are not a table"
		else
			for name, fn in pairs(spec.hooks) do
				if type(fn) ~= "function" then
					why = "hook " .. tostring(name) .. " is not a function"
					break
				end
				if HOOKS[name] then s.hooks[name] = fn else skipped[#skipped + 1] = tostring(name) end
			end
		end
	end
	if why then
		report(id, "refused: " .. why)
		return false, why
	end
	s.resolve, s.onApply, s.onLeave = spec.resolve, spec.onApply, spec.onLeave
	if not SKINS[id] then ORDER[#ORDER + 1] = id end
	SKINS[id] = s
	FAILED[id] = nil
	if Theme.SkinId() == id then Theme.Refresh() end
	if #skipped > 0 then
		table.sort(skipped)
		local note = "hooks this Polestar does not have, left out: " .. table.concat(skipped, ", ")
		report(id, note)
		return true, note
	end
	return true
end

-- The skin chosen (ui.skin) as it is drawn: a registered skin that has not
-- failed this session, else the built-in look Theme.SkinKey gives.
function Theme.SkinId()
	local k = ns.Get and ns.Get("ui.skin")
	if SKINS[k] and not FAILED[k] then return k end
	return Theme.SkinKey()
end

-- The variant of registered skin `s` in use: the player's pick
-- (ui.skinVariants.<id>) while the skin has it, else its default.
local function variantOf(s)
	if not s.variants then return nil end
	local v = ns.Get and ns.Get("ui.skinVariants." .. s.id)
	if v ~= nil and s.variantBy[v] then return v end
	return s.defaultVariant
end

-- The variant of skin `id` in use; nil for a skin without variants.
function Theme.SkinVariant(id)
	local s = SKINS[id]
	return s and variantOf(s) or nil
end

-- A registered skin's variants: { { id, name, desc }, ... } | nil
function Theme.SkinVariants(id)
	local s = SKINS[id]
	if not (s and s.variants) then return nil end
	local out = {}
	for i, vid in ipairs(s.variants) do
		local v = s.variantBy[vid]
		out[i] = { id = vid, name = v.name, desc = v.desc }
	end
	return out
end

-- A registered skin's public facts, or nil.
function Theme.SkinInfo(id)
	local s = SKINS[id]
	if not s then return nil end
	return { id = id, name = s.name, addon = s.addon, author = s.author, version = s.version, desc = s.desc,
		base = s.base, api = s.api, failed = FAILED[id] }
end

-- The registered skins' ids, in the order they came.
function Theme.RegisteredSkins()
	local out = {}
	for i, id in ipairs(ORDER) do out[i] = id end
	return out
end

-- The settings the variant of skin `id` in use sets when it is chosen
-- (its preset), or nil.
function Theme.SkinPreset(id)
	local s = SKINS[id]
	local v = s and s.variants and s.variantBy[variantOf(s)]
	return v and v.preset or nil
end

-- Set the preset of skin `id`'s variant in use, once. -> how many settings
function Theme.ApplySkinPreset(id)
	local n = 0
	for path, value in pairs(Theme.SkinPreset(id) or {}) do
		if type(path) == "string" then
			ns.Set(path, value)
			n = n + 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- The skin in use: its hooks, its pieces (Theme.SkinKit) and the switch.
---------------------------------------------------------------------------

local liveId, liveHooks

-- The skin stops for the session on its first error; its base look stands
-- in, and the player is told once.
local function failSkin(id, err)
	if not SKINS[id] or FAILED[id] then return end
	FAILED[id] = tostring(err)
	report(id, "failed: " .. tostring(err))
	if ns.Print then ns.Print(format(L["The skin %s stopped with an error and is off until you reload: %s"], SKINS[id].name, tostring(err))) end
	if ns.After then ns.After(0, Theme.Refresh) end
end

-- The skin in use's hook for `surface`, run with the module's own art.
-- -> true when a hook ran
function Theme.SkinHook(surface, ...)
	local fn = liveHooks and liveHooks[surface]
	if not fn or FAILED[liveId] then return false end
	local ok, err = pcall(fn, ...)
	if not ok then
		failSkin(liveId, err)
		return false
	end
	return true
end

-- The skin's hook for `surface` with its answer: -> true, its first result
-- when the hook ran; false when there is none or it failed.
function Theme.SkinHookValue(surface, ...)
	local fn = liveHooks and liveHooks[surface]
	if not fn or FAILED[liveId] then return false end
	local ok, v = pcall(fn, ...)
	if not ok then
		failSkin(liveId, v)
		return false
	end
	return true, v
end

-- Whether the skin in use hooks `surface`.
function Theme.SkinHooks(surface)
	return liveHooks ~= nil and liveHooks[surface] ~= nil and not FAILED[liveId]
end

-- The guide window's parts for a skin's hooks and its own frames: window,
-- rows (the goal rows, pooled) and GuideFrame.parts (strip, nav, body,
-- card, person, goals, tip, after, along, upnext, empty, band, banner,
-- foot, line, here). nil before the window is built. One table, made once.
local guideParts
function Theme.GuideParts()
	if guideParts then return guideParts end
	local G = ns.UI and ns.UI.GuideFrame
	local p = G and G.parts
	if not (p and G.frame) then return nil end
	guideParts = { window = G.frame, rows = G.rows }
	for k, v in pairs(p) do guideParts[k] = v end
	return guideParts
end

-- A skin's own pieces on a frame: kit.store(frame) is a table of the skin
-- in use's own for that frame; everything it holds that can hide is hidden
-- when another skin takes over.
local stores = setmetatable({}, { __mode = "k" }) -- frame -> skin id -> table
local function hideAll(v, seen)
	if type(v) ~= "table" or seen[v] then return end
	seen[v] = true
	if v.Hide then
		v:Hide()
		return
	end
	for _, x in pairs(v) do hideAll(x, seen) end
end
Theme.SkinKit = {
	store = function(frame)
		local byId = stores[frame]
		if not byId then
			byId = {}
			stores[frame] = byId
		end
		local id = liveId or Theme.SkinId()
		local own = byId[id]
		if not own then
			own = {}
			byId[id] = own
		end
		return own
	end,
}

-- The tokens of the skin in use (its own, its variant's over them, then its
-- resolver's), or nil for a built-in look.
local function liveTokens()
	local s = SKINS[Theme.SkinId()]
	if not s then return nil end
	local v = s.variants and s.variantBy[variantOf(s)]
	local t = {}
	for k, c in pairs(s.tokens or {}) do t[k] = c end
	for k, c in pairs(v and v.tokens or {}) do t[k] = c end
	if s.resolve then
		local r, g, b = Theme.ClassColor()
		local class
		if UnitClass then class = select(2, UnitClass("player")) end
		local ok, rt = pcall(s.resolve, { variant = variantOf(s), class = class, classColor = r and { r, g, b } or nil })
		local own, why
		if ok then own, why = readTokens(rt, "the resolver's tokens") else why = rt end
		if why then
			failSkin(s.id, "resolve: " .. tostring(why))
			return nil
		end
		for k, c in pairs(own or {}) do t[k] = c end
	end
	return t
end

-- The skin in use changed (at the start of every Theme.Refresh): the old
-- one's pieces hide and it hears onLeave, the new one hears onApply.
local function switch()
	local id = Theme.SkinId()
	if id == liveId then return end
	local old = SKINS[liveId]
	if liveId then
		local seen = {}
		for _, byId in pairs(stores) do hideAll(byId[liveId], seen) end
	end
	if old and old.onLeave then
		local ok, err = pcall(old.onLeave)
		if not ok then report(old.id, "onLeave: " .. tostring(err)) end
	end
	local s = SKINS[id]
	liveId, liveHooks = id, s and s.hooks or nil
	if s and s.onApply then
		local ok, err = pcall(s.onApply)
		if not ok then failSkin(id, "onApply: " .. tostring(err)) end
	end
end

-- What Theme.lua asks of the skin in use.
ns.SkinApi = {
	-- The built-in look a registered skin `k` is drawn from, or nil.
	base = function(k)
		local s = SKINS[k]
		if s and not FAILED[k] then return s.base end
	end,
	tokens = liveTokens,
	switch = switch,
}

-- A new variant pick repaints (the skin's tokens and hooks read it).
if ns.On then
	ns.On("SETTING_CHANGED", function(path)
		if type(path) == "string" and path:find("^ui%.skinVariants") then Theme.Refresh() end
	end)
end

---------------------------------------------------------------------------
-- Skin addons that load on demand: one names its skins in its TOC
--   ## X-Polestar-Skin: atlas        (several: "atlas, atlas-dark")
-- and Polestar loads it (out of combat) when the saved skin or the one the
-- player picks is its own.
---------------------------------------------------------------------------

-- Load the installed addon that declares skin `id`. -> ok, why
function Theme.LoadSkinAddon(id)
	if SKINS[id] then return true end
	local A = C_AddOns
	if not (A and A.GetNumAddOns and A.GetAddOnInfo and A.GetAddOnMetadata and A.LoadAddOn) then return false, "no addon list" end
	if InCombatLockdown and InCombatLockdown() then return false, "in combat" end
	for i = 1, A.GetNumAddOns() do
		local name = A.GetAddOnInfo(i)
		local declared = type(name) == "string" and A.GetAddOnMetadata(name, "X-Polestar-Skin") or nil
		if type(declared) == "string" then
			for x in declared:gmatch("[^,%s]+") do
				if x == id then
					if not (A.IsAddOnLoaded and A.IsAddOnLoaded(name)) then
						local ok, why = A.LoadAddOn(name)
						if not ok then return false, tostring(why) end
					end
					return SKINS[id] ~= nil, not SKINS[id] and (name .. " did not register it") or nil
				end
			end
		end
	end
	return false, "no installed addon declares it"
end

if ns.OnLogin then
	ns.OnLogin(function()
		local k = ns.Get("ui.skin")
		if type(k) == "string" and not SKINS[k] and not builtin(k) then Theme.LoadSkinAddon(k) end
		switch()
	end)
end

---------------------------------------------------------------------------
-- /polestar skin [id [variant]]: the skins, or choose one (and its variant,
-- whose preset is set once).
---------------------------------------------------------------------------

local function skinList()
	local names = {}
	for _, c in ipairs(Theme.SkinChoices()) do names[#names + 1] = c.value end
	for _, id in ipairs(ORDER) do
		local vs = Theme.SkinVariants(id)
		local ids = {}
		for i, v in ipairs(vs or {}) do ids[i] = v.id end
		names[#names + 1] = #ids > 0 and (id .. " (" .. table.concat(ids, ", ") .. ")") or id
	end
	return table.concat(names, ", ")
end

local function skinCommand(rest)
	local id, variant = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
	if id == "" then
		local now = Theme.SkinId()
		local v = Theme.SkinVariant(now)
		ns.Print(format(L["Skin: %s. Skins: %s"], v and (now .. " " .. v) or now, skinList()))
		return
	end
	if not (SKINS[id] or builtin(id)) then Theme.LoadSkinAddon(id) end
	local s = SKINS[id]
	if not (s or builtin(id)) then
		ns.Print(format(L["No skin called %s. Skins: %s"], id, skinList()))
		return
	end
	if variant ~= "" then
		if not (s and s.variantBy and s.variantBy[variant]) then
			local ids = {}
			for i, v in ipairs(s and s.variants or {}) do ids[i] = v end
			ns.Print(format(L["%s has no variant called %s. Its variants: %s"], id, variant, #ids > 0 and table.concat(ids, ", ") or "-"))
			return
		end
		ns.Set("ui.skinVariants." .. id, variant)
	end
	ns.Set("ui.skin", id)
	if s then Theme.ApplySkinPreset(id) end
	local v = Theme.SkinVariant(id)
	ns.Print(format(L["Skin set to %s."], v and (id .. " " .. v) or id))
end

if ns.RegisterCommand then
	ns.RegisterCommand("skin", skinCommand, L["Choose a skin and its variant (/polestar skin atlas j2)"])
end
