/** Returns whether Web Push is supported in the current browser */
export function isPushSupported(): boolean {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window
}

/** Returns the current notification permission state */
export function getNotificationPermission(): NotificationPermission {
    if (!('Notification' in window)) {
        return 'denied'
    }
    return Notification.permission
}

/** Returns true if push notifications are currently active (permission granted and subscription exists) */
export async function getPushEnabled(): Promise<boolean> {
    if (!isPushSupported() || Notification.permission !== 'granted') {
        return false
    }
    const reg = await getServiceWorkerRegistration()
    if (!reg) {
        return false
    }
    const sub = await reg.pushManager.getSubscription()
    return sub !== null
}

/** Fetches the VAPID public key from the server; returns null if push is not configured */
async function fetchVAPIDKey(): Promise<string | null> {
    const resp = await fetch('/v2/api/push/vapid-public-key', { credentials: 'include' })
    if (resp.status === 404) {
        return null
    }
    if (!resp.ok) {
        throw new Error(`Failed to fetch VAPID key: ${resp.status}`)
    }
    const data = (await resp.json()) as { key: string }
    return data.key
}

/** Returns the active service worker registration, or null */
async function getServiceWorkerRegistration(): Promise<ServiceWorkerRegistration | null> {
    if (!('serviceWorker' in navigator)) {
        return null
    }
    return navigator.serviceWorker.ready
}

/**
 * Subscribes the browser to Web Push and registers the subscription with the server.
 * Requests notification permission if not already granted.
 * Returns true on success, false if permission was denied or push is unsupported.
 */
export async function subscribePush(): Promise<boolean> {
    if (!isPushSupported()) {
        return false
    }

    const vapidKey = await fetchVAPIDKey()
    if (!vapidKey) {
        return false
    }

    const permission = await Notification.requestPermission()
    if (permission !== 'granted') {
        return false
    }

    const reg = await getServiceWorkerRegistration()
    if (!reg) {
        return false
    }

    const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidKey),
    })

    const json = sub.toJSON()
    await fetch('/v2/api/push/subscribe', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            endpoint: json.endpoint,
            p256dh: json.keys?.['p256dh'] ?? '',
            auth: json.keys?.['auth'] ?? '',
        }),
    })

    return true
}

/**
 * Unsubscribes the browser from Web Push and removes the subscription from the server.
 */
export async function unsubscribePush(): Promise<void> {
    const reg = await getServiceWorkerRegistration()
    if (!reg) {
        return
    }

    const sub = await reg.pushManager.getSubscription()
    if (!sub) {
        return
    }

    const endpoint = sub.endpoint
    await sub.unsubscribe()

    await fetch('/v2/api/push/subscribe', {
        method: 'DELETE',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ endpoint }),
    })
}

/** Converts a base64url-encoded VAPID public key to a Uint8Array for pushManager.subscribe() */
function urlBase64ToUint8Array(base64String: string): Uint8Array {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
    const rawData = atob(base64)
    return Uint8Array.from(rawData, (c) => c.charCodeAt(0))
}
