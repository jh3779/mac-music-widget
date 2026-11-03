const messages = {
  ready: '재생 정보 수신 중입니다. 위젯에서 제목·채널/아티스트를 확인하세요.',
  waitingForMedia: 'Safari 연결은 확인했습니다. YouTube 또는 YouTube Music에서 미디어를 재생해 주세요.',
  reconnectPage: 'Safari 연결은 확인했습니다. 재생 탭을 새로고침하고 사이트 접근 허용을 확인하세요.',
  extensionNotConnected: 'Safari 확장 연결과 사이트 접근 허용을 확인하세요.',
  updatesDelayed: '최근 재생 정보를 받지 못했습니다. 재생 탭을 새로고침해 주세요.',
  configurationRequired: '앱과 Safari 확장의 App Group·서명 설정을 확인하세요.'
};
browser.runtime.sendMessage({ kind: 'status' }).then(response => {
  document.getElementById('status').textContent = messages[response?.connectionState] ||
    (response?.ok ? messages.reconnectPage : response?.error || 'Safari 네이티브 연결을 확인할 수 없습니다. 앱 설치와 서명을 확인하세요.');
  for (const [id, value, action] of [['app', response?.appURL, 'open'], ['settings', response?.settingsURL, 'safari-settings']]) {
    // Native supplies URLs for the containing app. Only the fixed recovery route is allowed.
    if (typeof value !== 'string' || !new RegExp('^[A-Za-z][A-Za-z0-9+.-]*://' + action + '$').test(value)) continue;
    const link = document.getElementById(id);
    if (link) { link.href = value; link.hidden = false; }
  }
}).catch(() => {
  document.getElementById('status').textContent = 'Safari 확장 연결을 확인할 수 없습니다. 사이트 접근을 허용한 뒤 재생 탭을 새로고침해 주세요.';
});
