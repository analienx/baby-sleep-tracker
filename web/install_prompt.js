/* Little Rest cross-platform PWA installation guide.
 * No remote scripts, tracking, permissions or browser storage contents.
 * Browser-managed installation is only invoked from a direct user click.
 */
(() => {
  'use strict';

  const isStandalone = () =>
    window.matchMedia('(display-mode: standalone)').matches ||
    window.navigator.standalone === true;
  const agent = navigator.userAgent || '';
  const isAppleMobile = /iPhone|iPad|iPod/.test(agent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isAndroid = /Android/.test(agent);
  const isMobile = isAppleMobile || isAndroid;
  if (!isMobile || isStandalone()) return;

  let deferredPrompt = null;
  let banner = null;
  let modal = null;
  const dismissalKey = 'little-rest-install-guide-dismissed';
  const dismissed = () => {
    try { return Date.now() - Number(localStorage.getItem(dismissalKey) || 0) < 30 * 24 * 60 * 60 * 1000; }
    catch (_) { return false; }
  };
  const rememberDismissal = () => {
    try { localStorage.setItem(dismissalKey, String(Date.now())); }
    catch (_) { /* private browsing may disable storage */ }
  };

  function removeModal() {
    if (modal) { modal.remove(); modal = null; }
  }
  function removeBanner() {
    if (banner) { banner.remove(); banner = null; }
  }
  function closeGuide() {
    removeModal();
    removeBanner();
    rememberDismissal();
  }

  function showGuide() {
    if (modal || isStandalone()) return;
    const android = isAndroid;
    const instructions = isAppleMobile
      ? 'In Safari, tap Share, choose Add to Home Screen, enable Open as Web App, then tap Add.'
      : android
        ? 'In Chrome, open the three-dot menu, choose Add to Home screen, then Install.'
        : 'Use your browser’s menu to add Little Rest to your Home Screen.';
    modal = document.createElement('div');
    modal.className = 'lr-install-backdrop';
    modal.innerHTML = `
      <section class="lr-install-dialog" role="dialog" aria-modal="true"
          aria-labelledby="lr-install-heading" aria-describedby="lr-install-description">
        <div class="lr-install-symbol" aria-hidden="true">☾</div>
        <h2 id="lr-install-heading">Little Rest on your Home Screen</h2>
        <p id="lr-install-description"></p>
        <p class="lr-install-note">Use the same verified account on every device.
          Offline edits need a confirmed sync before they are safely backed up.</p>
        <button type="button" class="lr-install-done">Got it</button>
      </section>`;
    modal.querySelector('#lr-install-description').textContent = instructions;
    modal.querySelector('.lr-install-done').addEventListener('click', closeGuide);
    modal.addEventListener('click', event => {
      if (event.target === modal) closeGuide();
    });
    document.body.appendChild(modal);
    modal.querySelector('.lr-install-done').focus();
  }

  async function install() {
    if (isStandalone()) { removeBanner(); return; }
    if (!deferredPrompt) { showGuide(); return; }
    const prompt = deferredPrompt;
    deferredPrompt = null;
    try {
      // Must be called from click, never after a timer/effect.
      await prompt.prompt();
      const choice = await prompt.userChoice;
      if (choice && choice.outcome === 'accepted') {
        closeGuide();
      } else {
        showGuide();
      }
    } catch (_) {
      showGuide();
    }
  }

  function showBanner() {
    if (banner || dismissed() || isStandalone() || !document.body) return;
    banner = document.createElement('aside');
    banner.className = 'lr-install-banner';
    banner.setAttribute('aria-label', 'Install Little Rest');
    const text = document.createElement('span');
    text.textContent = 'Add Little Rest to your Home Screen';
    const installButton = document.createElement('button');
    installButton.className = 'lr-install-action';
    installButton.type = 'button';
    installButton.textContent = 'Install';
    installButton.addEventListener('click', install);
    const dismissButton = document.createElement('button');
    dismissButton.className = 'lr-install-close';
    dismissButton.type = 'button';
    dismissButton.setAttribute('aria-label', 'Dismiss installation suggestion');
    dismissButton.textContent = '×';
    dismissButton.addEventListener('click', closeGuide);
    banner.append(text, installButton, dismissButton);
    document.body.appendChild(banner);
  }

  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    deferredPrompt = event;
    showBanner();
  });
  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    closeGuide();
  });
  window.addEventListener('pageshow', () => {
    if (isStandalone()) closeGuide();
  });
  window.addEventListener('keydown', event => {
    if (event.key === 'Escape') removeModal();
  });
  // Chrome's beforeinstallprompt often arrives after engagement. Give Safari
  // and Chrome users a discoverable manual route even when it never fires.
  window.addEventListener('load', () => {
    setTimeout(showBanner, 7000);
  }, { once: true });
})();
