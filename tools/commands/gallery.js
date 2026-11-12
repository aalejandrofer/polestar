'use strict';
// `node tools/polestar.js gallery`: every surface of the addon on one page.
// Runs the playground's Lua session (tools/play/session.js) headless, puts
// each scene on (a step, a banner, a toast, a window), draws it in each look
// (standard, compact, transparent...) and writes one HTML contact sheet,
// each picture cropped to the addon's own frames. --compare draws the same
// scenes from a second checkout beside the first, for a before and after.
// --walk plays the guide goal by goal instead, the character walking to each
// goal in a few strides, and writes a player that steps through the frames.
//
// Nothing here needs a browser; the page opens from the disk.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { parseArgs } = require('../lib/cli');
const { ROOT } = require('../lib/paths');

const DEFAULT_OUT = path.join(ROOT, 'data', 'local', 'gallery');

// The looks a scene is drawn in: the settings each one sets.
const MODES = {
	standard: { name: 'Standard', set: { 'ui.style': 'standard' } },
	compact: { name: 'Compact', set: { 'ui.style': 'standard', 'ui.compact': true } },
	transparent: { name: 'Transparent', set: { 'ui.style': 'transparent', 'ui.backing': 'soft' } },
	'transparent-dark': { name: 'Transparent, dark', set: { 'ui.style': 'transparent', 'ui.backing': 'dark' } },
	'transparent-none': { name: 'Transparent, bare', set: { 'ui.style': 'transparent', 'ui.backing': 'none' } },
	'compact-transparent': { name: 'Compact, transparent', set: { 'ui.style': 'transparent', 'ui.backing': 'soft', 'ui.compact': true } },
	'no-class': { name: 'No class colour', set: { 'ui.style': 'standard', 'ui.classAccent': false } },
};
const DEFAULT_MODES = ['standard', 'compact', 'transparent'];

// Settings put back to their defaults before every scene.
const LOOK_KEYS = ['ui.style', 'ui.backing', 'ui.classAccent', 'ui.compact', 'ui.wholeStep', 'ui.upcoming',
	'ui.upcomingOpen', 'ui.showNotes', 'ui.notesOpen', 'ui.shown'];

