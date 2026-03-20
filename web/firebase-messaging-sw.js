// Firebase Messaging Service Worker
// Maneja notificaciones push cuando la web app está en background o cerrada

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBQ-I2Bf9Fwm5SD1U3ePzQL_gcxde5TzFA',
  authDomain: 'donna-app-124dc.firebaseapp.com',
  projectId: 'donna-app-124dc',
  storageBucket: 'donna-app-124dc.firebasestorage.app',
  messagingSenderId: '1098500496995',
  appId: '1:1098500496995:web:8ba033333f0af75e0ce256',
  measurementId: 'G-1JNS0CCVN3',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[SW] Background message received:', payload);

  const notificationTitle = payload.notification?.title || 'Doña Repartos';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data,
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const orderId = event.notification.data?.order_id;
  const url = orderId ? `/?order=${orderId}` : '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});
