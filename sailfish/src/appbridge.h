#ifndef APPBRIDGE_H
#define APPBRIDGE_H

#include <QDBusContext>
#include <QObject>
#include <QString>

// Small D-Bus entry point so notification actions ("Open", "Mark done")
// can reach the running app. Only simple integer task ids are accepted, and
// "mark done" is only honoured when the call comes from the notification
// server (lipstick), not from arbitrary processes on the session bus.
class AppBridge : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.manojgudi.harbourvikunja")
    Q_PROPERTY(QString service READ service CONSTANT)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString iface READ iface CONSTANT)
    // True while the app was started by D-Bus (timed or a notification)
    // and its window has not been shown yet.
    Q_PROPERTY(bool background READ background NOTIFY backgroundChanged)

public:
    explicit AppBridge(QObject *parent = nullptr);

    bool registerOnBus();
    QString service() const { return m_service; }
    QString path() const { return QStringLiteral("/"); }
    QString iface() const { return QStringLiteral("io.github.manojgudi.harbourvikunja"); }

    bool background() const { return m_background; }
    void setBackground(bool background);

    Q_INVOKABLE bool openFile(const QString &path);
    // Called when background work is finished; quits if no window was shown.
    Q_INVOKABLE void backgroundDone();
    void quitIfIdle();

public slots:
    Q_SCRIPTABLE void activate();
    Q_SCRIPTABLE void openTask(int taskId);
    Q_SCRIPTABLE void markDone(int taskId);
    // Called (through dbus-send) by a timed event.
    Q_SCRIPTABLE void reminderDue(const QString &kind, int taskId, qlonglong time);

signals:
    void activateRequested();
    void openTaskRequested(int taskId);
    void markDoneRequested(int taskId);
    void reminderRequested(int taskId, const QString &kind, double time);
    void showRequested();
    void backgroundChanged();
    // The background instance is done; main() saves state and exits.
    void backgroundFinished();

private:
    bool callerAllowed();

    QString m_service;
    bool m_background = false;
    int m_pendingWork = 0;
};

#endif // APPBRIDGE_H
