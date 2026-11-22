/**
 * Phoenix Remote — Node.js entry point (Stream Deck runs this with its bundled Node 20).
 *
 * Stream Deck starts the plugin as:
 *   node main.js -port <n> -pluginUUID <id> -registerEvent <event> -info <json>
 */
'use strict';

if (typeof globalThis.WebSocket === 'undefined') globalThis.WebSocket = require('./ws.js');
globalThis.PhoenixIcons = require('./icons.js');
require('./streamlabs.js'); // defines globalThis.StreamlabsClient
globalThis.SonarClient = require('./sonar.js');

const plugin = require('./plugin.js');

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length - 1; i += 2) args[argv[i].replace(/^-+/, '')] = argv[i + 1];

process.on('uncaughtException', (e) => plugin.log('uncaught: ' + (e && e.stack || e)));
process.on('unhandledRejection', (e) => plugin.log('unhandled: ' + (e && e.stack || e)));

plugin.connectElgatoStreamDeckSocket(args.port, args.pluginUUID, args.registerEvent, args.info);
