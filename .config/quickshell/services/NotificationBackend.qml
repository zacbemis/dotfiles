import Quickshell.Services.Notifications

// Only loaded in explicit server mode. Preview mode never claims the bus name.
NotificationServer {
    actionsSupported: true
    bodySupported: true
    // Sanitized b/i/u/links only; body-image HTML is not advertised or loaded.
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    bodyImagesSupported: false
    imageSupported: true
    persistenceSupported: true
    keepOnReload: true
    onNotification: notification => NotificationService.receive(notification)
}
