/**
 * Phoenix Remote — key artwork.
 *
 * Every key image is an SVG generated here, so the live plugin (setImage) and
 * the PNG build script (tools/build-icons.mjs) draw from one source.
 * Style: YakOS Aurora base (dark navy tile, purple emblem, cyan diamond)
 * blended with the Phoenix cosmic look (magenta nebula glow, neon edge).
 */
(function (root) {
	'use strict';

	const C = {
		navyTop: '#0B0A26',
		navyBottom: '#170A33',
		purple: '#7C3AED',
		violet: '#A855F7',
		magenta: '#E040FB',
		cyan: '#22D3EE',
		text: '#F5F3FF',
		dim: '#8B86A8',
		red: '#FF3B5C',
		amber: '#FFB020',
		green: '#34F5A4'
	};

	// Accent per mode: edge colour, glyph colour, glow strength.
	const MODES = {
		idle: { edge: [C.cyan, C.magenta], glyph: C.cyan, glow: 0.55 },
		active: { edge: [C.magenta, C.violet], glyph: C.text, glow: 1 },
		live: { edge: [C.red, C.magenta], glyph: C.text, glow: 1 },
		warn: { edge: [C.amber, C.magenta], glyph: C.amber, glow: 0.8 },
		ok: { edge: [C.green, C.cyan], glyph: C.green, glow: 0.9 },
		off: { edge: ['#3A3558', '#2A2545'], glyph: C.dim, glow: 0 }
	};

	// 24x24 line glyphs, drawn with stroke="currentColor".
	const GLYPHS = {
		broadcast:
			'<circle cx="12" cy="12" r="2.2" fill="currentColor" stroke="none"/>' +
			'<path d="M8.2 15.8a5.4 5.4 0 0 1 0-7.6M15.8 8.2a5.4 5.4 0 0 1 0 7.6"/>' +
			'<path d="M5.2 18.8a9.6 9.6 0 0 1 0-13.6M18.8 5.2a9.6 9.6 0 0 1 0 13.6"/>',
		stop: '<rect x="7" y="7" width="10" height="10" rx="1.6" fill="currentColor" stroke="none"/>',
		record:
			'<circle cx="12" cy="12" r="8.5"/>' +
			'<circle cx="12" cy="12" r="4.6" fill="currentColor" stroke="none"/>',
		clip:
			'<path d="M20 12a8 8 0 1 1-2.35-5.65"/><path d="M20 4.5v4.2h-4.2"/>' +
			'<path d="M10.2 9.2l4.6 2.8-4.6 2.8z" fill="currentColor" stroke-linejoin="round"/>',
		buffer:
			'<path d="M4 7h11M4 12h16M4 17h8"/><circle cx="18.5" cy="7" r="1.6" fill="currentColor" stroke="none"/>' +
			'<circle cx="15.5" cy="17" r="1.6" fill="currentColor" stroke="none"/>',
		scene:
			'<rect x="3" y="5" width="18" height="12.5" rx="2"/>' +
			'<path d="M9 21h6M12 17.5V21"/><path d="M10.2 8.8l4.4 2.45-4.4 2.45z" fill="currentColor" stroke-linejoin="round"/>',
		mic:
			'<rect x="9" y="3" width="6" height="11" rx="3"/>' +
			'<path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M8.5 21h7"/>',
		micOff:
			'<rect x="9" y="3" width="6" height="11" rx="3"/>' +
			'<path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M8.5 21h7"/><path d="M4 4l16 16" stroke-width="2.4"/>',
		speaker:
			'<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor" stroke-linejoin="round"/>' +
			'<path d="M15.5 9a4.2 4.2 0 0 1 0 6M18 6.5a8 8 0 0 1 0 11"/>',
		speakerOff:
			'<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor" stroke-linejoin="round"/>' +
			'<path d="M15.5 9.5l5 5M20.5 9.5l-5 5"/>',
		// Aurora-style yak/phoenix emblem with the cyan diamond.
		emblem:
			'<path d="M3.5 3.5C5 9 8 12.5 12 14c4-1.5 7-5 8.5-10.5C17.5 6 15 7.5 12 7.5S6.5 6 3.5 3.5z" fill="#7C3AED" stroke="none"/>' +
			'<path d="M8.5 12.5L12 22l3.5-9.5c-1.2.8-2.3 1.3-3.5 1.5-1.2-.2-2.3-.7-3.5-1.5z" fill="#6D28D9" stroke="none"/>' +
			'<path d="M12 5.2l2.6 2.6L12 10.4 9.4 7.8z" fill="currentColor" stroke="none"/>' +
			'<path d="M12.6 15l-1.4 2.6h1.6l-1.2 2.6" stroke="#0B0A26" stroke-width="1"/>'
	};

	function esc(s) {
		return String(s).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
	}

	// Split a label into at most two lines that fit the key.
	function wrapLabel(label) {
		const text = String(label || '').toUpperCase().trim();
		if (text.length <= 10) return [text];
		const words = text.split(/\s+/);
		let best = null;
		for (let i = 1; i < words.length; i++) {
			const a = words.slice(0, i).join(' ');
			const b = words.slice(i).join(' ');
			const w = Math.max(a.length, b.length);
			if (!best || w < best.w) best = { lines: [a, b], w };
		}
		if (best && best.w <= 13) return best.lines;
		return [text.length > 13 ? text.slice(0, 12) + '…' : text];
	}

	/**
	 * Build a 144x144 key SVG.
	 * opts: { glyph, label, mode, badge, badgeColor, dim }
	 */
	function key(opts) {
		const m = MODES[opts.mode] || MODES.idle;
		const lines = wrapLabel(opts.label);
		const longest = Math.max(...lines.map((l) => l.length), 1);
		const fontSize = longest <= 7 ? 19 : longest <= 10 ? 16 : 13.5;
		const glyphY = lines.length === 2 ? 24 : 30;
		const labelY = lines.length === 2 ? 108 : 120;
		const uid = Math.random().toString(36).slice(2, 8);
		const opacity = opts.dim ? 0.45 : 1;

		const stars = [
			[22, 30, 1.1], [118, 22, 0.9], [104, 54, 0.7], [30, 92, 0.8], [126, 104, 1], [60, 16, 0.6], [86, 124, 0.7]
		].map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="#fff" opacity="0.55"/>`).join('');

		const label = lines.map((l, i) =>
			`<text x="72" y="${labelY + i * (fontSize + 2)}" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-weight="700" font-size="${fontSize}" letter-spacing="0.6" fill="${C.text}">${esc(l)}</text>`
		).join('');

		const badge = opts.badge
			? `<g><rect x="${72 - (opts.badge.length * 4.6 + 12)}" y="8" width="${opts.badge.length * 9.2 + 24}" height="20" rx="10" fill="${opts.badgeColor || C.red}"/>` +
			  `<text x="72" y="22.5" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-weight="800" font-size="12.5" letter-spacing="1" fill="#fff">${esc(opts.badge)}</text></g>`
			: '';

		return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 144 144" width="100%" height="100%">
<defs>
<linearGradient id="bg${uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.navyTop}"/><stop offset="1" stop-color="${C.navyBottom}"/></linearGradient>
<radialGradient id="nebA${uid}" cx="0.22" cy="0.18" r="0.75"><stop offset="0" stop-color="${C.magenta}" stop-opacity="${0.42 * m.glow + 0.08}"/><stop offset="1" stop-color="${C.magenta}" stop-opacity="0"/></radialGradient>
<radialGradient id="nebB${uid}" cx="0.85" cy="0.9" r="0.7"><stop offset="0" stop-color="${C.purple}" stop-opacity="${0.5 * m.glow + 0.1}"/><stop offset="1" stop-color="${C.purple}" stop-opacity="0"/></radialGradient>
<linearGradient id="edge${uid}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${m.edge[0]}"/><stop offset="1" stop-color="${m.edge[1]}"/></linearGradient>
<filter id="glow${uid}" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="3.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>
<rect x="0" y="0" width="144" height="144" rx="24" fill="url(#bg${uid})"/>
<rect x="0" y="0" width="144" height="144" rx="24" fill="url(#nebA${uid})"/>
<rect x="0" y="0" width="144" height="144" rx="24" fill="url(#nebB${uid})"/>
${stars}
<rect x="3" y="3" width="138" height="138" rx="21" fill="none" stroke="url(#edge${uid})" stroke-width="3.5" opacity="${0.55 + 0.45 * m.glow}" ${m.glow ? `filter="url(#glow${uid})"` : ''}/>
<g opacity="${opacity}">
<g transform="translate(${72 - 30} ${glyphY}) scale(2.5)" color="${m.glyph}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" ${m.glow ? `filter="url(#glow${uid})"` : ''}>${GLYPHS[opts.glyph] || ''}</g>
${label}
</g>
${badge}
</svg>`;
	}

	// Small white glyph for the Stream Deck action list (20x20 / 40x40).
	function listIcon(glyph) {
		return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100%" height="100%" color="#FFFFFF" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">${GLYPHS[glyph]}</svg>`;
	}

	function toDataUri(svg) {
		return 'data:image/svg+xml;charset=utf8,' + encodeURIComponent(svg);
	}

	const api = { key, listIcon, toDataUri, COLORS: C };
	if (typeof module !== 'undefined' && module.exports) module.exports = api;
	else root.PhoenixIcons = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
