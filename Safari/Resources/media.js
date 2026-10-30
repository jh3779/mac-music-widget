/* Shared by the isolated content script and extension background page. */
globalThis.MediaMetadata = Object.freeze({
  videoID(rawURL) {
    try {
      const url = new URL(rawURL);
      if (url.protocol !== 'https:' || url.hostname !== 'www.youtube.com' || url.port || url.pathname !== '/watch') return null;
      const id = url.searchParams.get('v');
      return /^[A-Za-z0-9_-]{11}$/.test(id || '') ? id : null;
    } catch { return null; }
  },
  snapshot(input) {
    const id = this.videoID(input.url);
    if (!id || id !== input.pageVideoID || input.ad || input.readyState < 1) return null;
    const title = String(input.title || '').trim().slice(0, 512);
    if (!title) return null;
    return {
      version: 1, videoID: id, title,
      author: String(input.author || '').trim().slice(0, 256),
      isPlaying: !input.paused && !input.ended,
      canGoNext: !!input.canGoNext, canGoPrevious: !!input.canGoPrevious
    };
  }
});
