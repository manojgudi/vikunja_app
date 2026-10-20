#include "appbridge.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDesktopServices>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>

AppBridge::AppBridge(QObject *parent)
    : QObject(parent)
{
}

bool AppBridge::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;
    if (!bus.registerObject(path(), this, QDBusConnection::ExportScriptableSlots))
        return false;
    // Sailjail lets an app own a bus name made of its organization and
    // application name.
    const QStringList candidates = {
        QStringLiteral("io.github.manojgudi.harbour-vikunja"),
        QStringLiteral("io.github.manojgudi.harbourvikunja")
    };
    for (const QString &name : candidates) {
        if (bus.registerService(name)) {
            m_service = name;
            return true;
        }
    }
    qWarning("Could not register a D-Bus service name; notification actions will not work");
    return false;
}

bool AppBridge::openFile(const QString &path)
{
    // Only files the app itself saved to the Downloads folder are opened.
    const QString downloads = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    const QFileInfo info(path);
    if (!info.exists() || !info.canonicalFilePath().startsWith(QFileInfo(downloads).canonicalFilePath() + QLatin1Char('/')))
        return false;
    return QDesktopServices::openUrl(QUrl::fromLocalFile(info.canonicalFilePath()));
}

bool AppBridge::callerAllowed()
{
    if (!calledFromDBus())
        return true;
    const QDBusReply<QString> owner = connection().interface()->serviceOwner(QStringLiteral("org.freedesktop.Notifications"));
    const bool ok = owner.isValid() && owner.value() == message().service();
    if (!ok)
        qWarning("Ignoring D-Bus call from %s", qPrintable(message().service()));
    return ok;
}

void AppBridge::activate()
{
    emit activateRequested();
}

void AppBridge::openTask(int taskId)
{
    // Opening a task only shows it, so any caller may do that.
    if (taskId > 0)
        emit openTaskRequested(taskId);
}

void AppBridge::markDone(int taskId)
{
    if (taskId > 0 && callerAllowed())
        emit markDoneRequested(taskId);
}
