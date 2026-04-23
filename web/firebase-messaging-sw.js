// Background push handler for Rakhi's Jarvis PWA.
//
// Runs as a Service Worker registered at the site root. When a push
// arrives while the PWA is closed or in the background, this file
// renders the system notification. When the PWA is in the foreground,
// firebase_messaging's Dart side handles it instead.
//
// IMPORTANT: the firebaseConfig block below MUST match the `web`
// FirebaseOptions in lib/firebase_options.dart, otherwise the service
// worker will register against the wrong project and push tokens go
// dead silently.
//
// The service worker lives at the site root by Firebase Messaging
// convention — do NOT move it into a subdirectory.

importScripts(
  'https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js',
);

// Must match lib/firebase_options.dart → FirebaseOptions.web exactly.
// Keep both in sync whenever Firebase Console regenerates credentials.
firebase.initializeApp({
  apiKey: 'AIzaSyCuzulGhpmhq1EuYlIvz0eMsmvgvD1qh3M',
  appId: '1:546240967899:web:21f2901d31e2b15dca48fe',
  messagingSenderId: '546240967899',
  projectId: 'jarvis-78573',
  storageBucket: 'jarvis-78573.firebasestorage.app',
  authDomain: 'jarvis-78573.firebaseapp.com',
});

const messaging = firebase.messaging();

// Renders an OS notification when a push arrives and the PWA isn't
// focused. iOS 16.4+ respects this for installed (home-screen) PWAs.
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};
  const title = notification.title || 'Jarvis';
  const options = {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    // Rakhi's accent — used on browsers that support coloured notification UI
    data: data,
    tag: data.tag || 'jarvis-push',
  };
  return self.registration.showNotification(title, options);
});

// When Rakhi taps a push, focus an existing PWA tab if one is open,
// otherwise open the app fresh. Keeps her from ending up with three
// duplicate Jarvis tabs after a day of reminders.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.click_url) || '/';
  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((matched) => {
        for (const client of matched) {
          if (client.url.includes(self.location.origin) && 'focus' in client) {
            client.focus();
            return;
          }
        }
        if (clients.openWindow) return clients.openWindow(url);
      }),
  );
});
