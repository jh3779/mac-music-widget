(() => {
  const documentID = crypto.randomUUID();
  let musicKey = '';
  let musicID = '';
  let lastSignature = '';
  let lastCommandID = '';
  const enabled = button => !!button && !button.disabled && button.getAttribute('aria-disabled') !== 'true' && button.getClientRects().length > 0;
  let lastSentAt = 0;
  let scheduled;
  let navigating = false;
  function read() {
    if (MediaMetadata.isMusicURL(location.href)) {
      const bar = document.querySelector('ytmusic-player-bar');
      const video = document.querySelector('video');
      const player = document.querySelector('#movie_player');
      if (!bar || !video) return null;
      const snapshot = MediaMetadata.musicSnapshot({ url: location.href,
        title: bar.querySelector('.title')?.textContent, author: bar.querySelector('.byline')?.textContent,
        artworkURL: bar.querySelector('img')?.src, paused: video.paused, ended: video.ended,
        readyState: video.readyState, ad: !!player?.classList.contains('ad-showing'),
        canGoNext: enabled(bar.querySelector('.next-button')), canGoPrevious: enabled(bar.querySelector('.previous-button')) });
      if (!snapshot) return null;
      const key = JSON.stringify([snapshot.title, snapshot.author, snapshot.artworkURL]);
      if (key !== musicKey) { musicKey = key; musicID = crypto.randomUUID(); }
      return { ...snapshot, videoID: musicID };
    }
    const page = document.querySelector('ytd-watch-flexy');
    const player = document.querySelector('#movie_player');
    const video = player?.querySelector('video');
    if (navigating || !page || !video) return null;
    return MediaMetadata.snapshot({
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
    const snapshot = read();
    const signature = JSON.stringify(snapshot);
    if (!force && signature === lastSignature && Date.now() - lastSentAt < 2000) return;
    lastSignature = signature;
    lastSentAt = Date.now();
    try {
      const response = await browser.runtime.sendMessage({ kind: 'snapshot', snapshot: snapshot ? { ...snapshot, documentID } : null });
      if (!response?.ok) lastSignature = ''; // Retry on the next observation/heartbeat.
    } catch { lastSignature = ''; }
  }
  function schedule() {
    if (scheduled) return;
    scheduled = setTimeout(() => { scheduled = undefined; void publish(); }, 250);
  }
  for (const event of ['play', 'pause', 'ended', 'loadedmetadata', 'emptied']) {
    document.addEventListener(event, schedule, true);
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
    const video = isMusic ? document.querySelector('video') : player?.querySelector('video');
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