// Lua installed once per session: the reset between scenes and the scene helpers.
const HELPERS = `gallery = {}
local ns = Polestar
local patched = {}
function gallery.patch(name, fn)
	local E = ns.Engine
	if patched[name] == nil then patched[name] = E[name] or false end
	E[name] = fn
end
function gallery.refresh()
	local g = ns.UI and ns.UI.GuideFrame
	if not g then return end
	if g.Render then pcall(g.Render) end
	if g.Layout then pcall(g.Layout) end
end
function gallery.notice(key, value)
	local g = ns.UI and ns.UI.GuideFrame
	if g and g.notices then g.notices[key] = value end
	gallery.refresh()
end
function gallery.hideTransients()
	local u = ns.UI or {}
	pcall(function() if u.WhileHereToast then u.WhileHereToast.Hide() end end)
	pcall(function() if u.GuideEnd then u.GuideEnd.Hide() end end)
	pcall(function() if u.StepList and u.StepList.On() then u.StepList.Toggle(false) end end)
	pcall(function() if ns.Nav and ns.Nav.alerts then ns.Nav.alerts.HideNotice() end end)
	pcall(function() if PolestarPicker then PolestarPicker:Hide() end end)
	-- The minimap would sit over a card a skin puts above the window.
	pcall(function() if Minimap then Minimap:Hide() end end)
	pcall(play.closeSpecial)
	for _, n in ipairs({ "PolestarClassToast", "PolestarDungeonToast" }) do
		local f = _G[n]
		if f and f.Hide then f:Hide() end
	end
end
function gallery.reset(keys, set, step)
	local E = ns.Engine
	for name, fn in pairs(patched) do E[name] = fn or nil end
	patched = {}
	local g = ns.UI and ns.UI.GuideFrame
	if g and g.notices then
		local n = g.notices
		n.questSkip, n.closedTab, n.train, n.outlevel, n.stepSkip = nil, nil, nil, nil, nil
	end
	-- pairs: luaTable writes the list's keys as strings, which ipairs skips.
	for _, k in pairs(keys) do ns.Set(k, ns.GetDefault(k)) end
	for k, v in pairs(set) do ns.Set(k, v) end
	gallery.hideTransients()
	if step and E.GetGuide() then E.Goto(step) end
	gallery.refresh()
end
-- Two rows for the While you're here list, the way Showcase fakes them.
function gallery.fakeHere()
	local s = ns.Engine.GetStepIndex() or 1
	return {
		{ step = s + 2, index = 1, here = "turnin", t = "turnin", quest = 0,
			hereText = "Turn in \\"Showcase Delivery\\" to Gelkak Gyromast", yards = 160 },
		{ step = s + 9, index = 2, here = "take", t = "accept", quest = 0, later = true,
			hereText = "Accept \\"A Second Thing To Do Nearby\\"", yards = 410 },
	}
end
-- The first step from 'from' whose window shows at least 'groups' persons
-- (NPCs, objects, places): a step with more on it than one line.
function gallery.findStep(groups, from)
	local E, UI = ns.Engine, ns.UI
	if not (E.GetGuide() and UI.StepGroups) then return nil end
	for s = from or 1, E.GetStepCount() do
		local v = E.GetStepView(s)
		if v and v.status ~= "na" then
			local ok, gs = pcall(UI.StepGroups, v)
			if ok and gs and #gs >= groups then return s end
		end
	end
end
-- Screen rectangles (UIParent pixels, y down) of the addon's frames on show.
local SKIP = { PolestarNavArrow = true, PolestarTargetButton = true, PolestarMinimapButton = true }
function gallery.rects(all)
	local out = {}
	local H = UIParent:GetHeight() * UIParent:GetEffectiveScale()
	-- PolestarUIParent covers the screen; the addon's frames are its children.
	local frames = { UIParent:GetChildren() }
	if PolestarUIParent then for _, c in ipairs({ PolestarUIParent:GetChildren() }) do frames[#frames + 1] = c end end
	for _, f in ipairs(frames) do
		local name = f.GetName and f:GetName()
		if name and name ~= "PolestarUIParent" and name:find("^Polestar") and (all or not SKIP[name]) and f:IsVisible() and f:GetLeft() then
			local s = f:GetEffectiveScale()
			local l, r, t, b = f:GetLeft() * s, f:GetRight() * s, f:GetTop() * s, f:GetBottom() * s
			-- A skin's card outside the window (a child past its edge) is in the picture too.
			for _, c in ipairs({ f:GetChildren() }) do
				if c:IsVisible() and c:GetLeft() and c:GetTop() then
					local cs = c:GetEffectiveScale()
					l, r = math.min(l, c:GetLeft() * cs), math.max(r, c:GetRight() * cs)
					t, b = math.max(t, c:GetTop() * cs), math.min(b, c:GetBottom() * cs)
				end
			end
			if r - l > 2 and t - b > 2 then out[#out + 1] = { name = name, x = l, y = H - t, w = r - l, h = t - b } end
		end
	end
	return out
end`;

// "atlas" or "atlas:ledger": the skin, and the variant picked under its card.
// "atlas:j+" also lays the skin's preset (its variant's over it) over the settings,
// as "Apply <skin>'s layout" on the Theme page does.
function skinLua(spec) {
	const preset = String(spec).endsWith('+');
	const [id, v] = String(spec).replace(/\+$/, '').split(':');
	// A skin's addon loads on demand (as the skin picker loads it) before it is picked.
	const load = `if Polestar.Theme.LoadSkinAddon then Polestar.Theme.LoadSkinAddon(${lua(id)}) end; `;
	const set = load + (v ? `Polestar.Set("ui.skinVariants." .. ${lua(id)}, ${lua(v)}); Polestar.Set("ui.skin", ${lua(id)})`
		: `Polestar.Set("ui.skin", ${lua(id)})`);
	return preset ? `${set}; local T = Polestar.Theme; if not T.SkinPreset and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Polestar_Options") end; local p = T.SkinPreset and T.SkinPreset(${lua(id)})
		if p then for k, x in pairs(p) do Polestar.Set(k, x) end else print("gallery: no preset for ${id}") end` : set;
}

