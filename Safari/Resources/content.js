(() => {
  const documentID = crypto.randomUUID();
  let musicKey = '';
  let musicID = '';
  let musicVideo;
  let musicSource = '';
  let musicGeneration = 0;
  let musicLoading = false;
  let lastSignature = '';
  let lastCommandID = '';
  const enabled = button => !!button && !button.disabled && button.getAttribute('aria-disabled') !== 'true' && button.getClientRects().length > 0;
  let lastSentAt = 0;
  let scheduled;
  let navigating = false;
  let readNote = '';
  function observeMusicResource(video) {
    const source = video.currentSrc || '';
    if (video === musicVideo && source === musicSource) return false;
    musicVideo = video;
    musicSource = source;
    musicGeneration++;
    return true;
  }
  function read() {
    readNote = '';
    if (MacMusicWidgetMedia.isMusicURL(location.href)) {
      const bar = document.querySelector('ytmusic-player-bar');
      const player = document.querySelector('#movie_player');
      const video = player?.querySelector('video');
      if (!bar || !video) { readNote = 'Music player not found'; return null; }
      // A track's DOM title can lag behind its actual media resource. Commands
      // must notice a new element/source even before the next published snapshot.
      observeMusicResource(video);
      const snapshot = MacMusicWidgetMedia.musicSnapshot({ url: location.href,
        title: bar.querySelector('.title')?.textContent, author: bar.querySelector('.byline')?.textContent,
        artworkURL: bar.querySelector('img')?.src, paused: video.paused, ended: video.ended,
        readyState: video.readyState, ad: !!player?.classList.contains('ad-showing'),
        canGoNext: enabled(bar.querySelector('.next-button')), canGoPrevious: enabled(bar.querySelector('.previous-button')) });
      if (!snapshot) { readNote = `Music metadata unavailable (ready=${video.readyState})`; return null; }
      musicLoading = false;
      const key = JSON.stringify([musicGeneration, musicSource, snapshot.title, snapshot.author, snapshot.artworkURL]);
      if (key !== musicKey) { musicKey = key; musicID = crypto.randomUUID(); }
      return { ...snapshot, videoID: musicID };
    }
    const page = document.querySelector('ytd-watch-flexy');
    const player = document.querySelector('#movie_player');
    const video = player?.querySelector('video');
    if (navigating || !page || !video) { readNote = 'Open a regular YouTube watch page'; return null; }
    return MacMusicWidgetMedia.snapshot({
      url: location.href,
      pageVideoID: page.getAttribute('video-id'),
      title: page.querySelector('#title h1, h1.ytd-watch-metadata')?.textContent,
      author: page.querySelector('#owner #channel-name a')?.textContent,
      paused: video.paused, ended: video.ended, readyState: video.readyState,
      canGoNext: enabled(player.querySelector('.ytp-next-button')),
      canGoPrevious: enabled(player.querySelector('.ytp-prev-button')),
      ad: player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting')
    });
  }
  async function publish(force = false) {
    let snapshot = null;
    try { snapshot = read(); } catch { readNote = 'Page adapter could not read the player'; }
    const signature = JSON.stringify(snapshot);
    if (!force && signature === lastSignature && Date.now() - lastSentAt < 2000) return;
    lastSignature = signature;
    lastSentAt = Date.now();
    try {
      const response = await browser.runtime.sendMessage({ kind: 'snapshot', snapshot: snapshot ? { ...snapshot, documentID } : null, diagnostic: readNote });
      if (!response?.ok) lastSignature = ''; // Retry on the next observation/heartbeat.
    } catch { lastSignature = ''; }
  }
  function schedule() {
    if (scheduled) return;
    scheduled = setTimeout(() => { scheduled = undefined; void publish(); }, 250);
  }
  function mediaEvent(event) {
    if (MacMusicWidgetMedia.isMusicURL(location.href)) {
      const video = document.querySelector('#movie_player')?.querySelector('video');
      // Preview videos elsewhere on the page must not change this track's target.
      if (!video || event.target !== video) return;
      if (event.type === 'emptied' || event.type === 'loadedmetadata') {
        const changed = observeMusicResource(video);
        // Some players reuse a MediaSource Blob URL. Invalidate that generation
        // too, grouping an emptied/loadedmetadata pair as one reload cycle.
        if (!changed && !musicLoading) musicGeneration++;
        musicLoading = event.type === 'emptied';
      }
    }
    schedule();
  }
  for (const event of ['play', 'pause', 'ended', 'loadedmetadata', 'emptied']) {
    document.addEventListener(event, mediaEvent, true);
  }
  document.addEventListener('yt-navigate-start', () => { navigating = true; void publish(true); });
  document.addEventListener('yt-navigate-finish', () => { navigating = false; schedule(); });
  window.addEventListener('pagehide', () => {
    void browser.runtime.sendMessage({ kind: 'snapshot', snapshot: null }).catch(() => {});
  });
  new MutationObserver(schedule).observe(document.documentElement, {
    subtree: true, childList: true, characterData: true, attributes: true,
    attributeFilter: ['video-id', 'class']
  });
  browser.runtime.onMessage.addListener(async message => {
    const command = message?.command;
    const snapshot = read();
    if (message?.kind !== 'command' || !command || command.documentID !== documentID ||
        !snapshot || command.videoID !== snapshot.videoID || command.id === lastCommandID ||
        !Number.isFinite(command.expiresAt) || Date.now() / 1000 >= command.expiresAt) return { ok: false };
    lastCommandID = command.id;
    const isMusic = snapshot.source === 'youtubeMusic';
    const player = document.querySelector(isMusic ? 'ytmusic-player-bar' : '#movie_player');
    const video = isMusic ? document.querySelector('#movie_player')?.querySelector('video') : player?.querySelector('video');
    try {
      if (command.action === 'playPause') {
        if (video.paused) await video.play(); else video.pause();
      } else if (command.action === 'pause') {
        video.pause();
      } else {
        const selector = (isMusic ? { next: '.next-button', previous: '.previous-button' } : { next: '.ytp-next-button', previous: '.ytp-prev-button' })[command.action];
        const button = selector && player.querySelector(selector);
        if (!enabled(button)) return { ok: false };
        button.click();
      }
      schedule();
      return { ok: true };
    } catch { return { ok: false }; } // Safari autoplay policy still applies.
  });
  setInterval(() => { void publish(); }, 2000);
  void publish(true);
})();
