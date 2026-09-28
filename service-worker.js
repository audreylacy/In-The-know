self.addEventListener('push', (event) => {
  const payload = event.data ? event.data.json() : { title: 'In The Know', message: 'You have a new update.' };
  const options = {
    body: payload.message || 'You have a new update.',
    tag: payload.tag || 'in-the-know',
    data: payload
  };

  event.waitUntil(self.registration.showNotification(payload.title || 'In The Know', options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const url = self.location.origin;
  event.waitUntil(clients.openWindow(url));
});
