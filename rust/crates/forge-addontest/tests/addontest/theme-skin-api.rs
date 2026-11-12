//! The Skin API's guide window part (Theme/SkinApi.lua): another addon registers a skin on one of Polestar's
//! looks, with tokens, variants and hooks; /polestar skin picks it and its variant and sets the variant's preset
//! once; its hooks dress the guide window and the heads-up card; a hook that raises turns the skin off for the
//! session. The repository's Atlas skin (addon/Polestar_Skin_Atlas) is the one a player gets.

use forge_addontest::{emitted, Addon, RunAddon};
use serde_json::{json, Value};

const UI_FILES: [&str; 3] = ["Core/Core.xml", "Theme/Theme.xml", "UI/UI.xml"];

fn run_with(script: &str, atlas: bool) -> Value {
	let mut addons = vec![Addon::files("Polestar", &UI_FILES)];
	if atlas {
		addons.push(Addon::name("Polestar_Skin_Atlas"));
	}
	emitted(&RunAddon {
		stubs: vec!["stub_ui.lua"],
		addons,
		script: format!(
			"uistub.install()\nstub.login()\nlocal GF = Polestar.UI.GuideFrame\nlocal F = PolestarGuideFrame\nlocal TABS = {{ {{ uistub.elwynn, 3 }}, {{ uistub.tailoring, 2 }}, {{ uistub.stormwindRep, 2 }} }}\nlocal function firstRow()\n\tfor _, r in ipairs(GF.rows) do if r:IsShown() and r.psGoal then return r end end\nend\n{script}"
		),
		..Default::default()
	})
	.remove(0)
}

fn run_ui(script: &str) -> Value {
	run_with(script, false)
}

fn n(v: &Value) -> f64 {
	v.as_f64().unwrap_or_else(|| panic!("not a number: {v}"))
}

// A skin dresses each goal row once painted (guideRow), takes room of its own under the window's parts
// (guideLayout: the window grows by its answer), hears every render with the step on screen (guideRender), paints
// its own progress (guideProgress) and gives the heads-up card the frame to sit on (guideAnchor). Without the
// skin, nothing of it stays.
#[test]
fn a_registered_skin_s_guide_window_hooks_dress_rows_add_room_follow_renders_and_anchor_the_heads_up() {
	let out = run_ui(
		r##"
		local T = Polestar.Theme
		local seen = { rows = 0, renders = 0 }
		local cards
		local ok, why = T.RegisterSkin("dense", { api = 2, name = "Dense", addon = "Test_Dense", base = "polestar",
			hooks = {
				guideRow = function(row, goal, info)
					seen.rows = seen.rows + 1
					row.psDense = goal.t .. (info.current and ":current" or "")
				end,
				guideLayout = function(parts, width, y)
					cards = cards or CreateFrame("Frame", nil, parts.window)
					cards:ClearAllPoints()
					cards:SetPoint("BOTTOMLEFT", parts.window, "TOPLEFT", 0, 0)
					cards:SetSize(width, 30)
					seen.layoutY = y
					return 20
				end,
				guideRender = function(view, parts) seen.renders = seen.renders + 1; seen.step = view and view.index or false; seen.parts = parts.window == F end,
				guideProgress = function(foot, frac) seen.frac = frac end,
				guideAnchor = function() return cards end,
			} })
		uistub.openTabs(TABS, 1)
		local before = math.floor(F:GetHeight() + 0.5)
		Polestar.Set("ui.skin", "dense")
		GF.Render()
		local after = math.floor(F:GetHeight() + 0.5)
		local r = firstRow()
		local CT = Polestar.UI.ClassToast
		CT.ShowCard({ head = "LEVEL 10", title = "Something ready", act = { label = "Go", run = function() end } })
		local _, rel = CT.frame:GetPoint(1)
		local onCards = rel == cards
		CT.Hide()
		Polestar.Set("ui.skin", "polestar")
		GF.Render()
		emit({ ok = ok, why = why or false, before = before, after = after, dense = r.psDense or false, rows = seen.rows > 0,
			renders = seen.renders > 0, step = seen.step, parts = seen.parts, frac = seen.frac ~= nil, layoutY = seen.layoutY ~= nil,
			onCards = onCards, back = math.floor(F:GetHeight() + 0.5), v = T.API_VERSION })"##,
	);
	assert_eq!(out["ok"], true, "registered: {}", out["why"]);
	assert_eq!(out["v"], 2);
	assert_eq!(
		(out["rows"].clone(), out["renders"].clone(), out["parts"].clone(), out["frac"].clone(), out["layoutY"].clone()),
		(json!(true), json!(true), json!(true), json!(true), json!(true)),
		"{out}"
	);
	assert!(out["dense"].as_str().unwrap_or("").len() > 1, "the row was dressed: {}", out["dense"]);
	assert_eq!(out["step"], 3, "the step on screen");
	assert_eq!(n(&out["after"]) - n(&out["before"]), 20.0, "the window grew by the skin's room");
	assert_eq!(out["onCards"], true, "the heads-up card sits on the skin's frame");
	assert_eq!(out["back"], out["before"], "back on the house skin, its own height");
}

