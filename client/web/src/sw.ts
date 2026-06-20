/// <reference lib="webworker" />
import { cleanupOutdatedCaches, precacheAndRoute } from 'workbox-precaching'

declare const self: ServiceWorkerGlobalScope

// Injected by vite-plugin-pwa at build time
precacheAndRoute(self.__WB_MANIFEST)
cleanupOutdatedCaches()

self.addEventListener('push', (event) => {
    const data = event.data?.json() as { title?: string; body?: string } | undefined
    const title = data?.title ?? 'Revaulter'
    const body = data?.body ?? 'New request pending approval'

    event.waitUntil(
        self.registration.showNotification(title, {
            body,
            icon: '/apple-touch-icon-dark.png',
        })
    )
})

self.addEventListener('notificationclick', (event) => {
    event.notification.close()

    event.waitUntil(
        self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
            const existing = clients.find((c) => c.url.startsWith(self.location.origin))
            if (existing) {
                return existing.focus()
            }
            return self.clients.openWindow('/')
        })
    )
})
