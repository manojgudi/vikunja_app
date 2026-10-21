// Stand-in for lipstick's notification server: answers
// org.freedesktop.Notifications calls and logs every Notify to stdout.
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QDateTime>
#include <cstdio>

class Server : public QDBusVirtualObject
{
public:
    QString introspect(const QString &) const override { return QString(); }
    bool handleMessage(const QDBusMessage &m, const QDBusConnection &c) override
    {
        if (m.member() == QLatin1String("Notify")) {
            const QList<QVariant> a = m.arguments();
            const QVariantMap hints = a.value(6).toMap();
            printf("NOTIFY %s app=%s summary=\"%s\" body=\"%s\" actions=%d\n",
                   qPrintable(QDateTime::currentDateTime().toString(Qt::ISODate)),
                   qPrintable(a.value(0).toString()), qPrintable(a.value(3).toString()),
                   qPrintable(a.value(4).toString()), a.value(5).toStringList().size());
            for (auto it = hints.begin(); it != hints.end(); ++it)
                if (it.key().startsWith(QLatin1String("x-nemo-remote-action")))
                    printf("  ACTION %s = %s\n", qPrintable(it.key()), qPrintable(it.value().toString()));
            fflush(stdout);
            c.send(m.createReply(QVariant::fromValue(uint(++m_id))));
        } else if (m.member() == QLatin1String("GetCapabilities")) {
            c.send(m.createReply(QStringList{ QStringLiteral("body"), QStringLiteral("actions") }));
        } else if (m.member() == QLatin1String("GetServerInformation")) {
            c.send(m.createReply(QVariantList{ QStringLiteral("mock"), QStringLiteral("e2e"), QStringLiteral("1"), QStringLiteral("1.2") }));
        } else if (!m.isReplyRequired() || m.member() == QLatin1String("CloseNotification")) {
            if (m.isReplyRequired()) c.send(m.createReply());
        } else {
            c.send(m.createErrorReply(QStringLiteral("org.freedesktop.DBus.Error.NotSupported"), m.member()));
        }
        return true;
    }
private:
    uint m_id = 0;
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    Server server;
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerVirtualObject(QStringLiteral("/org/freedesktop/Notifications"), &server)
            || !bus.registerService(QStringLiteral("org.freedesktop.Notifications"))) {
        fprintf(stderr, "cannot register\n");
        return 1;
    }
    printf("READY\n");
    fflush(stdout);
    return app.exec();
}