// Each scene: what it puts on screen, as Lua run after the reset. `step`:
// the step the reset goes to ('live', 'busy' (a step with persons after the
// first) or a number). Ported from Showcase's scenes.
const SCENES = [
	{ id: 'live', name: 'Live step', step: 'live', lua: '' },
	{ id: 'busy', name: 'Step with several persons', step: 'busy', lua: '' },
	{ id: 'whole', name: 'Whole step shown', step: 'busy', lua: 'Polestar.Set("ui.wholeStep", true)' },
	{ id: 'upnext', name: 'Up next, open', step: 'live', lua: 'Polestar.Set("ui.upcoming", 3); Polestar.Set("ui.upcomingOpen", true)' },
	{ id: 'tip', name: 'Tip open', step: 'live', lua: 'Polestar.Set("ui.showNotes", true); Polestar.Set("ui.notesOpen", true)' },
	{ id: 'here', name: "While you're here (two rows)", step: 'live', lua: `local list = gallery.fakeHere()
gallery.patch("GetWhileHereList", function() return list end)
gallery.refresh()
local g = Polestar.UI.GuideFrame
if g.FillHere then pcall(g.FillHere, Polestar.Engine); pcall(g.Layout) end` },
	{ id: 'steplist', name: 'Step browser open', step: 'live', lua: 'local SL = Polestar.UI.StepList; if SL then SL.Toggle(true) end; gallery.refresh()' },
	{ id: 'questskip', name: 'Banner: quest skipped', step: 'live', lua: 'gallery.notice("questSkip", { title = "Beached Sea Turtle" })' },
	{ id: 'closedtab', name: 'Banner: tab closed', step: 'live', lua: 'gallery.notice("closedTab", { guideId = "gallery:none", title = "Darkshore (16-19)" })' },
	{ id: 'group', name: 'Banner: group quest', step: 'live', lua: 'gallery.patch("GroupQuestion", function() return 0, "The Tower of Showcase" end); gallery.refresh()' },
	{ id: 'lost', name: 'Banner: quest left the log', step: 'live', lua: 'gallery.patch("LostQuestion", function() return 0, "Beached Sea Turtle" end); gallery.refresh()' },
	{ id: 'train', name: 'Banner: class training due', step: 'live', lua: 'gallery.notice("train", { level = 20 })' },
	{ id: 'outlevel', name: 'Banner: outlevelled', step: 'live', lua: 'local g = Polestar.Engine.GetGuide(); if g then gallery.notice("outlevel", { guideId = g.id, title = "Ashenvale (20-30)" }) end' },
	{ id: 'classtoast', name: 'Toast: class quest', step: 'live', lua: 'Polestar.RunCommand("classtoast")' },
	{ id: 'dungeontoast', name: 'Toast: dungeon heads-up', step: 'live', lua: 'Polestar.RunCommand("dungeontoast")' },
	{ id: 'heretoast', name: "Toast: While you're here (window hidden)", step: 'live', lua: 'Polestar.Set("ui.shown", false); local T = Polestar.UI.WhileHereToast; if T then T.Show(gallery.fakeHere()[1]) end' },
	{ id: 'notice', name: 'Notice: transport alert', step: 'live', lua: 'local A = Polestar.Nav and Polestar.Nav.alerts; if A then A.ShowNotice("Zeppelin to Orgrimmar", "Arrives in 0:45 at the tower", 20) end' },
	{ id: 'guideend', name: 'Guide end', step: 'live', lua: 'local G, g = Polestar.UI.GuideEnd, Polestar.Engine.GetGuide(); if G and g then G.Show({ guideId = g.id, undone = 3, live = Polestar.Engine.GetStepIndex() }) end' },
	{ id: 'whatsnew', name: "What's new", step: 'live', lua: 'Polestar.RunCommand("whatsnew")', once: true },
	{ id: 'welcome', name: 'Welcome', step: 'live', lua: 'Polestar.RunCommand("welcome")', once: true },
];

