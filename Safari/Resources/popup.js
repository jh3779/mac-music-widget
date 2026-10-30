browser.runtime.sendMessage({ kind: 'status' }).then(response => {
  document.getElementById('status').textContent = response?.ok
    ? 'Native bridge ready. The host app must also be running.'
    : (response?.error || 'Native bridge unavailable. Check signing and App Group settings.');
}).catch(() => {
  document.getElementById('status').textContent = 'Extension unavailable. Reload the page after enabling access.';
});
