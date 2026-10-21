#ifndef APPSETTINGS_H
#define APPSETTINGS_H

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QStringList>
#include <QSettings>
#include <QStandardPaths>
#include <QString>

// Sailjail only keeps ~/.config/<organization>/<application>/ for a sandboxed
// app. QSettings' default file, ~/.config/<organization>/<application>.conf,
// sits next to that folder, so inside the sandbox it is written to a
// temporary mount and gone when the app closes. Every QSettings in the app
// uses this file instead.
namespace AppSettings {

inline QString path()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/settings.conf");
}

inline QString logPath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/session.log");
}

// Appends one timestamped line to the session log, kept to the last 300 lines.
inline void appendLog(const QString &message)
{
    const QString line = QDateTime::currentDateTime().toString(Qt::ISODate)
            + QStringLiteral(" [") + QString::number(QCoreApplication::applicationPid())
            + QStringLiteral("] ") + message;
    QFile file(logPath());
    QStringList lines;
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        lines = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), QString::SkipEmptyParts);
        file.close();
    }
    lines << line;
    while (lines.size() > 300)
        lines.removeFirst();
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        file.write((lines.join(QLatin1Char('\n')) + QLatin1Char('\n')).toUtf8());
}

// Session diagnostics, never tokens or task data: a short log in the app's
// private cache folder (~/.cache/<org>/<app>/session.log), plus a warning
// for the journal.
inline void diag(const QString &message)
{
    qWarning("vikunja-session: %s", qPrintable(message));
    appendLog(message);
}

inline QSettings *create(QObject *parent = nullptr)
{
    return new QSettings(path(), QSettings::IniFormat, parent);
}

}

#endif // APPSETTINGS_H