const usage = `usage: node tools/polestar.js gallery [options]

Draws every scene (steps, banners, toasts, windows) in each look and writes
one HTML contact sheet, each picture cropped to the addon's frames.

  --root <checkout>     the checkout whose addon is drawn (default: this one)
  --compare <checkout>  draw the same scenes from a second checkout beside it
  --label <a,b>         column names for --root and --compare
  --skin <id[:variant]> ui.skin for the run (a skin the checkout has), and its variant
  --modes <a,b,...>     looks to draw: ${Object.keys(MODES).join(', ')}
                        (default ${DEFAULT_MODES.join(',')})
  --scenes <a,b,...>    only these scenes: ${SCENES.map((s) => s.id).join(', ')}
  --steps <n,n,...>     also draw these step numbers of the guide
  --race, --class       the character (default Dwarf SHAMAN)
  --level <n>           the character's level
  --guide <id>          the guide to open (default: the one Polestar picks)
  --walk <n>            play n goals instead, walking to each, and write a
                        step-through player (walk.html)
  --strides <n>         frames per walk to a goal (default 3)
  --events <n>          on the walk, a random banner or toast every n goals
                        (default 6, 0 for none; --seed <n> picks another set)
  --out <dir>           where the page goes (default data/local/gallery)`;

function parse(argv) {
	const { opts, error } = parseArgs(argv, {
		options: ['--root', '--compare', '--label', '--skin', '--modes', '--scenes', '--steps', '--race', '--class',
			'--level', '--guide', '--walk', '--strides', '--events', '--seed', '--out', '--scale'],
	});
	if (error) throw new Error(error);
	const list = (v) => (v ? String(v).split(',').map((s) => s.trim()).filter(Boolean) : null);
	const o = {
		help: !!opts.help,
		roots: [path.resolve(opts.root || ROOT), ...(opts.compare ? [path.resolve(opts.compare)] : [])],
		labels: list(opts.label),
		skin: opts.skin || null,
		modes: list(opts.modes) || DEFAULT_MODES,
		scenes: list(opts.scenes),
		steps: (list(opts.steps) || []).map(Number),
		race: opts.race || 'Dwarf',
		cls: (opts.class || 'SHAMAN').toUpperCase(),
		level: opts.level ? Number(opts.level) : null,
		guide: opts.guide || null,
		walk: opts.walk ? Number(opts.walk) : 0,
		strides: opts.strides ? Number(opts.strides) : 3,
		events: opts.events === undefined ? 6 : Number(opts.events),
		seed: opts.seed ? Number(opts.seed) : 1,
		scale: opts.scale ? Number(opts.scale) : null,
		out: path.resolve(opts.out || DEFAULT_OUT),
	};
	for (const m of o.modes) if (!MODES[m]) throw new Error(`unknown look "${m}"`);
	for (const s of o.scenes || []) if (!SCENES.some((x) => x.id === s)) throw new Error(`unknown scene "${s}"`);
	if (o.steps.some((n) => !Number.isInteger(n) || n < 1)) throw new Error('--steps needs step numbers');
	if (o.walk && !(Number.isInteger(o.walk) && o.walk > 0)) throw new Error('--walk needs a number of goals');
	for (const r of o.roots) {
		if (!fs.existsSync(path.join(r, 'tools', 'play', 'session.js'))) throw new Error(`${r} is not a Polestar checkout`);
		if (!fs.existsSync(path.join(r, 'data', 'forever', 'races.json'))) throw new Error(`${r}: data/forever is not built (or linked)`);
	}
	return o;
}

const lua = (s) => JSON.stringify(String(s));
const luaTable = (obj) => `{ ${Object.entries(obj).map(([k, v]) => `[${lua(k)}] = ${typeof v === 'string' ? lua(v) : String(v)}`).join(', ')} }`;

// One checkout's session: started on a temp character, its pictures and textures.
class Run {
	constructor(root, index, opts) {
		this.root = root;
		this.index = index;
		this.opts = opts;
		this.tex = new Set();
	}

