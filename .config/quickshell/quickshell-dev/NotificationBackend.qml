import Quickshell.Services.Notifications

// Only loaded in explicit server mode. Preview mode never claims the bus name.
NotificationServer {
    actionsSupported: true
    bodySupported: true
    // Cards deliberately render plain text; do not advertise unsupported markup.
    bodyMarkupSupported: false
    bodyImagesSupported: false
    imageSupported: true
    persistenceSupported: true
    keepOnReload: true
    onNotification: notification => NotificationService.receive(notification)
}
