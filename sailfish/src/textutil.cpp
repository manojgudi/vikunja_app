#include "textutil.h"

#include <QRegularExpression>
#include <QSet>
#include <QStringList>
#include <QUrl>

namespace TextUtil {

QString normalizeServerUrl(const QString &input)
{
    QString s = input.trimmed();
    s.remove(QRegularExpression(QStringLiteral("\\s")));
    if (s.isEmpty())
        return QString();
    if (!s.contains(QStringLiteral("://")))
        s.prepend(QStringLiteral("https://"));
    while (s.endsWith(QLatin1Char('/')))
        s.chop(1);
    if (s.endsWith(QStringLiteral("/api/v1")))
        s.chop(7);
    while (s.endsWith(QLatin1Char('/')))
        s.chop(1);

    const QUrl url(s, QUrl::StrictMode);
    const QString scheme = url.scheme().toLower();
    if (!url.isValid() || url.host().isEmpty() || (scheme != QLatin1String("https") && scheme != QLatin1String("http")))
        return QString();
    if (!url.userInfo().isEmpty() || url.hasQuery() || url.hasFragment())
        return QString();
    return s;
}

static QString attributeValue(const QString &attrs, const QString &name)
{
    const QRegularExpression re(QStringLiteral("\\b%1\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))").arg(name),
                                QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch m = re.match(attrs);
    if (!m.hasMatch())
        return QString();
    for (int i = 2; i <= 4; ++i) {
        if (!m.captured(i).isNull())
            return m.captured(i);
    }
    return QString();
}

QString sanitizeHtml(const QString &html)
{
    static const QSet<QString> allowed = {
        QStringLiteral("p"), QStringLiteral("br"), QStringLiteral("b"), QStringLiteral("strong"),
        QStringLiteral("i"), QStringLiteral("em"), QStringLiteral("u"), QStringLiteral("s"),
        QStringLiteral("del"), QStringLiteral("strike"), QStringLiteral("ul"), QStringLiteral("ol"),
        QStringLiteral("li"), QStringLiteral("h1"), QStringLiteral("h2"), QStringLiteral("h3"),
        QStringLiteral("h4"), QStringLiteral("h5"), QStringLiteral("h6"), QStringLiteral("blockquote"),
        QStringLiteral("code"), QStringLiteral("pre"), QStringLiteral("a"), QStringLiteral("hr"),
        QStringLiteral("table"), QStringLiteral("tr"), QStringLiteral("td"), QStringLiteral("th"),
        QStringLiteral("thead"), QStringLiteral("tbody"), QStringLiteral("span"), QStringLiteral("div")
    };
    static const QRegularExpression dropWithContent(
        QStringLiteral("<(script|style|iframe|object|embed|svg|math|template|noscript|head|title)\\b[^>]*>.*?</\\1\\s*>"),
        QRegularExpression::CaseInsensitiveOption | QRegularExpression::DotMatchesEverythingOption);
    static const QRegularExpression comments(QStringLiteral("<!--.*?-->"), QRegularExpression::DotMatchesEverythingOption);
    static const QRegularExpression tag(QStringLiteral("<\\s*(/?)\\s*([a-zA-Z][a-zA-Z0-9]*)([^>]*)>"));

    QString s(html);
    s.remove(comments);
    s.remove(dropWithContent);

    QString out;
    out.reserve(s.size());
    int pos = 0;
    QRegularExpressionMatchIterator it = tag.globalMatch(s);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        out += s.mid(pos, m.capturedStart() - pos);
        pos = m.capturedEnd();

        const bool closing = !m.captured(1).isEmpty();
        const QString name = m.captured(2).toLower();
        if (!allowed.contains(name))
            continue;
        if (closing) {
            out += QStringLiteral("</%1>").arg(name);
            continue;
        }
        if (name == QLatin1String("a")) {
            const QString href = attributeValue(m.captured(3), QStringLiteral("href")).trimmed();
            const QString scheme = QUrl(href).scheme().toLower();
            if (scheme == QLatin1String("https") || scheme == QLatin1String("http") || scheme == QLatin1String("mailto")) {
                QString escaped = href.toHtmlEscaped();
                out += QStringLiteral("<a href=\"%1\">").arg(escaped);
            } else {
                out += QStringLiteral("<a>");
            }
            continue;
        }
        out += QStringLiteral("<%1>").arg(name);
    }
    out += s.mid(pos);
    // Any stray '<' left over (e.g. broken markup) must not start a tag.
    out.replace(QRegularExpression(QStringLiteral("<(?![/a-z])")), QStringLiteral("&lt;"));
    return out;
}

QString htmlToPlain(const QString &html)
{
    if (html.trimmed().isEmpty())
        return QString();
    QString s = sanitizeHtml(html);
    s.replace(QRegularExpression(QStringLiteral("<br\\s*/?>"), QRegularExpression::CaseInsensitiveOption), QStringLiteral("\n"));
    s.replace(QRegularExpression(QStringLiteral("</(p|div|h[1-6]|li|blockquote|pre|tr)>"), QRegularExpression::CaseInsensitiveOption), QStringLiteral("\n"));
    s.replace(QRegularExpression(QStringLiteral("<li>"), QRegularExpression::CaseInsensitiveOption), QStringLiteral("• "));
    s.remove(QRegularExpression(QStringLiteral("<[^>]*>")));
    s.remove(QLatin1Char('\r'));

    QString plain;
    static const QRegularExpression numeric(QStringLiteral("&#(x?)([0-9a-fA-F]+);"));
    int pos = 0;
    QRegularExpressionMatchIterator it = numeric.globalMatch(s);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        plain += s.mid(pos, m.capturedStart() - pos);
        bool ok = false;
        const uint code = m.captured(2).toUInt(&ok, m.captured(1).isEmpty() ? 10 : 16);
        if (ok && code > 0 && code < 0x110000)
            plain += QString::fromUcs4(&code, 1);
        pos = m.capturedEnd();
    }
    plain += s.mid(pos);
    plain.replace(QStringLiteral("&nbsp;"), QStringLiteral(" "));
    plain.replace(QStringLiteral("&lt;"), QStringLiteral("<"));
    plain.replace(QStringLiteral("&gt;"), QStringLiteral(">"));
    plain.replace(QStringLiteral("&quot;"), QStringLiteral("\""));
    plain.replace(QStringLiteral("&#39;"), QStringLiteral("'"));
    plain.replace(QStringLiteral("&amp;"), QStringLiteral("&"));
    while (plain.endsWith(QLatin1Char('\n')))
        plain.chop(1);
    return plain;
}

