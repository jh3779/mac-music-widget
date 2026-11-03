/* Shared by the isolated content script and extension background page. */
globalThis.MacMusicWidgetMedia = Object.freeze({
  timing(input) {
    const maximum = 365 * 24 * 60 * 60;
    const live = input.isLive === true || input.duration === Infinity;
    const duration = !live && Number.isFinite(input.duration) && input.duration > 0 && input.duration <= maximum ? input.duration : 0;
    const position = Number.isFinite(input.currentTime) ? Math.min(maximum, Math.max(0, input.currentTime)) : 0;
    const rate = Number.isFinite(input.playbackRate) && input.playbackRate >= 0 && input.playbackRate <= 16 ? input.playbackRate : 1;
    return { elapsed: duration > 0 ? Math.min(duration, position) : position, duration, playbackRate: rate,
      isAdvancing: !input.paused && !input.ended && !input.seeking && input.readyState >= 3 && rate > 0, isLive: live };
  },
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
    return { ...this.timing(input), version: 1, source: 'youtubeMusic', title,
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
      ...this.timing(input), version: 1, videoID: id, title,
      author: String(input.author || '').trim().slice(0, 256),
      isPlaying: !input.paused && !input.ended,
      canGoNext: !!input.canGoNext, canGoPrevious: !!input.canGoPrevious
    };
  }
});