// guidePlace: each part about to be placed is offered to the skin with its height; one the skin claims (its answer
// true) leaves the window: the window is shorter by that part ("Then:" by its height, the card's tip with its gap)
// and the part stays where the skin put it. Claimed no more, the part goes back under its own frame and the window
// gets its height back; a skin that claims nothing changes nothing.
#[test]
fn a_part_a_skin_places_itself_leaves_the_guide_window_s_height_and_comes_back_when_no_skin_claims_it() {
	let out = run_ui(
		r##"
		local T = Polestar.Theme
		local P = GF.parts
		local mine = CreateFrame("Frame", nil, UIParent)
		mine:SetSize(240, 120)
		local claim, offered = {}, {}
		local ok, why = T.RegisterSkin("cards", { api = 2, name = "Cards", addon = "Test_Cards", base = "polestar",
			hooks = {
				guidePlace = function(name, frame, width, height)
					offered[name] = { width = width, height = height }
					if not claim[name] then return false end
					frame:SetParent(mine)
					frame:ClearAllPoints()
					frame:SetPoint("TOPLEFT", mine, "TOPLEFT", 0, 0)
					return true
				end,
			} })
		uistub.openTabs(TABS, 1)
		local function h() return math.floor(F:GetHeight() + 0.5) end
		local house = h()
		local homes = { after = P.after:GetParent(), tip = P.tip:GetParent() }
		Polestar.Set("ui.skin", "cards")
		GF.Render()
		local hooked = h()
		local function offer(name)
			local o = offered[name]
			return o and o.width > 0 and o.height or false
		end
		local seen = { after = offer("after"), tip = offer("tip") }
		claim.after = true
		GF.Render()
		local _, rel = P.after:GetPoint(1)
		local noAfter = { h = h(), parent = P.after:GetParent() == mine, rel = rel == mine, shown = P.after:IsShown() }
		claim.tip = true
		GF.Render()
		local noTip = { h = h(), parent = P.tip:GetParent() == mine }
		claim.after, claim.tip = nil, nil
		GF.Render()
		local back = { h = h(), after = P.after:GetParent() == homes.after, tip = P.tip:GetParent() == homes.tip }
		Polestar.Set("ui.skin", "polestar")
		GF.Render()
		emit({ ok = ok, why = why or false, house = house, hooked = hooked, seen = seen, noAfter = noAfter, noTip = noTip,
			back = back, off = h() })"##,
	);
	assert_eq!(out["ok"], true, "registered: {}", out["why"]);
	assert_eq!(out["hooked"], out["house"], "a skin that claims nothing leaves the layout as it was");
	let offered = |part: &str| out["seen"][part].as_f64().filter(|h| *h > 0.0);
	let (Some(after), Some(tip)) = (offered("after"), offered("tip")) else {
		panic!("both parts are offered to the skin with their height: {}", out["seen"]);
	};
	let lost = n(&out["hooked"]) - n(&out["noAfter"]["h"]);
	assert!((lost - after).abs() <= 1.0, "\"Then:\" claimed: the window is {lost} shorter, the part is {after} high");
	assert_eq!(
		(out["noAfter"]["parent"].clone(), out["noAfter"]["rel"].clone(), out["noAfter"]["shown"].clone()),
		(json!(true), json!(true), json!(true)),
		"the claimed part stays where the skin put it"
	);
	let lost = n(&out["noAfter"]["h"]) - n(&out["noTip"]["h"]);
	assert!((lost - (tip + 2.0)).abs() <= 1.0, "the tip claimed: the window is {lost} shorter, the tip is {tip} high with its 2 of gap");
	assert_eq!(out["noTip"]["parent"], true);
	assert_eq!(out["back"], json!({ "h": out["house"].clone(), "after": true, "tip": true }), "claimed no more: back under its own frame, the window its height again");
	assert_eq!(out["off"], out["house"], "Polestar's own look: the house layout");
}

