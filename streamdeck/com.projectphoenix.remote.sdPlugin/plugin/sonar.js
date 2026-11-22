/**
 * Phoenix Remote — SteelSeries Sonar client (local, on the Gaming PC).
 *
 * Sonar's web server picks a new port each time it starts, so the address is
 * looked up through SteelSeries GG: coreProps.json gives GG's local HTTPS
 * address, and GG's /subApps lists Sonar's current web server. Only
 * 127.0.0.1 is ever contacted.
 *
 * Sonar must be in Streamer mode. Each channel then has two mixes:
 *   streaming  — what Kick viewers hear (sent to the Streaming PC)
 *   monitoring — what you hear in your headset
 * Channels: game, chatRender (Discord), chatCapture (mic), media, aux.
 * For the mic, the monitoring mute is what chat apps (Discord) receive.
 */
'use strict';

const fs = require('fs');
const http = require('http');
const https = require('https');

const CORE_PROPS = 'C:\\ProgramData\\SteelSeries\\GG\\coreProps.json';
const POLL_MS = 1500;
const RETRY_MS = 5000;
const CHANNELS = ['game', 'chatRender', 'chatCapture', 'media', 'aux'];
const LOCAL = /^(127\.0\.0\.1|localhost)$/;

function request(method, url) {
	return new Promise((resolve, reject) => {
		const u = new URL(url);
		if (!LOCAL.test(u.hostname)) return reject(new Error('refusing non-local address ' + u.host));
		const mod = u.protocol === 'https:' ? https : http;
		// GG's local HTTPS uses a self-signed certificate; only loopback is allowed above.
		const req = mod.request(u, { method, rejectUnauthorized: false, timeout: 3000 }, (res) => {
			let body = '';
			res.setEncoding('utf8');
			res.on('data', (c) => { body += c; });
			res.on('end', () => {
				if (res.statusCode >= 400) return reject(new Error(`HTTP ${res.statusCode} ${method} ${u.pathname}`));
				try { resolve(body ? JSON.parse(body) : null); } catch (e) { resolve(body.trim()); }
			});
		});
		req.on('timeout', () => req.destroy(new Error('timed out')));
		req.on('error', reject);
		req.end();
	});
}

class SonarClient {
	constructor(log) {
		this.log = log || (() => {});
		this.base = '';
		this.timer = null;
		this.listeners = new Set();
		this.state = {
			conn: 'searching', // searching | connected | classic | offline
			error: '',
			streamRoute: {}, // channel -> routed into the stream mix
			streamMuted: {}, // channel -> muted in the stream mix
			monitorMuted: {}, // channel -> muted in your headset (mic: muted to Discord)
			masterMonitorMuted: false
		};
	}

	onChange(fn) { this.listeners.add(fn); }

	setState(patch) {
		const before = JSON.stringify(this.state);
		Object.assign(this.state, patch);
		if (JSON.stringify(this.state) === before) return;
		for (const fn of this.listeners) {
			try { fn(this.state); } catch (e) { this.log('sonar listener error: ' + e.message); }
		}
	}

	start() { this.tick(); }

	async tick() {
		clearTimeout(this.timer);
		try {
			if (!this.base) await this.discover();
			await this.refresh();
		} catch (e) {
			if (this.base || this.state.conn !== 'offline') this.log('sonar: ' + e.message);
			this.base = '';
			this.setState({ conn: 'offline', error: e.code === 'ENOENT' ? 'SteelSeries GG not found' : e.message });
		}
		this.timer = setTimeout(() => this.tick(), this.base ? POLL_MS : RETRY_MS);
	}

	async discover() {
		const props = JSON.parse(fs.readFileSync(CORE_PROPS, 'utf8'));
		const sub = await request('GET', `https://${props.ggEncryptedAddress}/subApps`);
		const sonar = sub && sub.subApps && sub.subApps.sonar;
		if (!sonar || !sonar.isRunning) throw new Error('Sonar is not running');
		const base = sonar.metadata && sonar.metadata.webServerAddress;
		if (!base) throw new Error('Sonar web server not ready');
		this.base = base.replace(/\/$/, '');
		this.log('sonar: found at ' + this.base);
	}

