#include "redact.h"
#include "appsettings.h"

#include <QRegularExpression>
#include <cstdio>

namespace Redact {

QString url(const QUrl &url)
{
    QUrl clean(url);
    clean.setUserInfo(QString());
    clean.setQuery(QString());
    clean.setFragment(QString());
    return clean.toString();
}

QString text(const QString &input)
{
    static const QRegularExpression bearer(QStringLiteral("(Bearer\\s+)[A-Za-z0-9._~+/=-]+"),
                                           QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression apiToken(QStringLiteral("\\btk_[A-Za-z0-9]+"));
    static const QRegularExpression jwt(QStringLiteral("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"));
    static const QRegularExpression jsonSecret(
        QStringLiteral("(\"(?:password|token|totp_passcode|refresh_token|access_token|code_verifier)\"\\s*:\\s*\")[^\"]*"),
        QRegularExpression::CaseInsensitiveOption);

    QString out(input);
    out.replace(bearer, QStringLiteral("\\1[redacted]"));
    out.replace(jsonSecret, QStringLiteral("\\1[redacted]"));
    out.replace(jwt, QStringLiteral("[redacted]"));
    out.replace(apiToken, QStringLiteral("[redacted]"));
    return out;
}

static void messageHandler(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
#ifdef QT_NO_DEBUG
    if (type == QtDebugMsg || type == QtInfoMsg)
        return;
#endif
    const char *level = "D";
    switch (type) {
    case QtDebugMsg: level = "D"; break;
    case QtInfoMsg: level = "I"; break;
    case QtWarningMsg: level = "W"; break;
    case QtCriticalMsg: level = "C"; break;
    case QtFatalMsg: level = "F"; break;
    }
    const QByteArray line = text(msg).toLocal8Bit();
    fprintf(stderr, "[%s] %s\n", level, line.constData());
    fflush(stderr);
    // Qt and QML warnings also go to the session log (redacted, shortened),
    // so a failure on the phone can be read without the journal.
    if (type != QtDebugMsg && type != QtInfoMsg && QCoreApplication::instance()
            && !msg.startsWith(QLatin1String("vikunja-session:"))) {
        static bool busy = false;
        if (!busy) {
            busy = true;
            AppSettings::appendLog(QStringLiteral("qt %1: %2").arg(QLatin1String(level))
                                   .arg(text(msg).left(300)));
            busy = false;
        }
    }
}

void installMessageHandler()
{
    qInstallMessageHandler(messageHandler);
}

}
