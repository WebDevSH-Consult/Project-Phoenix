// Renders Phoenix Remote's static PNGs (action list, default key images, plugin
// and category icons) from the same SVG generator the live plugin uses.
// Rasterises with headless Microsoft Edge, so there are no npm dependencies.
//
//   node streamdeck/tools/build-icons.mjs [--preview]
//
// --preview also writes preview.html: every key state on one sheet.

import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const pluginDir = resolve(here, '..', 'com.projectphoenix.remote.sdPlugin');
const icons = createRequire(import.meta.url)(join(pluginDir, 'plugin', 'icons.js'));

const EDGE_PATHS = [
	'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
	'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe'
];
const edge = EDGE_PATHS.find(existsSync);
if (!edge) throw new Error('Microsoft Edge not found; it is used to rasterise the SVGs.');

const work = mkdtempSync(join(tmpdir(), 'phoenix-icons-'));
const profile = join(work, 'edge-profile');

function rasterise(svg, outPng, size) {
	const svgFile = join(work, `icon-${size}-${Math.random().toString(36).slice(2)}.svg`);
	writeFileSync(svgFile, svg);
	mkdirSync(dirname(outPng), { recursive: true });
	execFileSync(edge, [
		'--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
		`--user-data-dir=${profile}`,
		'--default-background-color=00000000',
		`--window-size=${size},${size}`,
		`--screenshot=${outPng}`,
		pathToFileURL(svgFile).href
	], { stdio: 'ignore' });
	// msedge.exe can hand off to a background process and return before the
	// screenshot lands, so wait for the file.
	const deadline = Date.now() + 15000;
	while (!existsSync(outPng)) {
		if (Date.now() > deadline) throw new Error('Edge did not write ' + outPng);
		Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
	}
	Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 150);
}

// Writes name.png at `size` and name@2x.png at double size.
function pair(svg, base, size) {
	rasterise(svg, base + '.png', size);
	rasterise(svg, base + '@2x.png', size * 2);
}

const KEY_DEFAULTS = {
	stream: { glyph: 'broadcast', label: 'Go live', mode: 'idle' },
	record: { glyph: 'record', label: 'Record', mode: 'idle' },
	replaybuffer: { glyph: 'buffer', label: 'Replay buffer', mode: 'idle' },
	replaysave: { glyph: 'clip', label: 'Save clip', mode: 'idle' },
	scene: { glyph: 'scene', label: 'Scene', mode: 'idle' },
	mute: { glyph: 'mic', label: 'Mute', mode: 'idle' },
	status: { glyph: 'emblem', label: 'Phoenix', mode: 'idle' }
};
const LIST_GLYPHS = {
	stream: 'broadcast', record: 'record', replaybuffer: 'buffer', replaysave: 'clip',
	scene: 'scene', mute: 'mic', status: 'emblem'
};

const images = join(pluginDir, 'images');
for (const [name, opts] of Object.entries(KEY_DEFAULTS)) {
	pair(icons.key(opts), join(images, 'keys', name), 72);
	pair(icons.listIcon(LIST_GLYPHS[name]), join(images, 'actions', name), 20);
	console.log('built', name);
}
pair(icons.listIcon('emblem'), join(images, 'category'), 28);
pair(icons.key({ glyph: 'emblem', label: 'Phoenix', mode: 'active' }), join(images, 'plugin'), 256);
console.log('built plugin + category icons');

if (process.argv.includes('--preview')) {
	const C = icons.COLORS;
	const states = [
		['Go live', { glyph: 'broadcast', label: 'Go live', mode: 'idle' }],
		['Live', { glyph: 'stop', label: 'End stream', mode: 'live', badge: '● LIVE' }],
		['Record', { glyph: 'record', label: 'Record', mode: 'idle' }],
		['Recording', { glyph: 'stop', label: 'Stop rec', mode: 'live', badge: '● REC' }],
		['Buffer on', { glyph: 'buffer', label: 'Buffer on', mode: 'active', badge: 'REPLAY', badgeColor: C.purple }],
		['Save clip', { glyph: 'clip', label: 'Save clip', mode: 'idle' }],
		['Scene', { glyph: 'scene', label: 'Starting Soon', mode: 'idle' }],
		['Scene on air', { glyph: 'scene', label: 'Live Scene', mode: 'active', badge: 'ON AIR', badgeColor: C.magenta }],
		['Mic', { glyph: 'mic', label: 'Mic', mode: 'idle' }],
		['Mic muted', { glyph: 'micOff', label: 'Mic', mode: 'live', badge: 'MUTED' }],
		['Connected', { glyph: 'emblem', label: 'Connected', mode: 'ok' }],
		['No link', { glyph: 'scene', label: 'Be Right Back', mode: 'off', dim: true, badge: 'NO LINK', badgeColor: C.red }]
	];
	const cells = states.map(([t, o]) => `<figure>${icons.key(o)}<figcaption>${t}</figcaption></figure>`).join('');
	const out = join(here, '..', 'preview.html');
	writeFileSync(out, `<!doctype html><meta charset="utf-8"><title>Phoenix Remote keys</title>
<style>body{background:#111;color:#bbb;font:13px Segoe UI;display:grid;grid-template-columns:repeat(6,150px);gap:14px;padding:20px}
figure{margin:0;text-align:center}svg{width:144px;height:144px}</style>${cells}`);
	console.log('preview:', out);
}

// Background Edge processes may still hold the temp profile; cleanup is best-effort.
try {
	rmSync(work, { recursive: true, force: true, maxRetries: 5, retryDelay: 300 });
} catch {
	console.log('note: could not remove temp folder', work);
}