	async start() {
		const { Session } = require(path.join(this.root, 'tools', 'play', 'session.js'));
		this.dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'polestar-gallery-'));
		this.session = new Session({ dataDir: this.dataDir, config: { race: this.opts.race, cls: this.opts.cls } });
		await this.session.start();
		await this.lua(HELPERS);
		// Past the login: the welcome and what's new come up after a moment.
		await this.act({ type: 'time', seconds: 5 });
		await this.lua('pcall(play.closeSpecial); gallery.hideTransients()');
		const o = this.opts;
		if (o.level) await this.act({ type: 'level', level: o.level });
		if (o.guide) await this.act({ type: 'loadGuide', guide: o.guide });
		if (o.skin) await this.lua(skinLua(o.skin));
		if (o.scale) await this.lua(`Polestar.Set("ui.scale", ${o.scale})`);
		this.base = {};
		const r = await this.lua(`local E = Polestar.Engine
local g = E.GetGuide()
local live = E.GetStepIndex()
return { guide = g and g.id, title = g and g.title, live = live, busy = gallery.findStep(3, (live or 0) + 1) or gallery.findStep(2, (live or 0) + 1) or live }`);
		this.base = r || {};
		return this;
	}

	async lua(code) {
		const r = await this.session.call(code);
		if (!r.ok) throw new Error(`${this.root}: ${r.error}${r.trace ? `\n${r.trace}` : ''}`);
		return r.value;
	}

	async act(action) {
		const r = await this.session.act(action, 0);
		if (r.crashed || r.failed) throw new Error(`${this.root}: ${r.error}`);
		return r;
	}

	// The picture now: the svg, cropped to `crop` (or the addon's frames).
	async picture(crop, all = false) {
		const r = await this.act({ type: 'render' });
		const rects = await this.lua(`return gallery.rects(${all})`);
		return { svg: r.svg, rects: rects || [], errors: r.errors || [], crop };
	}

	// The textures a picture uses, written next to the page; its URLs pointed there.
	textures(svg, outDir) {
		return svg.replace(/\/tex\/([0-9a-f]+)\.png/g, (_, h) => {
			const name = `${this.index}-${h}.png`;
			if (!this.tex.has(name)) {
				const buf = this.session.texture(h);
				if (buf) fs.writeFileSync(path.join(outDir, 'tex', name), buf);
				this.tex.add(name);
			}
			return `tex/${name}`;
		});
	}

	async stop() {
		if (this.session) await this.session.stop({ save: false });
		if (this.dataDir) fs.rmSync(this.dataDir, { recursive: true, force: true });
	}
}

// The union of rectangles, padded and kept on the screen.
function union(rects, pad = 16) {
	if (!rects.length) return { x: 0, y: 0, w: 1920, h: 1080 };
	let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
	for (const x of rects) {
		l = Math.min(l, x.x); t = Math.min(t, x.y);
		r = Math.max(r, x.x + x.w); b = Math.max(b, x.y + x.h);
	}
	l = Math.max(0, Math.floor(l - pad)); t = Math.max(0, Math.floor(t - pad));
	r = Math.min(1920, Math.ceil(r + pad)); b = Math.min(1080, Math.ceil(b + pad));
	return { x: l, y: t, w: r - l, h: b - t };
}

