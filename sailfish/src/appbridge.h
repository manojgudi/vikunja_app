#ifndef APPBRIDGE_H
#define APPBRIDGE_H

#include <QObject>
#include <QString>

// Small D-Bus entry point so notification actions ("Open", "Mark done")
// can reach the running app. Only simple integer task ids are accepted.
class AppBridge : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.manojgudi.harbourvikunja")
    Q_PROPERTY(QString service READ service CONSTANT)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString iface READ iface CONSTANT)

public:
    explicit AppBridge(QObject *parent = nullptr);

    bool registerOnBus();
    QString service() const { return m_service; }
    QString path() const { return QStringLiteral("/"); }
    QString iface() const { return QStringLiteral("io.github.manojgudi.harbourvikunja"); }

    Q_INVOKABLE bool openFile(const QString &path);

public slots:
    Q_SCRIPTABLE void activate();
    Q_SCRIPTABLE void openTask(int taskId);
    Q_SCRIPTABLE void markDone(int taskId);

signals:
    void activateRequested();
    void openTaskRequested(int taskId);
    void markDoneRequested(int taskId);

private:
    QString m_service;
};

#endif // APPBRIDGE_H
