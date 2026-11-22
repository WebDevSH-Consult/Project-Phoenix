/**
 * Phoenix Remote — Streamlabs Desktop Remote Control client.
 *
 * Talks JSON-RPC 2.0 to Streamlabs Desktop's Remote Control API over its raw
 * SockJS WebSocket endpoint (ws://<host>:<port>/api/websocket). Authenticates
 * with TcpServerService.auth(token), subscribes to status events, and polls a
 * light snapshot as a safety net so keys never show stale state.
 *
 * The token is only ever sent to Streamlabs; it is never logged.
 */
(function (root) {
	'use strict';

	const REQUEST_TIMEOUT_MS = 5000;
	const POLL_MS = 3000;

	class StreamlabsClient {
		constructor(log) {
			this.log = log || (() => {});
			this.cfg = { host: '', port: 59650, token: '' };
			this.ws = null;
			this.nextId = 1;
			this.pending = new Map();
			this.listeners = new Set();
			this.retryMs = 2000;
			this.retryTimer = null;
			this.pollTimer = null;
			this.state = this.emptyState('unconfigured');
		}

		emptyState(conn) {
			return {
				conn, // unconfigured | connecting | connected | auth-failed | disconnected
				error: '',
				streaming: 'offline', // offline | starting | live | ending | reconnecting
				recording: 'offline', // offline | starting | recording | stopping
				replay: 'offline', // offline | running | saving | stopping
				scenes: [], // [{ id, name }]
				activeSceneId: '',
				audio: [] // [{ sourceId, name, muted, resourceId }]
			};
		}

		onChange(fn) {
			this.listeners.add(fn);
		}

		emit() {
			for (const fn of this.listeners) {
				try { fn(this.state); } catch (e) { this.log('listener error: ' + e.message); }
			}
		}

		// Only notify when something actually changed, so the 3s poll doesn't redraw every key.
		setState(patch) {
			const before = JSON.stringify(this.state);
			Object.assign(this.state, patch);
			if (JSON.stringify(this.state) !== before) this.emit();
		}

		configure(cfg) {
			const next = {
				host: String(cfg.host || '').trim(),
				port: Number(cfg.port) || 59650,
				token: String(cfg.token || '').trim()
			};
			const changed = next.host !== this.cfg.host || next.port !== this.cfg.port || next.token !== this.cfg.token;
			this.cfg = next;
			if (changed) this.reconnect();
		}

		reconnect() {
			this.teardown();
			this.retryMs = 2000;
			if (!this.cfg.host || !this.cfg.token) {
				this.state = this.emptyState('unconfigured');
				this.emit();
				return;
			}
			this.connect();
		}

		teardown() {
			clearTimeout(this.retryTimer);
			clearInterval(this.pollTimer);
			this.retryTimer = null;
			this.pollTimer = null;
			for (const p of this.pending.values()) {
				clearTimeout(p.timer);
				p.reject(new Error('connection closed'));
			}
			this.pending.clear();
			if (this.ws) {
				this.ws.onopen = this.ws.onclose = this.ws.onerror = this.ws.onmessage = null;
				try { this.ws.close(); } catch (e) { /* already closed */ }
				this.ws = null;
			}
		}

		connect() {
			const url = `ws://${this.cfg.host}:${this.cfg.port}/api/websocket`;
			this.setState({ conn: 'connecting', error: '' });
			this.log('connecting to ' + url);
			let ws;
			try {
				ws = new WebSocket(url);
			} catch (e) {
				this.scheduleRetry('could not open socket: ' + e.message);
				return;
			}
			this.ws = ws;
			ws.onopen = () => this.handshake();
			ws.onmessage = (e) => this.handleMessage(e.data);
			ws.onerror = () => { /* onclose follows and handles retry */ };
			ws.onclose = () => {
				if (this.ws !== ws) return;
				this.ws = null;
				if (this.state.conn !== 'auth-failed') this.scheduleRetry('connection closed');
			};
		}

		scheduleRetry(reason) {
			clearInterval(this.pollTimer);
			this.pollTimer = null;
			if (this.state.conn !== 'auth-failed') this.setState({ conn: 'disconnected', error: reason });
			const wait = this.state.conn === 'auth-failed' ? 15000 : this.retryMs;
			this.retryMs = Math.min(this.retryMs * 2, 15000);
			clearTimeout(this.retryTimer);
			this.retryTimer = setTimeout(() => {
				this.teardown();
				this.connect();
			}, wait);
		}

		async handshake() {
			try {
				await this.request('auth', 'TcpServerService', [this.cfg.token]);
			} catch (e) {
				this.log('auth failed: ' + e.message);
				this.setState({ conn: 'auth-failed', error: 'Streamlabs rejected the token' });
				this.teardown();
				this.scheduleRetry('auth failed');
				return;
			}
			this.retryMs = 2000;
			this.log('authenticated');
			await this.subscribeAll();
			await this.refresh();
			this.setState({ conn: 'connected', error: '' });
			this.logSnapshot();
			this.pollTimer = setInterval(() => this.refresh().catch(() => {}), POLL_MS);
		}

		async subscribeAll() {
			const subs = [
				['StreamingService', 'streamingStatusChange'],
				['StreamingService', 'recordingStatusChange'],
				['StreamingService', 'replayBufferStatusChange'],
				['ScenesService', 'sceneSwitched'],
				['ScenesService', 'sceneAdded'],
				['ScenesService', 'sceneRemoved'],
				['SourcesService', 'sourceUpdated'],
				['SourcesService', 'sourceAdded'],
				['SourcesService', 'sourceRemoved'],
				['SceneCollectionsService', 'collectionSwitched']
			];
			await Promise.all(subs.map(([res, ev]) =>
				this.request(ev, res).catch((e) => this.log(`subscribe ${res}.${ev} failed: ${e.message}`))
			));
		}

		// One line per connect so the log shows what each API call returned.
		logSnapshot() {
			const s = this.state;
			const active = this.state.scenes.find((x) => x.id === s.activeSceneId);
			this.log(`snapshot: streaming=${s.streaming} recording=${s.recording} replay=${s.replay}` +
				` scenes=[${s.scenes.map((x) => x.name).join(', ')}] active=${active ? active.name : '?'}` +
				` audio=[${s.audio.map((a) => `${a.name}${a.muted ? ' (muted)' : ''}`).join(', ')}]`);
		}

		// Full snapshot. Each part fails independently so one bad call never blanks the rest.
		async refresh() {
			const [model, scenes, active, audio] = await Promise.all([
				this.request('getModel', 'StreamingService').catch(() => null),
				this.request('getScenes', 'ScenesService').catch(() => null),
				this.request('activeScene', 'ScenesService').catch(() => null),
				this.request('getSources', 'AudioService').catch(() => null)
			]);
			const patch = {};
			if (model) {
				patch.streaming = model.streamingStatus || 'offline';
				patch.recording = model.recordingStatus || 'offline';
				patch.replay = model.replayBufferStatus || 'offline';
			}
			if (Array.isArray(scenes)) patch.scenes = scenes.map((s) => ({ id: s.id, name: s.name }));
			if (active && active.id) patch.activeSceneId = active.id;
			if (Array.isArray(audio)) {
				patch.audio = audio.map((a) => ({
					sourceId: a.sourceId,
					name: a.name,
					muted: !!a.muted,
					resourceId: a.resourceId || `AudioSource["${a.sourceId}"]`
				}));
			}
			if (Object.keys(patch).length) this.setState(patch);
		}

		handleMessage(raw) {
			let msg;
			try { msg = JSON.parse(raw); } catch (e) { return; }
			const result = msg.result;
			if (result && result._type === 'EVENT') {
				this.handleEvent(result.resourceId, result.data);
				return;
			}
			const p = this.pending.get(msg.id);
			if (!p) return;
			this.pending.delete(msg.id);
			clearTimeout(p.timer);
			if (msg.error) p.reject(new Error(msg.error.message || 'request failed'));
			else p.resolve(result);
		}

		handleEvent(resourceId, data) {
			switch (resourceId) {
				case 'StreamingService.streamingStatusChange':
					this.setState({ streaming: data });
					break;
				case 'StreamingService.recordingStatusChange':
					this.setState({ recording: data });
					break;
				case 'StreamingService.replayBufferStatusChange':
					this.setState({ replay: data });
					break;
				case 'ScenesService.sceneSwitched':
					if (data && data.id) this.setState({ activeSceneId: data.id });
					break;
				case 'SourcesService.sourceUpdated': {
					if (!data || !data.sourceId) break;
					const audio = this.state.audio.map((a) =>
						a.sourceId === data.sourceId ? Object.assign({}, a, { muted: !!data.muted, name: data.name || a.name }) : a
					);
					this.setState({ audio });
					break;
				}
				default:
					// Scene/source added or removed, collection switched: take a fresh snapshot.
					this.refresh().catch(() => {});
			}
		}

		request(method, resource, args) {
			return new Promise((resolve, reject) => {
				if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
					reject(new Error('not connected'));
					return;
				}
				const id = this.nextId++;
				const timer = setTimeout(() => {
					this.pending.delete(id);
					reject(new Error(`${resource}.${method} timed out`));
				}, REQUEST_TIMEOUT_MS);
				this.pending.set(id, { resolve, reject, timer });
				const params = { resource };
				if (args) params.args = args;
				this.ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
			});
		}

		// ---- Commands -------------------------------------------------------

		toggleStreaming() { return this.request('toggleStreaming', 'StreamingService'); }
		toggleRecording() { return this.request('toggleRecording', 'StreamingService'); }
		startReplayBuffer() { return this.request('startReplayBuffer', 'StreamingService'); }
		stopReplayBuffer() { return this.request('stopReplayBuffer', 'StreamingService'); }
		saveReplay() { return this.request('saveReplay', 'StreamingService'); }

		async switchScene(sceneName) {
			const scene = this.findScene(sceneName);
			if (!scene) throw new Error('scene not found: ' + sceneName);
			await this.request('makeSceneActive', 'ScenesService', [scene.id]);
			this.setState({ activeSceneId: scene.id });
		}

		async toggleMute(sourceName) {
			const src = this.findAudio(sourceName);
			if (!src) throw new Error('audio source not found: ' + sourceName);
			const muted = !src.muted;
			await this.request('setMuted', src.resourceId, [muted]);
			this.setState({ audio: this.state.audio.map((a) => (a === src ? Object.assign({}, a, { muted }) : a)) });
		}

		findScene(name) {
			return findByName(this.state.scenes, name);
		}

		findAudio(name) {
			return findByName(this.state.audio, name);
		}
	}

	function findByName(list, name) {
		if (!name) return null;
		return list.find((x) => x.name === name) ||
			list.find((x) => x.name.toLowerCase() === String(name).toLowerCase()) || null;
	}

	root.StreamlabsClient = StreamlabsClient;
})(globalThis);
