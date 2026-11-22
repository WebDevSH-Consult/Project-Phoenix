/**
 * Phoenix Remote — Stream Deck plugin entry point.
 *
 * Bridges Stream Deck keys to Streamlabs Desktop on another PC. Every key's
 * image is redrawn from the shared Streamlabs state whenever it changes.
 */
/* global StreamlabsClient, SonarClient, PhoenixIcons */
'use strict';

const PREFIX = 'com.projectphoenix.remote.';
const HOLD_MS = 800;
const DEFAULT_HOST = '192.168.1.119';

// Keys driven by SteelSeries Sonar on this PC rather than Streamlabs.
const SONAR_ACTIONS = new Set(['viewers', 'headset', 'talk']);
const CHANNELS = {
	game: { label: 'Game', glyph: 'gamepad' },
	aux: { label: 'Game chat', glyph: 'gamechat' },
	chatRender: { label: 'Discord', glyph: 'chat' },
	media: { label: 'Music', glyph: 'music' },
	chatCapture: { label: 'Mic', glyph: 'mic' },
	master: { label: 'Deafen all', glyph: 'headset' }
};
const TALK = {
	everyone: { label: 'Everyone', glyph: 'people' },
	kick: { label: 'Kick only', glyph: 'broadcast' },
	discord: { label: 'Discord only', glyph: 'chat' },
	party: { label: 'Party mode', glyph: 'party' }
};

let sd = null;
let pluginUUID = '';
const keys = new Map(); // context -> { action, settings, hold, flash }

const client = new StreamlabsClient(log);
client.onChange(() => {
	renderAll();
	pushToInspectors();
});

const sonar = new SonarClient(log);
sonar.onChange(() => {
	renderAll();
	pushToInspectors();
});

// Entry point, called from main.js with Stream Deck's launch arguments.
function connectElgatoStreamDeckSocket(inPort, inPluginUUID, inRegisterEvent) {
	pluginUUID = inPluginUUID;
	sd = new WebSocket('ws://127.0.0.1:' + inPort);
	sd.onopen = () => {
		send({ event: inRegisterEvent, uuid: inPluginUUID });
		send({ event: 'getGlobalSettings', context: inPluginUUID });
		sonar.start();
	};
	sd.onmessage = (e) => onDeckEvent(JSON.parse(e.data));
	// Stream Deck closed or restarted the plugin: exit so it can start a fresh copy.
	sd.onclose = () => process.exit(0);
}

function send(obj) {
	if (sd && sd.readyState === WebSocket.OPEN) sd.send(JSON.stringify(obj));
}

function log(message) {
	send({ event: 'logMessage', payload: { message: '[PhoenixRemote] ' + message } });
}

function onDeckEvent(msg) {
	const { event, action, context, payload } = msg;
	switch (event) {
		case 'didReceiveGlobalSettings': {
			const s = (payload && payload.settings) || {};
			client.configure({ host: s.host || DEFAULT_HOST, port: s.port, token: s.token });
			break;
		}
		case 'willAppear':
			keys.set(context, { action: shortName(action), settings: payload.settings || {}, hold: null, flash: null });
			render(context);
			break;
		case 'willDisappear': {
			const k = keys.get(context);
			if (k) clearTimeout(k.hold && k.hold.timer);
			keys.delete(context);
			break;
		}
		case 'didReceiveSettings': {
			const k = keys.get(context);
			if (k) {
				k.settings = payload.settings || {};
				render(context);
			}
			break;
		}
		case 'keyDown':
			onKeyDown(context);
			break;
		case 'keyUp':
			onKeyUp(context);
			break;
		case 'propertyInspectorDidAppear':
			pushToInspector(context, action);
			break;
		case 'sendToPlugin':
			if (payload && payload.cmd === 'reconnect') client.reconnect();
			if (payload && payload.cmd === 'globalsChanged') send({ event: 'getGlobalSettings', context: pluginUUID });
			pushToInspector(context, action);
			break;
		default:
			break;
	}
}

function shortName(action) {
	return String(action || '').replace(PREFIX, '');
}

// ---- Key presses ------------------------------------------------------------

function needsHold(k) {
	// Going live / ending the stream is guarded by press-and-hold unless switched off.
	return k.action === 'stream' && k.settings.requireHold !== false;
}

function onKeyDown(context) {
	const k = keys.get(context);
	if (!k) return;
	if (k.action === 'status') {
		client.reconnect();
		return;
	}
	const conn = SONAR_ACTIONS.has(k.action) ? sonar.state.conn : client.state.conn;
	if (conn !== 'connected') {
		send({ event: 'showAlert', context });
		return;
	}
	if (needsHold(k)) {
		k.hold = { fired: false, timer: setTimeout(() => {
			k.hold.fired = true;
			run(context, k);
		}, HOLD_MS) };
		return;
	}
	run(context, k);
}

