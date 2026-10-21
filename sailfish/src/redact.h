#ifndef REDACT_H
#define REDACT_H

#include <QString>
#include <QUrl>

namespace Redact {

// Returns scheme://host[:port]/path with user info, query and fragment removed.
QString url(const QUrl &url);

// Replaces bearer tokens, Vikunja API tokens (tk_...), JWTs and
// password-like JSON fields with "[redacted]".
QString text(const QString &input);

// Installs a Qt message handler that redacts every log line and drops
// debug output in release builds.
void installMessageHandler();

}

#endif // REDACT_H