	async refresh() {
		const mode = await request('GET', this.base + '/mode/');
		if (mode !== 'stream') {
			this.setState({ conn: 'classic', error: 'Sonar is in Classic mode — switch it to Streamer mode' });
			return;
		}
		const [vol, routes] = await Promise.all([
			request('GET', this.base + '/volumeSettings/streamer'),
			request('GET', this.base + '/streamRedirections')
		]);
		const streamRoute = {};
		const streamMuted = {};
		const monitorMuted = {};
		const streaming = (routes || []).find((r) => r.streamRedirectionId === 'streaming');
		for (const ch of CHANNELS) {
			const d = (vol.devices[ch] && vol.devices[ch].stream) || {};
			streamMuted[ch] = !!(d.streaming && d.streaming.muted);
			monitorMuted[ch] = !!(d.monitoring && d.monitoring.muted);
			const r = streaming && streaming.status.find((x) => x.role === ch);
			streamRoute[ch] = !!(r && r.isEnabled);
		}
		const master = (vol.masters && vol.masters.stream && vol.masters.stream.monitoring) || {};
		this.setState({ conn: 'connected', error: '', streamRoute, streamMuted, monitorMuted, masterMonitorMuted: !!master.muted });
	}

	async put(path) {
		if (!this.base) throw new Error('Sonar not connected');
		await request('PUT', this.base + path);
	}

	// ---- Reads ----------------------------------------------------------------

	onStream(ch) { return !!this.state.streamRoute[ch] && !this.state.streamMuted[ch]; }
	inHeadset(ch) { return ch === 'master' ? !this.state.masterMonitorMuted : !this.state.monitorMuted[ch]; }
	discordHearsMic() { return !this.state.monitorMuted.chatCapture; }

	talkMode() {
		const kick = this.onStream('chatCapture');
		const discord = this.discordHearsMic();
		if (kick && discord) return this.onStream('chatRender') && this.onStream('aux') ? 'party' : 'everyone';
		if (kick) return 'kick';
		if (discord) return 'discord';
		return 'nobody';
	}

	// ---- Writes ---------------------------------------------------------------

	async setStream(ch, on) {
		if (on) {
			if (!this.state.streamRoute[ch]) await this.put(`/streamRedirections/streaming/redirections/${ch}/isEnabled/true`);
			if (this.state.streamMuted[ch]) await this.put(`/volumeSettings/streamer/streaming/${ch}/isMuted/false`);
		} else {
			await this.put(`/volumeSettings/streamer/streaming/${ch}/isMuted/true`);
		}
	}

	async setHeadset(ch, on) {
		await this.put(`/volumeSettings/streamer/monitoring/${ch}/isMuted/${!on}`);
	}

	async toggleStream(ch) {
		await this.setStream(ch, !this.onStream(ch));
		await this.refresh();
	}

	async toggleHeadset(ch) {
		await this.setHeadset(ch, !this.inHeadset(ch));
		await this.refresh();
	}

	// everyone: Kick + Discord hear you · kick: Discord can't · discord: viewers can't
	// (and viewers stop hearing Discord / game chat) · party: everyone, and viewers
	// also hear Discord and game chat.
	async setTalkMode(mode) {
		const kick = mode !== 'discord';
		const discord = mode !== 'kick';
		await this.setStream('chatCapture', kick);
		await this.setHeadset('chatCapture', discord);
		if (mode === 'party') {
			await this.setStream('chatRender', true);
			await this.setStream('aux', true);
		} else if (mode === 'discord') {
			await this.setStream('chatRender', false);
			await this.setStream('aux', false);
		}
		await this.refresh();
	}
}

module.exports = SonarClient;