function onKeyUp(context) {
	const k = keys.get(context);
	if (!k || !k.hold) return;
	clearTimeout(k.hold.timer);
	const fired = k.hold.fired;
	k.hold = null;
	if (!fired) flash(context, k, 'HOLD');
}

function flash(context, k, text) {
	clearTimeout(k.flash && k.flash.timer);
	k.flash = { text, timer: setTimeout(() => { k.flash = null; render(context); }, 1500) };
	render(context);
}

async function run(context, k) {
	const s = k.settings;
	try {
		switch (k.action) {
			case 'stream':
				if (['starting', 'ending'].includes(client.state.streaming)) return;
				await client.toggleStreaming();
				break;
			case 'record':
				await client.toggleRecording();
				break;
			case 'replaybuffer':
				if (client.state.replay === 'offline') await client.startReplayBuffer();
				else await client.stopReplayBuffer();
				break;
			case 'replaysave':
				if (client.state.replay !== 'running') {
					flash(context, k, 'BUFFER OFF');
					send({ event: 'showAlert', context });
					return;
				}
				await client.saveReplay();
				flash(context, k, 'SAVED');
				break;
			case 'scene':
				await client.switchScene(s.sceneName);
				break;
			case 'mute':
				await client.toggleMute(s.sourceName);
				break;
			case 'viewers':
				await sonar.toggleStream(s.channel || 'game');
				break;
			case 'headset':
				await sonar.toggleHeadset(s.channel || 'game');
				break;
			case 'talk':
				await sonar.setTalkMode(s.mode || 'everyone');
				break;
			default:
				return;
		}
		log(`${k.action} ok ${s.sceneName || s.sourceName || s.channel || s.mode || ''}`.trim());
		send({ event: 'showOk', context });
	} catch (e) {
		log(`${k.action} failed: ${e.message}`);
		send({ event: 'showAlert', context });
	}
}

// ---- Rendering --------------------------------------------------------------

function renderAll() {
	for (const context of keys.keys()) render(context);
}

function render(context) {
	const k = keys.get(context);
	if (!k) return;
	const svg = PhoenixIcons.key(look(k));
	send({ event: 'setImage', context, payload: { image: PhoenixIcons.toDataUri(svg), target: 0 } });
}

function look(k) {
	if (SONAR_ACTIONS.has(k.action)) return lookSonar(k);
	const st = client.state;
	const s = k.settings;
	const linked = st.conn === 'connected';

	if (k.action === 'status') {
		switch (st.conn) {
			case 'connected': return { glyph: 'emblem', label: 'Connected', mode: 'ok' };
			case 'connecting': return { glyph: 'emblem', label: 'Linking…', mode: 'warn' };
			case 'auth-failed': return { glyph: 'emblem', label: 'Check token', mode: 'warn', badge: 'TOKEN' , badgeColor: PhoenixIcons.COLORS.amber };
			case 'unconfigured': return { glyph: 'emblem', label: 'Set up', mode: 'warn', badge: 'SETUP', badgeColor: PhoenixIcons.COLORS.amber };
			default: return { glyph: 'emblem', label: 'Offline', mode: 'off', badge: 'NO LINK', badgeColor: PhoenixIcons.COLORS.red };
		}
	}

	let out;
	switch (k.action) {
		case 'stream': {
			const live = st.streaming === 'live' || st.streaming === 'reconnecting';
			if (st.streaming === 'starting') out = { glyph: 'broadcast', label: 'Starting…', mode: 'warn' };
			else if (st.streaming === 'ending') out = { glyph: 'stop', label: 'Ending…', mode: 'warn' };
			else if (live) out = { glyph: 'stop', label: 'End stream', mode: 'live', badge: st.streaming === 'reconnecting' ? 'RECONNECT' : '● LIVE' };
			else out = { glyph: 'broadcast', label: 'Go live', mode: 'idle' };
			if (k.flash) out.label = live ? 'Hold to end' : 'Hold to go live';
			break;
		}
		case 'record': {
			const on = st.recording === 'recording';
			out = on
				? { glyph: 'stop', label: 'Stop rec', mode: 'live', badge: '● REC' }
				: { glyph: 'record', label: st.recording === 'starting' ? 'Starting…' : 'Record', mode: 'idle' };
			break;
		}
		case 'replaybuffer': {
			const on = st.replay === 'running' || st.replay === 'saving';
			out = on
				? { glyph: 'buffer', label: 'Buffer on', mode: 'active', badge: 'REPLAY', badgeColor: PhoenixIcons.COLORS.purple }
				: { glyph: 'buffer', label: 'Buffer off', mode: 'idle' };
			break;
		}
		case 'replaysave': {
			const ready = st.replay === 'running';
			out = { glyph: 'clip', label: st.replay === 'saving' ? 'Saving…' : 'Save clip', mode: ready ? 'idle' : 'off', dim: !ready && linked };
			if (k.flash) out = { glyph: 'clip', label: k.flash.text, mode: k.flash.text === 'SAVED' ? 'ok' : 'warn' };
			break;
		}
		case 'scene': {
			const scene = client.findScene(s.sceneName);
			const active = scene && scene.id === st.activeSceneId;
			out = { glyph: 'scene', label: s.label || s.sceneName || 'Pick scene', mode: active ? 'active' : 'idle' };
			if (active) Object.assign(out, { badge: 'ON AIR', badgeColor: PhoenixIcons.COLORS.magenta });
			if (linked && s.sceneName && !scene) Object.assign(out, { mode: 'warn', badge: 'MISSING', badgeColor: PhoenixIcons.COLORS.amber });
			break;
		}
		case 'mute': {
			const src = client.findAudio(s.sourceName);
			const isMic = s.kind !== 'speaker';
			const muted = src && src.muted;
			out = {
				glyph: muted ? (isMic ? 'micOff' : 'speakerOff') : (isMic ? 'mic' : 'speaker'),
				label: s.label || s.sourceName || 'Pick source',
				mode: muted ? 'live' : 'idle'
			};
			if (muted) out.badge = 'MUTED';
			if (linked && s.sourceName && !src) Object.assign(out, { mode: 'warn', badge: 'MISSING', badgeColor: PhoenixIcons.COLORS.amber });
			break;
		}
		default:
			out = { glyph: 'emblem', label: 'Phoenix', mode: 'idle' };
	}

	if (!linked) {
		out.mode = 'off';
		out.dim = true;
		out.badge = 'NO LINK';
		out.badgeColor = PhoenixIcons.COLORS.red;
	}
	return out;
}

