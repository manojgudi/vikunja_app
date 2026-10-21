#include "appbridge.h"
#include "appsettings.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDesktopServices>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTimer>
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

void AppBridge::setBackground(bool background)
{
    if (m_background == background)
        return;
    m_background = background;
    emit backgroundChanged();
}

void AppBridge::backgroundDone()
{
    if (m_pendingWork > 0)
        --m_pendingWork;
    quitIfIdle();
}

void AppBridge::quitIfIdle()
{
    if (!m_background || m_pendingWork > 0)
        return;
    // Give the notification server a moment to receive what was published.
    QTimer::singleShot(3000, this, [this]() {
        if (m_background && m_pendingWork == 0)
            emit backgroundFinished();
    });
}

void AppBridge::activate()
{
    AppSettings::diag(QStringLiteral("dbus: activate, background=%1").arg(m_background));
    setBackground(false);
    emit showRequested();
    emit activateRequested();
}

void AppBridge::openTask(int taskId)
{
    AppSettings::diag(QStringLiteral("dbus: openTask %1, background=%2").arg(taskId).arg(m_background));
    // Opening a task only shows it, so any caller may do that.
    setBackground(false);
    emit showRequested();
    if (taskId > 0)
        emit openTaskRequested(taskId);
    else
        emit activateRequested();
}

void AppBridge::reminderDue(const QString &kind, int taskId, qlonglong time)
{
    // Anyone on the session bus could call this, so the arguments are only a
    // hint: the QML side re-checks the task on the server before it shows
    // anything.
    static const QStringList kinds = { QStringLiteral("due"), QStringLiteral("reminder"),
                                       QStringLiteral("sync"), QStringLiteral("test") };
    if (taskId < 0 || !kinds.contains(kind))
        return;
    AppSettings::diag(QStringLiteral("dbus: reminderDue %1 %2").arg(kind).arg(taskId));
    ++m_pendingWork;
    emit reminderRequested(taskId, kind, double(time) * 1000.0);
}

void AppBridge::markDone(int taskId)
{
    if (taskId > 0 && callerAllowed())
        emit markDoneRequested(taskId);
}
