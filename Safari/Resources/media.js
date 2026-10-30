/* Shared by the isolated content script and extension background page. */
globalThis.MediaMetadata = Object.freeze({
  isMusicURL(rawURL) {
    try { return new URL(rawURL).origin === 'https://music.youtube.com'; } catch { return false; }
  },
  musicSnapshot(input) {
    if (!this.isMusicURL(input.url) || input.ad || input.readyState < 1) return null;
    const title = String(input.title || '').trim().slice(0, 512);
    if (!title) return null;
    let artworkURL = '';
    try {
      const url = new URL(input.artworkURL);
      if (url.protocol === 'https:' && !url.username && !url.password && !url.port &&
          ['googleusercontent.com', 'ytimg.com'].some(host => url.hostname === host || url.hostname.endsWith('.' + host))) {
        artworkURL = url.href.replace(/=w[^?]*$/, '=w544-h544-l90-rj');
      }
    } catch {}
    return { version: 1, source: 'youtubeMusic', title,
      author: String(input.author || '').split('•')[0].trim().slice(0, 256), artworkURL,
      isPlaying: !input.paused && !input.ended, canGoNext: !!input.canGoNext, canGoPrevious: !!input.canGoPrevious };
  },
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
