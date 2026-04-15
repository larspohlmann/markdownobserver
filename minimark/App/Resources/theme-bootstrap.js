(function() {
  var meta = document.querySelector('meta[name="minimark-runtime-theme-js-base64"]');
  if (!meta) return;
  var b64 = meta.getAttribute('content');
  if (!b64) return;
  try {
    var binary = atob(b64);
    var bytes = Uint8Array.from(binary, function(c) { return c.charCodeAt(0); });
    var themeJS = new TextDecoder().decode(bytes);
    new Function(themeJS)();
    window.__minimarkLastThemeJSBase64 = b64;
  } catch(e) { console.error('Theme JS bootstrap error:', e); }
})();
