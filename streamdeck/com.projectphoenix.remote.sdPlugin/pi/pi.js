/**
 * Phoenix Remote — property inspector.
 *
 * Builds the per-action fields (scene / audio source pickers, hold-to-confirm)
 * and the shared Streamlabs connection fields stored in global settings.
 */
'use strict';

const PREFIX = 'com.projectphoenix.remote.';

let sd = null;
let uuid = '';
let actionUUID = '';
let action = '';
let settings = {};
let globals = {};
let lists = { conn: 'connecting', scenes: [], audio: [] };

const $ = (id) => document.getElementById(id);

// eslint-disable-next-line no-unused-vars
function connectElgatoStreamDeckSocket(inPort, inUUID, inRegisterEvent, inInfo, inActionInfo) {
	uuid = inUUID;
	const info = JSON.parse(inActionInfo);
	actionUUID = info.action;
	action = actionUUID.replace(PREFIX, '');
	settings = (info.payload && info.payload.settings) || {};

	sd = new WebSocket('ws://127.0.0.1:' + inPort);
	sd.onopen = () => {
		send({ event: inRegisterEvent, uuid });
		send({ event: 'getGlobalSettings', context: uuid });
		toPlugin({ cmd: 'hello' });
	};
	sd.onmessage = (e) => {
		const msg = JSON.parse(e.data);
		if (msg.event === 'didReceiveGlobalSettings') {
			globals = (msg.payload && msg.payload.settings) || {};
			fillConnection();
		} else if (msg.event === 'sendToPropertyInspector') {
			lists = msg.payload || lists;
			buildAction();
			showStatus();
		} else if (msg.event === 'didReceiveSettings') {
			settings = (msg.payload && msg.payload.settings) || {};
			buildAction();
		}
	};
	buildAction();
	showStatus();
}

function send(obj) {
	if (sd && sd.readyState === WebSocket.OPEN) sd.send(JSON.stringify(obj));
}

function toPlugin(payload) {
	send({ event: 'sendToPlugin', action: actionUUID, context: uuid, payload });
}

function saveSettings() {
	send({ event: 'setSettings', context: uuid, payload: settings });
}

// ---- Connection (global) ----------------------------------------------------

function fillConnection() {
	$('host').value = globals.host || '';
	$('port').value = globals.port || '';
	$('token').value = '';
	$('token').placeholder = globals.token ? 'Saved — paste a new one to replace' : 'Paste from Streamlabs → Settings → Remote Control';
	// Open the connection section until a token has been saved.
	$('connection').open = !globals.token;
}

$('save').addEventListener('click', () => {
	const next = Object.assign({}, globals, {
		host: $('host').value.trim() || '192.168.1.119',
		port: Number($('port').value) || 59650
	});
	const token = $('token').value.trim();
	if (token) next.token = token;
	globals = next;
	send({ event: 'setGlobalSettings', context: uuid, payload: globals });
	toPlugin({ cmd: 'globalsChanged' });
	fillConnection();
});

const STATUS_TEXT = {
	connected: 'Connected to Streamlabs',
	connecting: 'Connecting…',
	'auth-failed': 'Streamlabs rejected the token — paste it again',
	unconfigured: 'Enter the Streamlabs token below',
	disconnected: 'Can’t reach the Streaming PC'
};

function showStatus() {
	$('status').textContent = STATUS_TEXT[lists.conn] || lists.conn;
	$('status').className = 'status ' + lists.conn;
	$('status-dot').className = 'dot ' + lists.conn;
}

// ---- Per-action fields ------------------------------------------------------

function buildAction() {
	const box = $('action-section');
	box.innerHTML = '';
	if (action === 'scene') {
		box.appendChild(picker('Scene', 'sceneName', lists.scenes));
		box.appendChild(textField('Key label', 'label', 'Defaults to the scene name'));
	} else if (action === 'mute') {
		box.appendChild(picker('Audio source', 'sourceName', lists.audio));
		box.appendChild(textField('Key label', 'label', 'e.g. MIC'));
		box.appendChild(select('Icon', 'kind', [['mic', 'Microphone'], ['speaker', 'Speaker']], settings.kind || 'mic'));
	} else if (action === 'stream') {
		const row = document.createElement('div');
		row.className = 'row';
		row.innerHTML = '<label for="hold">Safety</label><label class="check"><input id="hold" type="checkbox" /> Press and hold to go live / end</label>';
		box.appendChild(row);
		const cb = row.querySelector('#hold');
		cb.checked = settings.requireHold !== false;
		cb.addEventListener('change', () => { settings.requireHold = cb.checked; saveSettings(); });
	}
}

function picker(labelText, key, options) {
	const current = settings[key] || '';
	const opts = options.map((n) => [n, n]);
	if (current && !options.includes(current)) opts.unshift([current, current + ' (not found)']);
	if (!opts.length) opts.push(['', lists.conn === 'connected' ? 'None found' : 'Connect to load list']);
	return select(labelText, key, opts, current);
}

function select(labelText, key, opts, current) {
	const row = document.createElement('div');
	row.className = 'row';
	const label = document.createElement('label');
	label.textContent = labelText;
	const sel = document.createElement('select');
	for (const [value, text] of opts) {
		const o = document.createElement('option');
		o.value = value;
		o.textContent = text;
		if (value === current) o.selected = true;
		sel.appendChild(o);
	}
	if (!current && opts.length && opts[0][0]) {
		settings[key] = opts[0][0];
		saveSettings();
	}
	sel.addEventListener('change', () => { settings[key] = sel.value; saveSettings(); });
	row.append(label, sel);
	return row;
}

function textField(labelText, key, placeholder) {
	const row = document.createElement('div');
	row.className = 'row';
	const label = document.createElement('label');
	label.textContent = labelText;
	const input = document.createElement('input');
	input.type = 'text';
	input.placeholder = placeholder;
	input.value = settings[key] || '';
	input.addEventListener('change', () => { settings[key] = input.value.trim(); saveSettings(); });
	row.append(label, input);
	return row;
}
