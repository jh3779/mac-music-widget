const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const documentID = '7A6341CD-1052-41CC-A8A5-F3AA4B9E2D88';
const url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
const metadata = { videoID: 'dQw4w9WgXcQ', title: 'Video', author: 'Channel', isPlaying: true, documentID, canGoNext: true, canGoPrevious: false };
const load = (name, ctx) => vm.runInContext(fs.readFileSync(`Safari/Resources/${name}.js`, 'utf8'), ctx, { filename: path.resolve('Safari/Resources/' + name + '.js') });
function background() {
  const calls = [], deliveries = [];
  let message, removed, updated, nativeResponse = { ok: true };
  const ctx = vm.createContext({ URL, browser: {
    runtime: { onMessage: { addListener(fn) { message = fn; } }, async sendNativeMessage(app, value) { calls.push(value); return nativeResponse; } },
    tabs: { onRemoved: { addListener(fn) { removed = fn; } }, onUpdated: { addListener(fn) { updated = fn; } }, async sendMessage(id, value) { deliveries.push({ id, value }); } }
  }});
  load('media', ctx); load('background', ctx);
  return { calls, deliveries, send: (value, sender = { url, frameId: 0, tab: { id: 42, incognito: false } }) => message(value, sender),
    remove: id => removed(id), update: (id, change) => updated(id, change), respond: value => { nativeResponse = value; } };
}
test('background validates origin, top frame, private mode and payload', async () => {
  const b = background();
  for (const sender of [
    { url: 'https://evil.test', frameId: 0, tab: { id: 42 } },
    { url: 'https://www.instagram.com/reel/ABC123/', frameId: 0, tab: { id: 42 } },
    { url, frameId: 1, tab: { id: 42 } },
    { url, frameId: 0, tab: { id: 42, incognito: true } },
    { url, frameId: 0, tab: { id: -1 } }, {}
  ]) assert.equal((await b.send({ kind: 'snapshot', snapshot: metadata }, sender)).ok, false);
  assert.equal((await b.send({ kind: 'snapshot', snapshot: { ...metadata, videoID: 'abcdefghijk' } })).ok, false);
  assert.equal(b.calls.length, 0);
  assert.equal((await b.send({ kind: 'snapshot', snapshot: metadata })).ok, true);
  assert.equal(b.calls[0].tabID, 42);
  assert.equal(b.calls[0].documentID, documentID);
});
test('native commands route to the reporting tab; close and navigation clear metadata', async () => {
  const b = background();
  b.respond({ ok: true, command: { action: 'pause', documentID } });
  await b.send({ kind: 'snapshot', snapshot: metadata });
  assert.equal(b.deliveries[0].id, 42);
  await b.send({ kind: 'snapshot', snapshot: null });
  b.remove(42); b.update(43, { url: 'https://example.com' });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(b.calls.slice(1).map(x => x.kind), ['clear', 'clear', 'clear']);
});
function content(music = false) {
  let listener, heartbeat;
  const events = {}, sent = [];
  const video = { paused: true, ended: false, readyState: 4, async play() { this.paused = false; }, pause() { this.paused = true; } };
  const next = { disabled: false, getAttribute() { return null; }, getClientRects() { return [1]; }, clicks: 0, click() { this.clicks++; } };
  const previous = { ...next, getClientRects() { return []; } };
  const player = { classList: { contains() { return false; } }, querySelector(selector) { return { video, '.ytp-next-button': next, '.ytp-prev-button': previous }[selector]; } };
  const page = { getAttribute() { return 'dQw4w9WgXcQ'; }, querySelector(selector) { return { textContent: selector.includes('h1') ? 'Video' : 'Channel' }; } };
  const title = { textContent: 'Song' };
  const bar = { querySelector(selector) { return { '.title': title, '.byline': { textContent: 'Artist • Album' }, img: { src: 'https://lh3.googleusercontent.com/cover=w60-h60' }, '.next-button': next, '.previous-button': previous }[selector]; } };
  const location = { href: music ? 'https://music.youtube.com/' : url };
  const unrelatedVideo = { readyState: 0, paused: true };
  let uuid = 0;
  const ctx = vm.createContext({ URL, Date, location, crypto: { randomUUID: () => uuid++ === 0 ? documentID : `00000000-0000-4000-8000-${String(uuid).padStart(12, '0')}` },
    setTimeout(fn) { return 1; }, setInterval(fn) { heartbeat = fn; },
    MutationObserver: class { observe() {} },
    window: { addEventListener(name, fn) { events[name] = fn; } },
    document: { documentElement: {}, querySelector(selector) { return { 'ytd-watch-flexy': page, '#movie_player': player, 'ytmusic-player-bar': bar, video: music ? unrelatedVideo : video }[selector]; }, addEventListener(name, fn) { events[name] = fn; } },
    browser: { runtime: { async sendMessage(value) { sent.push(value); return { ok: true }; }, onMessage: { addListener(fn) { listener = fn; } } } }
  });
  load('media', ctx); load('content', ctx);
  const command = (action, overrides = {}) => listener({ kind: 'command', command: { id: Math.random().toString(), action, videoID: sent[0].snapshot.videoID, documentID, expiresAt: Date.now() / 1000 + 8, ...overrides } });
  return { command, video, next, previous, title, events, sent, location, heartbeat: () => heartbeat() };
}
test('YouTube Music publishes without a watch URL, routes controls and rejects an old song target', async () => {
  const c = content(true);
  const snapshot = c.sent[0].snapshot;
  assert.equal(snapshot.source, 'youtubeMusic');
  assert.equal(snapshot.title, 'Song');
  assert.equal(snapshot.author, 'Artist');
  assert.match(snapshot.artworkURL, /^https:\/\/lh3.googleusercontent.com\//);
  assert.equal((await c.command('playPause')).ok, true);
  assert.equal(c.video.paused, false);
  assert.equal((await c.command('next')).ok, true);
  assert.equal(c.next.clicks, 1);
  assert.equal((await c.command('previous')).ok, false);
  c.title.textContent = 'Another song';
  assert.equal((await c.command('pause')).ok, false);
  assert.equal(c.video.paused, false);
  c.heartbeat();
  const changed = c.sent.at(-1).snapshot;
  assert.notEqual(changed.videoID, snapshot.videoID);
  assert.equal((await c.command('pause', { videoID: changed.videoID })).ok, true);
});
test('background requires Music identity on the exact Music origin and preserves artwork', async () => {
  const b = background();
  const sender = { url: 'https://music.youtube.com/', frameId: 0, tab: { id: 42, incognito: false } };
  const snapshot = { ...metadata, source: 'youtubeMusic', videoID: documentID, artworkURL: 'https://lh3.googleusercontent.com/cover' };
  assert.equal((await b.send({ kind: 'snapshot', snapshot: metadata }, sender)).ok, false);
  assert.equal((await b.send({ kind: 'snapshot', snapshot })).ok, false);
  assert.equal((await b.send({ kind: 'snapshot', snapshot }, sender)).ok, true);
  assert.equal(b.calls[0].source, 'youtubeMusic');
  assert.equal(b.calls[0].artworkURL, snapshot.artworkURL);
});
test('content publishes a thumbnail identity without embedding or fetching video', () => {
  const c = content();
  assert.equal(c.sent[0].snapshot.videoID, metadata.videoID);
  assert.equal(c.sent[0].snapshot.documentID, documentID);
  assert.equal(c.sent[0].snapshot.canGoNext, true);
  assert.equal(c.sent[0].snapshot.canGoPrevious, false);
});
test('play/pause controls only the matching document and video; duplicate commands are ignored', async () => {
  const c = content();
  assert.equal((await c.command('playPause', { documentID: 'wrong' })).ok, false);
  assert.equal((await c.command('playPause', { videoID: 'abcdefghijk' })).ok, false);
  assert.equal(c.video.paused, true);
  assert.equal((await c.command('playPause', { id: 'once' })).ok, true);
  assert.equal(c.video.paused, false);
  assert.equal((await c.command('playPause', { id: 'once' })).ok, false);
  assert.equal(c.video.paused, false);
  await c.command('pause'); assert.equal(c.video.paused, true);
  await c.command('playPause'); await c.command('playPause'); assert.equal(c.video.paused, true);
});
test('next/previous follow actual enabled YouTube buttons; navigation clears and rejects commands', async () => {
  const c = content();
  assert.equal((await c.command('next')).ok, true); assert.equal(c.next.clicks, 1);
  assert.equal((await c.command('previous')).ok, false);
  c.events['yt-navigate-start']();
  assert.equal(c.sent.at(-1).snapshot, null);
  assert.equal((await c.command('playPause')).ok, false);
  c.events['yt-navigate-finish'](); c.events.pagehide();
  assert.equal(c.sent.at(-1).snapshot, null);
});
test('Safari autoplay rejection returns failure instead of pretending playback succeeded', async () => {
  const c = content(); c.video.play = async () => { throw new Error('NotAllowedError'); };
  assert.equal((await c.command('playPause')).ok, false);
  assert.equal(c.video.paused, true);
});

test('commands that expire while the Safari page is suspended are rejected', async () => {
  const c = content();
  assert.equal((await c.command('playPause', { expiresAt: Date.now() / 1000 - 1 })).ok, false);
  assert.equal(c.video.paused, true);
});
test('popup reports native bridge success, error and connection failure', async () => {
  for (const outcome of [{ ok: true }, { ok: false, error: 'Group unavailable' }, new Error('Disconnected')]) {
    const status = { textContent: '' };
    const ctx = vm.createContext({ document: { getElementById() { return status; } }, browser: { runtime: {
      async sendMessage() { if (outcome instanceof Error) throw outcome; return outcome; }
    } } });
    load('popup', ctx);
    await new Promise(resolve => setImmediate(resolve));
    assert.match(status.textContent, outcome.ok ? /ready/ : outcome instanceof Error ? /unavailable/ : /Group unavailable/);
  }
});