// guideInset moves the step's card and Up next in from the window's left (the card narrower by as much); guideUpRow
// hears each Up next row with its step and place; guideShows "upnextHead" false drops Up next's heading (its rows
// show) and guideShows is asked whether done goals stay in place. Back on the house skin, all of it is as it was.
#[test]
fn a_skin_insets_the_card_and_up_next_hears_up_next_rows_and_drops_up_next_s_heading() {
	let out = run_ui(
		r##"
		local T = Polestar.Theme
		local P = GF.parts
		local seen = { up = 0, first = false, asked = {} }
		local ok, why = T.RegisterSkin("rail", { api = 2, name = "Rail", addon = "Test_Rail", base = "polestar",
			hooks = {
				guideInset = function(name) return (name == "card" and 20) or (name == "upnext" and 10) or nil end,
				guideUpRow = function(row, v, i)
					seen.up = seen.up + 1
					if seen.up == 1 then seen.first = type(v) == "table" and type(i) == "number" and row ~= nil end
				end,
				guideShows = function(name, shown)
					seen.asked[name] = true
					if name == "upnextHead" then return false end
					return shown
				end,
			} })
		Polestar.Set("ui.upcoming", 3)
		uistub.openTabs(TABS, 1)
		stub.advance(1)
		local function at(f)
			local _, _, _, x = f:GetPoint(1)
			return { w = math.floor(f:GetWidth() + 0.5), x = math.floor((x or 0) + 0.5) }
		end
		local house = { card = at(P.card), up = at(P.upnext), shown = P.upnext:IsShown(), toggle = P.upnext.Toggle:IsShown() }
		Polestar.Set("ui.skin", "rail")
		GF.Render()
		stub.advance(1)
		local skinned = { card = at(P.card), up = at(P.upnext), toggle = P.upnext.Toggle:IsShown() }
		Polestar.Set("ui.skin", "polestar")
		GF.Render()
		stub.advance(1)
		local back = { card = at(P.card), up = at(P.upnext), toggle = P.upnext.Toggle:IsShown() }
		emit({ ok = ok, why = why or false, house = house, skinned = skinned, back = back, up = seen.up, first = seen.first,
			done = seen.asked.done or false, head = seen.asked.upnextHead or false })"##,
	);
	assert_eq!(out["ok"], true, "registered: {}", out["why"]);
	assert_eq!(out["house"]["shown"], true, "Up next is on screen: {out}");
	let (h, s) = (&out["house"], &out["skinned"]);
	assert_eq!(n(&s["card"]["x"]) - n(&h["card"]["x"]), 20.0, "the card moves in by its inset: {out}");
	assert_eq!(n(&h["card"]["w"]) - n(&s["card"]["w"]), 20.0, "the card narrows by its inset: {out}");
	assert_eq!(n(&s["up"]["x"]) - n(&h["up"]["x"]), 10.0, "Up next moves in by its inset: {out}");
	assert!(n(&out["up"]) > 0.0 && out["first"] == true, "each Up next row is offered with its step: {out}");
	assert_eq!((h["toggle"].clone(), s["toggle"].clone()), (json!(true), json!(false)), "Up next's heading dropped");
	assert_eq!((out["done"].clone(), out["head"].clone()), (json!(true), json!(true)), "guideShows is asked for both");
	assert_eq!(out["back"], out["house"].as_object().map(|o| {
		let mut o = o.clone();
		o.remove("shown");
		Value::Object(o)
	}).unwrap(), "back on the house skin: as it was");
}

