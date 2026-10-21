#ifndef ALARMS_H
#define ALARMS_H

#include <QObject>
#include <QVariantList>

// Schedules reminder wake-ups with timed, the Sailfish system alarm
// service, so reminders fire while the app is closed. When an event is due,
// timed calls AppBridge::reminderDue over D-Bus; sailjail starts the app in
// the background for that call (ExecDBus in the desktop file).
//
// Only the task id, the kind and the time are given to timed. Task titles
// stay on the server and are fetched when the reminder fires.
class Alarms : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit Alarms(QObject *parent = nullptr);

    bool available() const { return m_available; }

    // events: [{ taskId, time (ms since epoch), kind: "due" | "reminder" }]
    // Replaces everything scheduled before and adds a background sync wake-up.
    Q_INVOKABLE bool schedule(const QVariantList &events, int syncHours = 6);
    Q_INVOKABLE bool scheduleTest(int seconds);
    Q_INVOKABLE void clear();
    Q_INVOKABLE int scheduledCount();

signals:
    void availableChanged();

private:
    QList<uint> ourCookies(const QString &kind = QString());
    void cancel(const QString &kind);

    bool m_available = false;
};

#endif // ALARMS_H
