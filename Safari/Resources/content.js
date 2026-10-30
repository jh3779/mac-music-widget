(() => {
  const documentID = crypto.randomUUID();
  let lastSignature = '';
  let lastCommandID = '';
  const enabled = button => !!button && !button.disabled && button.getAttribute('aria-disabled') !== 'true' && button.getClientRects().length > 0;
  let lastSentAt = 0;
  let scheduled;
  let navigating = false;
  function read() {
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
    if (message?.kind !== 'command' || !command || command.documentID !== documentID ||
        command.videoID !== MediaMetadata.videoID(location.href) || command.id === lastCommandID) return { ok: false };
    const snapshot = read();
    if (!snapshot) return { ok: false };
    lastCommandID = command.id;
    const player = document.querySelector('#movie_player');
    const video = player?.querySelector('video');
    try {
      if (command.action === 'playPause') {
        if (video.paused) await video.play(); else video.pause();
      } else if (command.action === 'pause') {
        video.pause();
      } else {
        const selector = { next: '.ytp-next-button', previous: '.ytp-prev-button' }[command.action];
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
