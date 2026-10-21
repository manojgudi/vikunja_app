#include "alarms.h"

#include <QDateTime>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMetaType>
#include <QDBusReply>
#include <QSet>

#include <timed-qt5/interface.h>

namespace {
// timed only accepts [A-Za-z_][A-Za-z_0-9]* here, and rejects upper-case
// attribute keys it does not know, so ours are lower case.
const char *const AppTag = "harbour_vikunja";
const int MaxEvents = 64;

// timed runs D-Bus actions in a forked copy of itself, and with Qt 5.6 that
// copy never gets the message out (the Qt D-Bus thread does not survive the
// fork; seen with the real timed). A command action is forked and exec'd, so
// it is reliable: dbus-send calls the app, and the session bus starts it
// through sailjail if it is not running. Only numbers and a fixed word go
// into the command line. dbus-send waits for the reply: a call whose sender
// has already gone is dropped while the bus is still starting the app.
void addCallback(Maemo::Timed::Event &e, const QString &kind, int taskId, qint64 when)
{
    const QString cmd = QStringLiteral(
        "DBUS_SESSION_BUS_ADDRESS=\"${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/dbus/user_bus_socket}\" "
        "/usr/bin/dbus-send --session --print-reply=literal --reply-timeout=90000 "
        "--dest=io.github.manojgudi.harbour-vikunja "
        "/ io.github.manojgudi.harbourvikunja.reminderDue string:%1 int32:%2 int64:%3 >/dev/null 2>&1")
            .arg(kind).arg(taskId).arg(when);
    Maemo::Timed::Event::Action &a = e.addAction();
    a.runCommand(cmd);
    // Also covers events that were missed while the phone was off, see
    // setTriggerIfMissedFlag below.
    a.whenTriggered();
}

void addEvent(Maemo::Timed::Event::List &list, qint64 when, const QString &kind, int taskId)
{
    Maemo::Timed::Event &e = list.append();
    e.setAttribute(QStringLiteral("APPLICATION"), QLatin1String(AppTag));
    e.setAttribute(QStringLiteral("kind"), kind);
    e.setAttribute(QStringLiteral("taskId"), QString::number(taskId));
    e.setAttribute(QStringLiteral("time"), QString::number(when));
    e.setTicker(static_cast<time_t>(when));
    e.setTriggerIfMissedFlag();
    addCallback(e, kind, taskId, when);
}
}

Alarms::Alarms(QObject *parent)
    : QObject(parent)
{
    qDBusRegisterMetaType<QList<uint>>();
    QDBusConnection bus = Maemo::Timed::bus();
    m_available = bus.isConnected() && bus.interface()
            && bus.interface()->isServiceRegistered(QLatin1String(Maemo::Timed::service())).value();
    if (!m_available)
        qWarning("timed is not available; reminders only fire while the app runs");
}

QList<uint> Alarms::ourCookies(const QString &kind)
{
    Maemo::Timed::Interface ifc;
    QMap<QString, QString> match;
    match.insert(QStringLiteral("APPLICATION"), QLatin1String(AppTag));
    if (!kind.isEmpty())
        match.insert(QStringLiteral("kind"), kind);
    QDBusReply<QList<uint>> reply = ifc.get_cookies_by_attributes_sync(match);
    if (!reply.isValid()) {
        qWarning("timed query failed: %s", qPrintable(reply.error().message()));
        return QList<uint>();
    }
    return reply.value();
}

void Alarms::clear()
{
    cancel(QString());
}

void Alarms::cancel(const QString &kind)
{
    if (!m_available)
        return;
    const QList<uint> cookies = ourCookies(kind);
    if (cookies.isEmpty())
        return;
    Maemo::Timed::Interface ifc;
    ifc.cancel_events_sync(cookies);
}

int Alarms::scheduledCount()
{
    return m_available ? ourCookies().size() : 0;
}

bool Alarms::schedule(const QVariantList &events, int syncHours)
{
    if (!m_available)
        return false;
    const qint64 now = QDateTime::currentMSecsSinceEpoch() / 1000;

    Maemo::Timed::Event::List list;
    QSet<QString> seen;
    for (const QVariant &v : events) {
        if (list.count() >= MaxEvents)
            break;
        const QVariantMap m = v.toMap();
        const int taskId = m.value(QStringLiteral("taskId")).toInt();
        const qint64 when = static_cast<qint64>(m.value(QStringLiteral("time")).toDouble() / 1000);
        QString kind = m.value(QStringLiteral("kind")).toString();
        if (kind != QLatin1String("due"))
            kind = QStringLiteral("reminder");
        const QString key = QStringLiteral("%1:%2:%3").arg(taskId).arg(kind).arg(when);
        if (taskId <= 0 || when <= now || seen.contains(key))
            continue;
        seen.insert(key);
        addEvent(list, when, kind, taskId);
    }
    if (syncHours > 0)
        addEvent(list, now + qint64(syncHours) * 3600, QStringLiteral("sync"), 0);

    // A pending "test" event from the settings page is left alone.
    cancel(QStringLiteral("due"));
    cancel(QStringLiteral("reminder"));
    cancel(QStringLiteral("sync"));
    if (list.count() == 0)
        return true;
    Maemo::Timed::Interface ifc;
    QDBusMessage reply = ifc.add_events_sync(list);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning("timed add_events failed: %s", qPrintable(reply.errorMessage()));
        return false;
    }
    return true;
}

bool Alarms::scheduleTest(int seconds)
{
    if (!m_available)
        return false;
    Maemo::Timed::Event::List list;
    addEvent(list, QDateTime::currentMSecsSinceEpoch() / 1000 + qMax(5, seconds), QStringLiteral("test"), 0);
    Maemo::Timed::Interface ifc;
    QDBusMessage reply = ifc.add_events_sync(list);
    return reply.type() != QDBusMessage::ErrorMessage;
}