QString plainToHtml(const QString &plain)
{
    const QString trimmed = plain.trimmed();
    if (trimmed.isEmpty())
        return QString();
    QStringList paragraphs = trimmed.split(QRegularExpression(QStringLiteral("\\n\\s*\\n")));
    QString out;
    for (const QString &p : paragraphs) {
        QString escaped = p.trimmed().toHtmlEscaped();
        escaped.replace(QLatin1Char('\n'), QStringLiteral("<br>"));
        out += QStringLiteral("<p>%1</p>").arg(escaped);
    }
    return out;
}

bool hasRichFormatting(const QString &html)
{
    static const QRegularExpression rich(
        QStringLiteral("<\\s*(b|strong|i|em|u|s|del|strike|ul|ol|h[1-6]|blockquote|code|pre|a|table|img)\\b"),
        QRegularExpression::CaseInsensitiveOption);
    return rich.match(html).hasMatch();
}

QString safeFileName(const QString &name)
{
    QString s = name;
    const int slash = qMax(s.lastIndexOf(QLatin1Char('/')), s.lastIndexOf(QLatin1Char('\\')));
    if (slash >= 0)
        s = s.mid(slash + 1);
    s.remove(QRegularExpression(QStringLiteral("[\\x00-\\x1f\\x7f]")));
    s.replace(QRegularExpression(QStringLiteral("[:*?\"<>|]")), QStringLiteral("_"));
    while (s.startsWith(QLatin1Char('.')))
        s.remove(0, 1);
    s = s.trimmed();
    if (s.isEmpty())
        s = QStringLiteral("attachment");
    if (s.size() > 200)
        s = s.left(200);
    return s;
}

}
