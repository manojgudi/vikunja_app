#ifndef TEXTUTIL_H
#define TEXTUTIL_H

#include <QObject>
#include <QString>

namespace TextUtil {

// Trims whitespace, adds https:// when no scheme is given and strips a
// trailing slash or /api/v1 suffix. Returns an empty string for input that
// is not an http(s) URL with a host.
QString normalizeServerUrl(const QString &input);

// Keeps a small allowlist of formatting tags and drops everything that can
// load remote content (img, style, link, iframe, ...), scripts, event
// handlers and all attributes except safe link targets.
QString sanitizeHtml(const QString &html);

// Converts Vikunja's HTML descriptions to plain text for editing.
QString htmlToPlain(const QString &html);

// Converts edited plain text back to minimal HTML (escaped, <p>/<br>).
QString plainToHtml(const QString &plain);

// True when the HTML uses formatting that htmlToPlain would lose.
bool hasRichFormatting(const QString &html);

// Makes a server-supplied file name safe to use inside a directory:
// strips path components, control characters and leading dots.
QString safeFileName(const QString &name);

}

// QML-facing wrapper.
class Util : public QObject
{
    Q_OBJECT
public:
    explicit Util(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE QString normalizeServerUrl(const QString &input) const { return TextUtil::normalizeServerUrl(input); }
    Q_INVOKABLE QString sanitizeHtml(const QString &html) const { return TextUtil::sanitizeHtml(html); }
    Q_INVOKABLE QString htmlToPlain(const QString &html) const { return TextUtil::htmlToPlain(html); }
    Q_INVOKABLE QString plainToHtml(const QString &plain) const { return TextUtil::plainToHtml(plain); }
    Q_INVOKABLE bool hasRichFormatting(const QString &html) const { return TextUtil::hasRichFormatting(html); }
};

#endif // TEXTUTIL_H
