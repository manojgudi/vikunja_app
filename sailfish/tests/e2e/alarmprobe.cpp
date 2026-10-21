// Schedules events through Alarms and prints what timed reports back.
#include <QCoreApplication>
#include <QDateTime>
#include <QDBusReply>
#include <cstdio>
#include <timed-qt5/interface.h>
#include "alarms.h"

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    Alarms a;
    printf("available=%d\n", a.available());
    QVariantMap e;
    e.insert("taskId", 42);
    e.insert("time", double(QDateTime::currentMSecsSinceEpoch() + 20000));
    e.insert("kind", "reminder");
    printf("schedule=%d\n", a.schedule(QVariantList{ e }, 6));
    printf("count=%d\n", a.scheduledCount());
    Maemo::Timed::Interface ifc;
    QDBusMessage m = ifc.get_cookies_by_attributes_sync(QMap<QString, QString>{{"APPLICATION", "harbour_vikunja"}});
    printf("raw reply type=%d err=%s args=%d sig=%s\n", m.type(), qPrintable(m.errorMessage()), m.arguments().size(), qPrintable(m.signature()));
    QDBusMessage q = ifc.query_sync(QMap<QString, QVariant>());
    printf("query all: type=%d %s sig=%s\n", q.type(), qPrintable(q.errorMessage()), qPrintable(q.signature()));
    if (q.arguments().size()) printf("  %s\n", qPrintable(q.arguments().first().toString()));
    return 0;
}
