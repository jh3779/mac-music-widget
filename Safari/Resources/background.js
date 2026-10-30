// Serialize native requests so a late heartbeat cannot resurrect a closed tab.
let pending = Promise.resolve();
function native(message) {
  const request = pending.then(() => browser.runtime.sendNativeMessage('com.jh3779.macmusicwidget', message));
  pending = request.catch(() => {});
  return request.catch(() => ({ ok: false, error: 'Native bridge unavailable. Check app signing and App Group settings.' }));
}
browser.runtime.onMessage.addListener((message, sender) => {
  if (message?.kind === 'status' && !sender.tab) return native({ kind: 'ping', version: 1 });
  if (message?.kind !== 'snapshot' || !sender.tab || sender.tab.incognito || sender.frameId !== 0 ||
      !Number.isSafeInteger(sender.tab.id) || sender.tab.id < 0) return Promise.resolve({ ok: false });
  // Check Safari-provided sender origin, never a URL supplied by the webpage.
  let url;
  try { url = new URL(sender.url); } catch { return Promise.resolve({ ok: false }); }
  if (url.origin !== 'https://www.youtube.com') return Promise.resolve({ ok: false });
  const tabID = sender.tab.id;
  if (message.snapshot === null) return native({ kind: 'clear', version: 1, tabID });
  const value = message.snapshot;
  if (!value || value.videoID !== MediaMetadata.videoID(sender.url) ||
      typeof value.documentID !== 'string' || !/^[0-9a-f-]{36}$/i.test(value.documentID) ||
      typeof value.canGoNext !== 'boolean' || typeof value.canGoPrevious !== 'boolean' ||
      typeof value.title !== 'string' || typeof value.author !== 'string' || typeof value.isPlaying !== 'boolean') {
    return Promise.resolve({ ok: false });
  }
  return native({ kind: 'snapshot', version: 1, tabID, videoID: value.videoID,
    documentID: value.documentID, canGoNext: value.canGoNext, canGoPrevious: value.canGoPrevious,
    title: value.title.slice(0, 512), author: value.author.slice(0, 256), isPlaying: value.isPlaying
  }).then(async response => {
    if (response?.command) {
      try { await browser.tabs.sendMessage(tabID, { kind: 'command', command: response.command }); }
      catch { /* A closed/navigated tab must not replay the command elsewhere. */ }
    }
    return response;
  });
});
browser.tabs.onRemoved.addListener(tabID => { void native({ kind: 'clear', version: 1, tabID }); });
// A navigation away from YouTube may not deliver pagehide. Clear on URL change too.
browser.tabs.onUpdated.addListener((tabID, change) => {
  if (change.url) void native({ kind: 'clear', version: 1, tabID });
});
