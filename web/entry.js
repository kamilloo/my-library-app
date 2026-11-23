const entry = document.querySelector('#entry');
const startup = document.querySelector('#startup');
const offline = document.querySelector('#offline-status');
const browser = document.querySelector('#browser');
const android = document.querySelector('#android');
const androidInfo = document.querySelector('#android-info');
const platform = document.querySelector('#platform-message');
const agent = navigator.userAgent;
const isAndroid = /Android/i.test(agent);
const isIphoneSafari = /iPhone/i.test(agent) && /Version\/[\d.]+.*Safari\//i.test(agent)
  && !/CriOS|FxiOS|EdgiOS|OPiOS/i.test(agent);

if (new URLSearchParams(location.search).get('app') === '1') {
  entry.hidden = true;
  startup.hidden = false;
  const bootstrap = document.createElement('script');
  bootstrap.src = 'flutter_bootstrap.js';
  bootstrap.onerror = () => {
    startup.textContent = 'Nie udało się uruchomić biblioteki. Połącz się z internetem i spróbuj ponownie.';
  };
  window.addEventListener('flutter-first-frame', () => {
    startup.hidden = true;
  }, { once: true });
  document.head.append(bootstrap);

  offline.hidden = false;
  offline.textContent = 'Przygotowywanie trybu offline…';
  prepareOffline();
  window.mojaBibliotekaOfflineReady = async () => {
    const worker = navigator.serviceWorker?.controller;
    if (!worker) return false;
    try {
      await verifyOfflineWorker(worker);
      return true;
    } catch (_) {
      return false;
    }
  };
} else {
  const unavailable = 'Nie mamy jeszcze zweryfikowanego linku do aplikacji w Google Play.';
  androidInfo.addEventListener('click', () => {
    document.querySelector('#play-status').textContent = unavailable;
  });

  if (isIphoneSafari) {
    browser.classList.add('primary');
    platform.textContent = 'Otwórz swoją bibliotekę w Safari na iPhonie.';
  } else if (isAndroid) {
    androidInfo.classList.add('primary');
    platform.textContent = 'Na Androidzie zalecamy aplikację z Google Play.';
    document.querySelector('#play-status').textContent = unavailable;
  } else {
    browser.hidden = true;
    platform.textContent = 'Moja Biblioteka jest przeznaczona na telefony. Na iPhonie otwórz tę stronę w Safari.';
  }

  fetch('play-config.json', { cache: 'no-cache' })
    .then(response => response.ok ? response.json() : null)
    .then(config => {
      if (!config?.url) return;
      const url = new URL(config.url);
      if (url.origin !== 'https://play.google.com' || url.pathname !== '/store/apps/details'
          || url.searchParams.get('id') !== 'com.kamilloo.mylibrary') return;
      android.href = url.href;
      android.hidden = false;
      androidInfo.hidden = true;
      android.classList.toggle('primary', isAndroid);
      document.querySelector('#play-status').textContent = '';
    })
    .catch(() => {});
}

async function prepareOffline() {
  try {
    if (!navigator.serviceWorker) throw new Error('serviceWorker unavailable');
    const timeout = new Promise((_, reject) =>
      setTimeout(() => reject(new Error('offline preparation timeout')), 120000));
    await Promise.race([registerOfflineWorker(), timeout]);
    offline.textContent = 'Zasoby do pracy offline są gotowe.';
    setTimeout(() => { offline.hidden = true; }, 6000);
  } catch (_) {
    offline.textContent = 'Tryb offline nie jest gotowy. Otwórz bibliotekę ponownie po połączeniu z internetem.';
    setTimeout(() => { offline.hidden = true; }, 10000);
  }
}

async function registerOfflineWorker() {
  // An already active worker can serve this page without a network connection.
  const active = navigator.serviceWorker.controller;
  if (!active) {
    await navigator.serviceWorker.register('offline-worker.js', { updateViaCache: 'none' });
  } else if (navigator.onLine) {
    navigator.serviceWorker.getRegistration().then(registration => registration?.update()).catch(() => {});
  }
  const registration = await navigator.serviceWorker.ready;
  const worker = navigator.serviceWorker.controller ?? registration.active;
  await verifyOfflineWorker(worker);
}

function verifyOfflineWorker(worker) {
  return new Promise((resolve, reject) => {
    const channel = new MessageChannel();
    const timeout = setTimeout(() => {
      channel.port1.close();
      reject(new Error('offline cache check timeout'));
    }, 5000);
    channel.port1.onmessage = event => {
      clearTimeout(timeout);
      channel.port1.close();
      if (event.data === true) resolve();
      else reject(new Error('offline cache incomplete'));
    };
    worker.postMessage('offline-ready', [channel.port2]);
  });
}
