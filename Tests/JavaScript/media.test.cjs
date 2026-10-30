const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
function api() {
  const context = vm.createContext({ URL });
  vm.runInContext(fs.readFileSync('Safari/Resources/media.js', 'utf8'), context, { filename: require('node:path').resolve('Safari/Resources/media.js') });
  return context.MacMusicWidgetMedia;
}
test('the helper does not replace the browser MediaMetadata API', () => {
  const original = class MediaMetadata {};
  const context = vm.createContext({ URL, MediaMetadata: original });
  vm.runInContext(fs.readFileSync('Safari/Resources/media.js', 'utf8'), context);
  assert.equal(context.MediaMetadata, original);
  assert.equal(typeof context.MacMusicWidgetMedia.musicSnapshot, 'function');
});
test('only regular YouTube watch URLs are eligible', () => {
  const m = api();
  assert.equal(m.videoID('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
  for (const url of ['https://music.youtube.com/watch?v=dQw4w9WgXcQ', 'https://www.youtube.com.evil.test/watch?v=dQw4w9WgXcQ', 'http://www.youtube.com/watch?v=dQw4w9WgXcQ', 'https://www.youtube.com/shorts/dQw4w9WgXcQ', 'garbage']) assert.equal(m.videoID(url), null);
});
test('snapshot carries bounded metadata and real play/pause state', () => {
  const m = api();
  const input = { url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', pageVideoID: 'dQw4w9WgXcQ', title: ' Example ', author: 'Channel', paused: false, ended: false, readyState: 4, ad: false };
  assert.equal(m.snapshot(input).isPlaying, true);
  assert.equal(m.snapshot({ ...input, paused: true }).isPlaying, false);
  assert.equal(m.snapshot({ ...input, ended: true }).isPlaying, false);
  assert.equal(m.snapshot({ ...input, ad: true }), null);
  assert.equal(m.snapshot({ ...input, pageVideoID: 'abcdefghijk' }), null);
  assert.equal(m.snapshot({ ...input, title: '' }), null);
  assert.equal(m.snapshot({ ...input, readyState: 0 }), null);
  assert.equal(m.snapshot({ ...input, title: 'x'.repeat(900) }).title.length, 512);
});
test('Instagram posts, reels, embeds and subdomains are explicitly excluded', () => {
  const m = api();
  for (const url of [
    'https://www.instagram.com/reel/ABC123/', 'https://instagram.com/p/ABC123/',
    'https://www.instagram.com/p/ABC123/embed/', 'https://m.instagram.com/reels/',
    'https://www.instagram.com/watch?v=dQw4w9WgXcQ'
  ]) assert.equal(m.videoID(url), null);
  const manifest = JSON.parse(fs.readFileSync('Safari/Resources/manifest.json', 'utf8'));
  assert.deepEqual(manifest.content_scripts[0].matches, ['https://www.youtube.com/*', 'https://music.youtube.com/*']);
  assert.equal(manifest.content_scripts[0].all_frames, false);
  assert.ok(!manifest.permissions.some(value => value.includes('instagram') || value === '<all_urls>'));
});
test('YouTube Music metadata works without a watch URL and only accepts Google artwork', () => {
  const m = api();
  const input = { url: 'https://music.youtube.com/', title: 'Song', author: 'Artist • Album', artworkURL: 'https://lh3.googleusercontent.com/example=w60-h60', paused: false, ended: false, readyState: 4, ad: false, canGoNext: true };
  const found = m.musicSnapshot(input);
  assert.equal(found.source, 'youtubeMusic');
  assert.equal(found.title, 'Song');
  assert.equal(found.author, 'Artist');
  assert.equal(found.isPlaying, true);
  assert.match(found.artworkURL, /w544/);
  assert.equal(m.musicSnapshot({ ...input, ad: true }), null);
  assert.equal(m.musicSnapshot({ ...input, url: 'https://www.instagram.com/' }), null);
  for (const artworkURL of ['http://lh3.googleusercontent.com/a', 'https://evilgoogleusercontent.com/a', 'https://instagram.com/a']) {
    assert.equal(m.musicSnapshot({ ...input, artworkURL }).artworkURL, '');
  }
});