// A skin's tokens lie over the scheme and its variant's over them; its accent stands in for Polestar gold only,
// under the player's own colour. Specs that would break the window are refused with the reason, and a hook that
// raises turns the skin off for the session (said once in chat), the saved choice kept.
#[test]
fn a_skin_s_tokens_and_variants_colour_the_window_bad_specs_are_refused_and_a_raising_hook_turns_it_off() {
	let out = run_ui(
		r##"
		local T = Polestar.Theme
		local function hex(name) return T.Hex(name):sub(3) end
		local house = { bg = hex("bg"), accent = hex("accent") }
		local ok, why = T.RegisterSkin("tint", { api = 2, name = "Tint", base = "polestar", tokens = { bg = "#101820" },
			variants = { { id = "plain", name = "Plain" }, { id = "gold", name = "Gold", tokens = { accent = "#e6ba66", bg = "#202020" } } },
			hooks = { guideRow = function() error("boom") end, notAHook = function() end } })
		Polestar.Set("ui.skin", "tint")
		local plain = { bg = hex("bg"), accent = hex("accent"), variant = T.SkinVariant("tint") }
		Polestar.Set("ui.skinVariants.tint", "gold")
		local gold = { bg = hex("bg"), accent = hex("accent"), variant = T.SkinVariant("tint") }
		Polestar.Set("ui.accent", { 0.2, 0.4, 0.6 })
		local own = hex("accent")
		Polestar.Set("ui.accent", nil)
		local refused = {}
		for i, spec in ipairs({ { name = "X", api = 9 }, { name = "X", base = "nowhere" }, { name = "X", tokens = { bg = "red" } },
			{ name = "X", variants = { { name = "no id" } } } }) do
			local r, msg = T.RegisterSkin("bad" .. i, spec)
			refused[i] = r == false and type(msg) == "string"
		end
		local builtin = T.RegisterSkin("halo", { name = "Mine" })
		local said = #stub.messages
		uistub.openTabs(TABS, 1)
		GF.Render()
		local lines = {}
		for i = said + 1, #stub.messages do lines[#lines + 1] = stub.messages[i] end
		emit({ ok = ok, why = why or false, house = house, plain = plain, gold = gold, own = own, refused = refused, builtin = builtin,
			failed = T.SkinInfo("tint").failed and true or false, id = T.SkinId(), saved = Polestar.Get("ui.skin"), lines = lines })"##,
	);
	assert_eq!(out["ok"], true, "registered, the unknown hook left out");
	assert!(out["why"].as_str().unwrap_or("").contains("notAHook"), "the left-out hook is named: {}", out["why"]);
	assert_eq!(out["plain"]["bg"], "101820", "the skin's own token");
	assert_eq!(out["plain"]["variant"], "plain", "the first variant without a pick");
	assert_eq!(out["plain"]["accent"], out["house"]["accent"], "no accent token: Polestar gold");
	assert_eq!((out["gold"]["bg"].clone(), out["gold"]["accent"].clone(), out["gold"]["variant"].clone()), (json!("202020"), json!("e6ba66"), json!("gold")));
	assert_eq!(out["own"], "336699", "the player's own accent over the skin's");
	assert_eq!(out["refused"], json!([true, true, true, true]));
	assert_eq!(out["builtin"], false, "a built-in look's id is refused");
	assert_eq!((out["failed"].clone(), out["id"].clone(), out["saved"].clone()), (json!(true), json!("polestar"), json!("tint")), "off for the session, the choice kept");
	let lines = out["lines"].as_array().cloned().unwrap_or_default();
	assert_eq!(lines.iter().filter(|l| l.as_str().unwrap_or("").contains("Tint stopped with an error")).count(), 1, "said once: {lines:?}");
}

