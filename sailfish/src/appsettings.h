#ifndef APPSETTINGS_H
#define APPSETTINGS_H

#include <QDir>
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

inline QSettings *create(QObject *parent = nullptr)
{
    return new QSettings(path(), QSettings::IniFormat, parent);
}

}

#endif // APPSETTINGS_H