// One picture's svg for the page: its own ids (scenes share the defs'
// numbering), cropped, sized in CSS pixels.
let seq = 0;
function placed(svg, box, scale = 0.8) {
	const p = `q${(seq++).toString(36)}`;
	return svg
		.replace(/(id="|url\(#|href="#)s([cmg]\d+)/g, `$1${p}$2`)
		.replace(/viewBox="[^"]*"/, `viewBox="${box.x} ${box.y} ${box.w} ${box.h}" width="${Math.round(box.w * scale)}" height="${Math.round(box.h * scale)}"`);
}

function esc(s) {
	return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}

const STYLE = `:root{--bg:#f4f4f2;--fg:#1d1d1f;--dim:#6b6b70;--card:#fff;--line:#e2e2e0;--pane:#2a2d33}
@media (prefers-color-scheme:dark){:root{--bg:#16171a;--fg:#e8e8ea;--dim:#9a9aa2;--card:#1f2125;--line:#2e3036;--pane:#2a2d33}}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif}
header{position:sticky;top:0;z-index:2;background:var(--bg);border-bottom:1px solid var(--line);padding:12px 20px;display:flex;gap:16px;align-items:baseline;flex-wrap:wrap}
h1{font-size:16px;margin:0}header span{color:var(--dim)}
nav a{color:var(--dim);margin-right:10px;text-decoration:none;font-size:12px}nav a:hover{color:var(--fg)}
main{padding:12px 20px 60px}
section{margin:18px 0 28px}h2{font-size:14px;margin:0 0 8px}h2 small{color:var(--dim);font-weight:400;margin-left:8px}
.row{display:flex;gap:14px;overflow-x:auto;align-items:flex-start;padding-bottom:6px}
figure{margin:0;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px;flex:none}
figcaption{font-size:12px;color:var(--dim);margin-bottom:6px}
.pic{background:var(--pane);border-radius:4px;line-height:0;overflow:hidden}
.pic svg{display:block}
.note{color:var(--dim);font-size:12px;max-width:420px;white-space:pre-wrap;line-height:1.3;margin-top:6px}
.err{color:#d0473b;font-size:12px;max-width:420px;white-space:pre-wrap;line-height:1.3;margin-top:6px}
label{font-size:12px;color:var(--dim)}`;

function page(title, sub, body, extra = '') {
	return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title><style>${STYLE}${extra}</style></head><body>${body}</body></html>`;
}

function glyphDefs(runs) {
	const seen = new Map();
	for (const run of runs) {
		for (const d of run.session.glyphs.defs) {
			const id = /id="([^"]+)"/.exec(d);
			if (id && !seen.has(id[1])) seen.set(id[1], d);
		}
	}
	return `<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>${[...seen.values()].join('')}</defs></svg>`;
}

async function sheet(opts, runs) {
	const scenes = SCENES.filter((s) => !opts.scenes || opts.scenes.includes(s.id));
	for (const n of opts.steps) scenes.push({ id: `step${n}`, name: `Step ${n}`, step: n, lua: '' });
	const labels = opts.labels || runs.map((r) => path.basename(r.root) === path.basename(ROOT) && r.index === 0 ? 'this checkout' : path.basename(r.root));
	const rows = [];
	let count = 0;
	for (const scene of scenes) {
		const figs = [];
		for (const mode of opts.modes) {
			for (const run of runs) {
				const step = typeof scene.step === 'number' ? scene.step : run.base[scene.step] || run.base.live;
				await run.lua(`gallery.reset(${luaTable(Object.fromEntries(LOOK_KEYS.map((k, i) => [i + 1, k])))}, ${luaTable(MODES[mode].set)}, ${step || 'nil'})`);
				if (opts.skin) await run.lua(skinLua(opts.skin));
				let errors = [];
				const said = await run.lua('return #stub.messages');
				try {
					if (scene.lua) await run.lua(scene.lua);
				} catch (err) {
					errors.push(err.message.split('\n')[0]);
				}
				await run.act({ type: 'time', seconds: 1 });
				const pic = await run.picture();
				errors = errors.concat(pic.errors.map((e) => e.msg || String(e)));
				// What the addon said in the chat (a toast with nothing due says so).
				const chat = (await run.lua(`local out = {} for i = ${said} + 1, #stub.messages do local m = stub.messages[i]; out[#out + 1] = type(m) == "table" and (m.text or m[1]) or tostring(m) end return out`)) || [];
				const note = chat.map((m) => String(m).replace(/\|c[0-9a-fA-F]{8}|\|r/g, '')).join('\n');
				const box = union(pic.rects);
				const svg = run.textures(placed(pic.svg, box), opts.out);
				const cap = `${MODES[mode].name}${runs.length > 1 ? ` · ${labels[run.index]}` : ''}`;
				figs.push(`<figure><figcaption>${esc(cap)}</figcaption><div class="pic">${svg}</div>${note ? `<div class="note">${esc(note)}</div>` : ''}${errors.length ? `<div class="err">${esc(errors.slice(0, 3).join('\n'))}</div>` : ''}</figure>`);
				count++;
			}
		}
		const stepNote = typeof scene.step === 'number' ? `step ${scene.step}` : `step ${runs[0].base[scene.step] || runs[0].base.live || '?'}`;
		rows.push(`<section id="${scene.id}"><h2>${esc(scene.name)}<small>${esc(stepNote)}</small></h2><div class="row">${figs.join('')}</div></section>`);
		process.stdout.write(`\r${count} pictures`);
	}
	process.stdout.write('\n');
	const b = runs[0].base;
	const title = 'Polestar gallery';
	const sub = `${opts.race} ${opts.cls}${opts.level ? ` ${opts.level}` : ''} · ${b.title || b.guide || 'no guide'}${opts.skin ? ` · skin ${opts.skin}` : ''} · ${labels.join(' vs ')}`;
	const navLinks = scenes.map((s) => `<a href="#${s.id}">${esc(s.name.replace(/^(Banner|Toast|Notice): /, ''))}</a>`).join('');
	const html = page(title, sub, `${glyphDefs(runs)}<header><h1>${title}</h1><span>${esc(sub)}</span><nav>${navLinks}</nav></header><main>${rows.join('')}</main>`);
	const file = path.join(opts.out, 'index.html');
	fs.writeFileSync(file, html);
	return { file, count };
}

