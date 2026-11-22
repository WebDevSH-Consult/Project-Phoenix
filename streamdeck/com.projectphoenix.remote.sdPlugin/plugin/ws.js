/**
 * Phoenix Remote — minimal WebSocket client for Node.
 *
 * Stream Deck runs plugins on Node 20, which has no global WebSocket. This is
 * just enough of the browser API (onopen / onmessage / onerror / onclose,
 * send, close, readyState) for the Stream Deck socket and Streamlabs' raw
 * SockJS endpoint: plain ws://, text frames, fragmentation, ping/pong.
 */
'use strict';

const net = require('net');
const crypto = require('crypto');

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const HANDSHAKE_TIMEOUT_MS = 10000;

class NodeWebSocket {
	constructor(url) {
		const u = new URL(url);
		if (u.protocol !== 'ws:') throw new Error('only ws:// is supported');
		this.url = url;
		this.readyState = NodeWebSocket.CONNECTING;
		this.onopen = this.onmessage = this.onerror = this.onclose = null;
		this._buf = Buffer.alloc(0);
		this._frag = null;
		this._fragOp = 0;
		this._closed = false;

		const key = crypto.randomBytes(16).toString('base64');
		this._accept = crypto.createHash('sha1').update(key + GUID).digest('base64');

		const sock = net.connect({ host: u.hostname, port: Number(u.port) || 80 });
		this._sock = sock;
		sock.setNoDelay(true);
		sock.setTimeout(HANDSHAKE_TIMEOUT_MS, () => sock.destroy(new Error('handshake timed out')));
		sock.on('connect', () => {
			sock.write(
				`GET ${u.pathname}${u.search} HTTP/1.1\r\n` +
				`Host: ${u.host}\r\n` +
				'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
				`Sec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`
			);
		});
		sock.on('data', (d) => this._onData(d));
		sock.on('error', (e) => this._fire('onerror', { message: e.message }));
		sock.on('close', () => this._finish());
	}

	send(data) {
		if (this.readyState !== NodeWebSocket.OPEN) throw new Error('WebSocket is not open');
		this._frame(0x1, Buffer.from(String(data), 'utf8'));
	}

	close() {
		if (this.readyState >= NodeWebSocket.CLOSING) return;
		this.readyState = NodeWebSocket.CLOSING;
		try { this._frame(0x8, Buffer.from([0x03, 0xe8])); } catch (e) { /* socket already gone */ }
		this._sock.end();
		setTimeout(() => this._sock.destroy(), 1000).unref();
	}

	_onData(chunk) {
		this._buf = Buffer.concat([this._buf, chunk]);
		if (this.readyState === NodeWebSocket.CONNECTING) {
			const end = this._buf.indexOf('\r\n\r\n');
			if (end < 0) return;
			const head = this._buf.subarray(0, end).toString('latin1');
			this._buf = this._buf.subarray(end + 4);
			const accept = /sec-websocket-accept:\s*(\S+)/i.exec(head);
			if (!/^HTTP\/1\.1 101/.test(head) || !accept || accept[1] !== this._accept) {
				this._sock.destroy(new Error('WebSocket upgrade refused'));
				return;
			}
			this._sock.setTimeout(0);
			this.readyState = NodeWebSocket.OPEN;
			this._fire('onopen', {});
		}
		this._parse();
	}

	_parse() {
		for (;;) {
			const b = this._buf;
			if (b.length < 2) return;
			const fin = (b[0] & 0x80) !== 0;
			const op = b[0] & 0x0f;
			const masked = (b[1] & 0x80) !== 0;
			let len = b[1] & 0x7f;
			let off = 2;
			if (len === 126) {
				if (b.length < 4) return;
				len = b.readUInt16BE(2);
				off = 4;
			} else if (len === 127) {
				if (b.length < 10) return;
				len = Number(b.readBigUInt64BE(2));
				off = 10;
			}
			let mask = null;
			if (masked) {
				if (b.length < off + 4) return;
				mask = b.subarray(off, off + 4);
				off += 4;
			}
			if (b.length < off + len) return;
			let payload = Buffer.from(b.subarray(off, off + len));
			if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
			this._buf = b.subarray(off + len);

			if (op === 0x8) { // close
				if (this.readyState === NodeWebSocket.OPEN) {
					this.readyState = NodeWebSocket.CLOSING;
					try { this._frame(0x8, payload.subarray(0, 2)); } catch (e) { /* ignore */ }
				}
				this._sock.end();
				return;
			}
			if (op === 0x9) { this._frame(0xA, payload); continue; } // ping -> pong
			if (op === 0xA) continue; // pong
			if (op === 0x1 || op === 0x2) {
				this._frag = [payload];
				this._fragOp = op;
			} else if (op === 0x0 && this._frag) {
				this._frag.push(payload);
			} else {
				continue;
			}
			if (fin) {
				const data = Buffer.concat(this._frag);
				this._frag = null;
				this._fire('onmessage', { data: this._fragOp === 0x1 ? data.toString('utf8') : data });
			}
		}
	}

	// Client frames must be masked (RFC 6455 §5.3).
	_frame(op, payload) {
		if (this._sock.destroyed) return;
		const len = payload.length;
		let head;
		if (len < 126) {
			head = Buffer.alloc(2);
			head[1] = 0x80 | len;
		} else if (len < 65536) {
			head = Buffer.alloc(4);
			head[1] = 0x80 | 126;
			head.writeUInt16BE(len, 2);
		} else {
			head = Buffer.alloc(10);
			head[1] = 0x80 | 127;
			head.writeBigUInt64BE(BigInt(len), 2);
		}
		head[0] = 0x80 | op;
		const mask = crypto.randomBytes(4);
		const body = Buffer.from(payload);
		for (let i = 0; i < body.length; i++) body[i] ^= mask[i & 3];
		this._sock.write(Buffer.concat([head, mask, body]));
	}

	_finish() {
		if (this._closed) return;
		this._closed = true;
		this.readyState = NodeWebSocket.CLOSED;
		this._fire('onclose', {});
	}

	_fire(name, evt) {
		const fn = this[name];
		if (typeof fn !== 'function') return;
		try { fn.call(this, evt); } catch (e) { process.emitWarning('WebSocket handler error: ' + e.message); }
	}
}

NodeWebSocket.CONNECTING = 0;
NodeWebSocket.OPEN = 1;
NodeWebSocket.CLOSING = 2;
NodeWebSocket.CLOSED = 3;

module.exports = NodeWebSocket;