// /polestar skin atlas j2: the Atlas addon (loaded on demand, as a player has it) is picked with its J2 variant and
// the variant's preset is set once: no tabs, no foot bar, the Journey collapsed. The window has one bar that fills
// as the guide's progress (no band or title bar), the live goal is bold with its gold count, and compact mode
// (J2c) keeps the tip. A wrong variant is said in chat and changes nothing; /polestar skin polestar takes the
// window back, Atlas's pieces hidden.
#[test]
fn the_skin_command_picks_atlas_j2_sets_its_preset_once_and_compact_mode_keeps_the_tip() {
	let out = run_with(
		r##"
		local T = Polestar.Theme
		uistub.openTabs(TABS, 1)
		local P = GF.parts
		local said = #stub.messages
		Polestar.RunCommand("skin atlas nope")
		local wrong = { skin = Polestar.Get("ui.skin"), line = stub.messages[#stub.messages] }
		Polestar.RunCommand("skin atlas j2")
		local line = stub.messages[#stub.messages]
		GF.Render()
		local function shown(f) return f and f:IsShown() and true or false end
		local j2 = { skin = T.SkinId(), key = T.SkinKey(), variant = T.SkinVariant("atlas"), tabs = Polestar.Get("guideWindow.tabs"),
			progress = Polestar.Get("guideWindow.progress"), journey = Polestar.Get("nav.journeyOpen"),
			strip = shown(P.strip), foot = shown(P.foot), band = shown(P.band), rule = shown(P.nav.Rule), accent = T.Hex("accent"):sub(3) }
		-- The preset is set once: a setting changed afterwards stays.
		Polestar.Set("guideWindow.tabs", true)
		GF.Render()
		local keeps = Polestar.Get("guideWindow.tabs")
		Polestar.Set("ui.compact", true)
		Polestar.Set("ui.showNotes", true)
		GF.Render()
		local compact = { tip = GF.parts.tip:IsShown(), variant = T.SkinVariant("atlas") }
		Polestar.Set("ui.compact", false)
		Polestar.RunCommand("skin polestar")
		GF.Render()
		local back = { skin = T.SkinId(), band = shown(P.band), rule = shown(P.nav.Rule) }
		emit({ wrong = wrong, line = line, j2 = j2, keeps = keeps, compact = compact, back = back,
			said = #stub.messages - said })"##,
		true,
	);
	assert_eq!(out["wrong"]["skin"], "polestar", "a wrong variant changes nothing");
	assert!(out["wrong"]["line"].as_str().unwrap_or("").contains("no variant called nope"), "{}", out["wrong"]["line"]);
	assert!(out["line"].as_str().unwrap_or("").contains("Skin set to atlas j2."), "{}", out["line"]);
	assert_eq!(
		out["j2"],
		json!({ "skin": "atlas", "key": "polestar", "variant": "j2", "tabs": false, "progress": false, "journey": false,
			"strip": false, "foot": false, "band": false, "rule": false, "accent": "e6ba66" }),
		"J2: one bar, no tabs, no foot bar, the Journey collapsed, its gold"
	);
	assert_eq!(out["keeps"], true, "the preset is set once, not held");
	assert_eq!(out["compact"], json!({ "tip": true, "variant": "j2" }), "J2c keeps the tip in compact mode");
	assert_eq!(out["back"], json!({ "skin": "polestar", "band": true, "rule": true }), "Polestar's own look back");
}

// Atlas clears the window's section lines, but the menu keeps its group lines (menuLine), and on J2's rail Up
// next has no heading to open it by, so its rows show even when the player once folded it. Skip is in the menu
// only, not on J2's bar. The guide's title on the bar lists the open guides, to switch with the strip off.
#[test]
fn atlas_keeps_the_menu_s_group_lines_and_j2_shows_up_next_rows_folded_or_not() {
	let out = run_with(
		r##"
		uistub.openTabs(TABS, 1)
		Polestar.RunCommand("skin atlas j2")
		Polestar.Set("ui.upcoming", 3)
		Polestar.Set("ui.upcomingOpen", false)
		GF.Render()
		stub.advance(1)
		local up = 0
		for i = 1, #GF.upRows do if GF.upRows[i]:IsShown() then up = up + 1 end end
		local skipBar = GF.parts.nav.Skip:IsShown()
		GF.parts.nav.Menu:Click()
		local M = PolestarMenu
		local seps, lit = 0, 0
		for i = 1, #(M and M.seps or {}) do
			local s = M.seps[i]
			if s:IsShown() then
				seps = seps + 1
				local tex = s.tex or s
				local a = select(4, tex:GetVertexColor())
				if (a or 1) > 0 then lit = lit + 1 end
			end
		end
		local skipMenu = false
		for i = 1, #(M and M.rows or {}) do
			local r = M.rows[i]
			if r:IsShown() and r.Text and r.Text:GetText() == "Skip this step" then skipMenu = true end
		end
		local menuShown = M and M:IsShown() or false
		M:Hide()
		-- The guide's title lists the open guides; a click switches.
		local hit = GF.parts.nav.Title.Hit
		local hitShown = hit:IsShown()
		hit:Click()
		local guides = {}
		for i = 1, #M.rows do
			local r = M.rows[i]
			if r:IsShown() then guides[#guides + 1] = r.Text:GetText() end
		end
		local second = M.rows[2]
		second:Click()
		local _, active = Polestar.Engine.GetTabs()
		-- Close guide, last in the list: the guide on screen goes.
		hit:Click()
		local last
		for i = 1, #M.rows do if M.rows[i]:IsShown() then last = M.rows[i] end end
		local closeText = last.Text:GetText()
		last:Click()
		local left = #(Polestar.Engine.GetTabs() or {})
		emit({ closeText = closeText, left = left, up = up, menu = menuShown, seps = seps, lit = lit, skipBar = skipBar, skipMenu = skipMenu,
			hitShown = hitShown, guides = guides, active = active })"##,
		true,
	);
	assert_eq!(out["menu"], true, "the menu opens: {out}");
	assert!(n(&out["seps"]) >= 2.0, "the menu is split into groups: {out}");
	assert_eq!(out["lit"], out["seps"], "every group line is painted, not cleared: {out}");
	assert_eq!(out["up"], json!(3), "J2 shows the three Up next rows though Up next was folded: {out}");
	assert_eq!((out["skipBar"].clone(), out["skipMenu"].clone()), (json!(false), json!(true)), "Skip is in the menu, not the bar: {out}");
	assert_eq!(out["hitShown"], true, "the title takes a click: {out}");
	assert_eq!(out["guides"].as_array().map(|g| g.len()), Some(5), "three open guides, Open in new tab and Close guide: {out}");
	assert_eq!((out["closeText"].clone(), out["left"].clone()), (json!("Close guide"), json!(2)), "Close guide closes the guide on screen: {out}");
	assert_eq!(out["active"], json!(2), "a click on the second guide switches to it: {out}");
}

// A skin's hooks during the layout see the step being drawn (GF.ShownStep), not the one before it: going back
// from step 2 to step 1, a skin drawing "the last step" found step 1 above itself.
#[test]
fn a_skin_s_layout_hooks_see_the_step_being_drawn() {
	let out = run_ui(
		r##"
		local T = Polestar.Theme
		local seen = {}
		T.RegisterSkin("seer", { api = 2, name = "Seer", addon = "Test_Seer", base = "polestar",
			hooks = { guidePerson = function(person, width, h) seen[#seen + 1] = GF.ShownStep(); return h end } })
		uistub.openTabs(TABS, 1)
		Polestar.Set("ui.skin", "seer")
		local E = Polestar.Engine
		E.Goto(2); stub.advance(0.25)
		seen = {}
		E.Goto(1); stub.advance(0.25)
		emit({ seen = seen })"##,
	);
	let seen = out["seen"].as_array().cloned().unwrap_or_default();
	assert!(!seen.is_empty(), "guidePerson ran: {out}");
	assert!(seen.iter().all(|v| v == &json!(1)), "every layout hook saw step 1: {out}");
}