// The walk: per goal, a few strides toward the waypoint, then the goal done.
// Toasts and banners come up as the guide brings them; time runs between
// frames so they fade the way they do in the game.
// What the walk drops in: the scenes a player meets on the way.
const EVENTS = ['questskip', 'train', 'notice', 'classtoast', 'dungeontoast', 'group', 'lost'];
const HERE_EVENT = 'local T = Polestar.UI.WhileHereToast; if T then T.Show(gallery.fakeHere()[1]) end';

// A small seeded random (mulberry32), so a walk is the same every run.
function random(seed) {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6d2b79f5) >>> 0;
		let t = a;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

async function walk(opts, run) {
	const frames = [];
	const rnd = random(opts.seed);
	let dropped = null;
	const snap = async (what) => {
		const pic = await run.picture(null, true);
		const s = await run.lua(`local E, w = Polestar.Engine, stub.world
local g = E.GetGuide()
return { step = E.GetStepIndex(), level = w.level, zone = w.zone, map = w.map, x = w.x, y = w.y, wp = E.GetWaypoint() }`);
		frames.push({ ...pic, what, state: s });
	};
	await run.lua(`gallery.reset({}, {}, nil)`);
	await snap('start');
	for (let g = 0; g < opts.walk; g++) {
		const s = await run.lua('local w, wp = stub.world, Polestar.Engine.GetWaypoint(); return { map = w.map, x = w.x, y = w.y, wp = wp }');
		const wp = s && s.wp;
		if (wp && wp.map === s.map && typeof wp.x === 'number') {
			for (let k = 1; k <= opts.strides; k++) {
				const f = k / (opts.strides + 1);
				await run.act({ type: 'move', map: s.map, x: s.x + (wp.x - s.x) * f, y: s.y + (wp.y - s.y) * f });
				await run.act({ type: 'time', seconds: 2 });
				await snap(`walking to ${wp.label || 'the goal'}`);
			}
		}
		const r = await run.act({ type: 'goal' });
		await run.act({ type: 'time', seconds: 1 });
		// A dropped-in banner stays a goal, then goes: the reset clears what it patched.
		if (dropped) {
			await run.lua('gallery.reset({}, {}, nil)');
			dropped = null;
		}
		await snap(`${wp && wp.label ? wp.label : 'goal'}: ${r.result}`);
		if (opts.events > 0 && (g + 1) % opts.events === 0) {
			const pick = rnd() < 0.25 ? 'heretoast' : EVENTS[Math.floor(rnd() * EVENTS.length)];
			const scene = SCENES.find((x) => x.id === pick);
			await run.lua(pick === 'heretoast' ? HERE_EVENT : scene.lua).catch(() => {});
			await run.act({ type: 'time', seconds: 1 });
			dropped = pick;
			await snap(`event: ${scene.name}`);
		}
		process.stdout.write(`\r${g + 1}/${opts.walk} goals, ${frames.length} frames`);
		if (r.result === 'noguide') break;
	}
	process.stdout.write('\n');
	// One frame for the whole walk: every frame's addon frames together.
	const box = union(frames.flatMap((f) => f.rects));
	const items = frames.map((f, i) => `<div class="frame" data-i="${i}"${i ? ' hidden' : ''}><div class="pic">${run.textures(placed(f.svg, box, 0.9), opts.out)}</div></div>`);
	const meta = frames.map((f) => ({ what: f.what, step: f.state && f.state.step, level: f.state && f.state.level, zone: f.state && f.state.zone, errors: f.errors.map((e) => e.msg || String(e)) }));
	const b = run.base;
	const sub = `${opts.race} ${opts.cls} · ${b.title || b.guide || 'no guide'} · ${frames.length} frames`;
	const html = page('Polestar walk', sub, `${glyphDefs([run])}<header><h1>Polestar walk</h1><span>${esc(sub)}</span></header><main>
<div class="bar"><button id="prev">◀</button><button id="play">Play</button><button id="next">▶</button>
<input id="seek" type="range" min="0" max="${frames.length - 1}" value="0"><label><input id="speed" type="range" min="1" max="10" value="3"> speed</label></div>
<p id="what"></p>${items.join('')}</main>
<script>
const META = ${JSON.stringify(meta).replace(/</g, '\\u003c')};
const frames = [...document.querySelectorAll('.frame')];
let i = 0, timer = null;
const show = (n) => { frames[i].hidden = true; i = (n + frames.length) % frames.length; frames[i].hidden = false; seek.value = i;
	const m = META[i]; what.textContent = (i + 1) + '/' + frames.length + ' · step ' + m.step + ' · level ' + m.level + ' · ' + (m.zone || '') + ' · ' + m.what + (m.errors.length ? ' · ERROR ' + m.errors[0] : ''); };
const stop = () => { clearInterval(timer); timer = null; play.textContent = 'Play'; };
prev.onclick = () => { stop(); show(i - 1); };
next.onclick = () => { stop(); show(i + 1); };
seek.oninput = () => { stop(); show(+seek.value); };
play.onclick = () => { if (timer) return stop(); play.textContent = 'Pause'; timer = setInterval(() => show(i + 1), 1600 / +speed.value); };
document.onkeydown = (e) => { if (e.key === 'ArrowLeft') prev.onclick(); if (e.key === 'ArrowRight') next.onclick(); if (e.key === ' ') { e.preventDefault(); play.onclick(); } };
show(0);
</script>`, '.bar{display:flex;gap:8px;align-items:center;margin:8px 0}#seek{flex:1}#what{color:var(--dim);font-size:13px;min-height:1.4em}');
	const file = path.join(opts.out, 'walk.html');
	fs.writeFileSync(file, html);
	return { file, count: frames.length };
}

async function run(argv) {
	let opts;
	try {
		opts = parse(argv);
	} catch (err) {
		console.error(`${err.message}\n\n${usage}`);
		return 2;
	}
	if (opts.help) {
		console.log(usage);
		return 0;
	}
	if (opts.walk && opts.roots.length > 1) {
		console.error('--walk draws one checkout; leave out --compare');
		return 2;
	}
	fs.mkdirSync(path.join(opts.out, 'tex'), { recursive: true });
	const runs = opts.roots.map((r, i) => new Run(r, i, opts));
	try {
		for (const r of runs) await r.start();
		const out = opts.walk ? await walk(opts, runs[0]) : await sheet(opts, runs);
		console.log(`${out.count} ${opts.walk ? 'frames' : 'pictures'}: ${path.relative(process.cwd(), out.file) || out.file}`);
		return 0;
	} catch (err) {
		console.error(`gallery: ${err.message}`);
		return 1;
	} finally {
		for (const r of runs) await r.stop().catch(() => {});
	}
}

module.exports = { name: 'gallery', summary: 'Draw every scene in each look to one HTML page (or --walk a guide)', usage, run };