function lookSonar(k) {
	const C = PhoenixIcons.COLORS;
	const s = k.settings;
	let out;
	if (k.action === 'talk') {
		const t = TALK[s.mode] || TALK.everyone;
		const now = sonar.talkMode() === (s.mode || 'everyone');
		out = { glyph: t.glyph, label: s.label || t.label, mode: now ? 'active' : 'idle' };
		if (now) Object.assign(out, { badge: 'NOW', badgeColor: C.magenta });
	} else {
		const ch = s.channel || 'game';
		const c = CHANNELS[ch] || CHANNELS.game;
		const label = s.label || c.label;
		if (k.action === 'viewers') {
			const isMic = ch === 'chatCapture';
			out = sonar.onStream(ch)
				? { glyph: c.glyph, label, mode: 'active', badge: 'ON AIR', badgeColor: C.magenta }
				: { glyph: c.glyph, label, mode: isMic ? 'live' : 'idle', slash: true, dim: !isMic,
					badge: 'OFF AIR', badgeColor: isMic ? C.red : '#4A4470' };
		} else if (ch === 'master') {
			out = sonar.inHeadset(ch)
				? { glyph: 'headset', label, mode: 'idle' }
				: { glyph: 'headset', label: 'Deafened', mode: 'live', slash: true, badge: 'DEAFENED' };
		} else {
			out = sonar.inHeadset(ch)
				? { glyph: c.glyph, label, mode: 'idle' }
				: { glyph: c.glyph, label, mode: 'live', slash: true, badge: 'MUTED' };
		}
	}

	switch (sonar.state.conn) {
		case 'connected':
			break;
		case 'classic':
			Object.assign(out, { mode: 'warn', dim: true, badge: 'CLASSIC', badgeColor: C.amber });
			break;
		default:
			Object.assign(out, { mode: 'off', dim: true, badge: 'NO SONAR', badgeColor: C.red });
	}
	return out;
}

// ---- Property inspector -----------------------------------------------------

function inspectorPayload() {
	const st = client.state;
	return {
		conn: st.conn,
		error: st.error,
		scenes: st.scenes.map((x) => x.name),
		audio: st.audio.map((x) => x.name),
		sonar: sonar.state.conn,
		sonarError: sonar.state.error
	};
}

function pushToInspector(context, action) {
	send({ event: 'sendToPropertyInspector', action, context, payload: inspectorPayload() });
}

function pushToInspectors() {
	for (const [context, k] of keys) pushToInspector(context, PREFIX + k.action);
}

module.exports = { connectElgatoStreamDeckSocket, log };
