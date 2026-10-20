#include "apiclient.h"

#include "redact.h"
#include "securestore.h"
#include "textutil.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJSEngine>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslError>
#include <QStandardPaths>
#include <QTimer>
#include <QUrlQuery>

namespace {
const char TokenSecret[] = "api-token";
const char UserAgent[] = "harbour-vikunja (Sailfish OS)";
const qint64 MaxDownloadBytes = 200 * 1024 * 1024;

// Permission groups requested when the app creates its own API token after a
// password login. Everything else (teams, webhooks, migrations, sharing...)
// is left out on purpose.
const QStringList TokenPermissionGroups = {
    QStringLiteral("projects"), QStringLiteral("projects_views"), QStringLiteral("projects_views_tasks"),
    QStringLiteral("tasks"), QStringLiteral("tasks_comments"), QStringLiteral("tasks_labels"),
    QStringLiteral("tasks_attachments"), QStringLiteral("labels")
};

QString fingerprint(const QSslCertificate &cert)
{
    const QByteArray hex = QCryptographicHash::hash(cert.toDer(), QCryptographicHash::Sha256).toHex().toUpper();
    QStringList parts;
    for (int i = 0; i < hex.size(); i += 2)
        parts << QString::fromLatin1(hex.mid(i, 2));
    return parts.join(QLatin1Char(':'));
}

QVariantMap certificateInfo(const QUrl &url, const QSslCertificate &cert, const QList<QSslError> &errors)
{
    QStringList errorStrings;
    for (const QSslError &e : errors)
        errorStrings << e.errorString();
    QVariantMap info;
    info.insert(QStringLiteral("host"), url.host());
    info.insert(QStringLiteral("port"), url.port(443));
    info.insert(QStringLiteral("sha256"), fingerprint(cert));
    info.insert(QStringLiteral("subject"), cert.subjectInfo(QSslCertificate::CommonName).join(QStringLiteral(", ")));
    info.insert(QStringLiteral("issuer"), cert.issuerInfo(QSslCertificate::CommonName).join(QStringLiteral(", ")));
    info.insert(QStringLiteral("expires"), cert.expiryDate().toString(Qt::ISODate));
    info.insert(QStringLiteral("errors"), errorStrings);
    return info;
}

bool isLoopback(const QString &host)
{
    if (host == QLatin1String("localhost"))
        return true;
    QHostAddress addr;
    return addr.setAddress(host) && addr.isLoopback();
}

QString serverMessage(const QByteArray &raw)
{
    const QVariantMap map = QJsonDocument::fromJson(raw).toVariant().toMap();
    return map.value(QStringLiteral("message")).toString();
}
}

QVariantMap ApiClient::Result::toMap() const
{
    QVariantMap m;
    m.insert(QStringLiteral("ok"), ok);
    m.insert(QStringLiteral("status"), status);
    m.insert(QStringLiteral("data"), data);
    m.insert(QStringLiteral("error"), error);
    m.insert(QStringLiteral("errorCode"), errorCode);
    m.insert(QStringLiteral("certificate"), certificate);
    m.insert(QStringLiteral("totalPages"), totalPages);
    return m;
}

ApiClient::ApiClient(SecureStore *store, QObject *parent)
    : QObject(parent)
    , m_store(store)
    , m_nam(new QNetworkAccessManager(this))
{
    // No HTTP cache: responses (task contents) are never written to disk.
    m_nam->setCache(nullptr);
}

bool ApiClient::persistentLogin() const
{
    return m_store && m_store->persistent();
}

bool ApiClient::insecureConnection() const
{
    return QUrl(m_server).scheme() == QLatin1String("http");
}

bool ApiClient::versionAtLeast(const QString &version, int major, int minor)
{
    static const QRegularExpression re(QStringLiteral("(\\d+)\\.(\\d+)"));
    const QRegularExpressionMatch m = re.match(version);
    if (!m.hasMatch())
        return true; // unstable / development builds
    const int maj = m.captured(1).toInt();
    const int min = m.captured(2).toInt();
    return maj > major || (maj == major && min >= minor);
}

QString ApiClient::pinKey(const QString &host, int port) const
{
    return QStringLiteral("tls/pins/%1:%2").arg(host.toLower()).arg(port);
}

bool ApiClient::urlAllowed(const QUrl &url, QString *reason) const
{
    const QString scheme = url.scheme().toLower();
    if (scheme == QLatin1String("https"))
        return true;
    if (scheme == QLatin1String("http")) {
        const QString host = url.host().toLower();
        if (isLoopback(host))
            return true;
        const QStringList allowed = m_settings.value(QStringLiteral("tls/insecureHosts")).toStringList();
        if (allowed.contains(host))
            return true;
        if (reason)
            *reason = tr("This server uses unencrypted HTTP.");
        return false;
    }
    if (reason)
        *reason = tr("Unsupported address.");
    return false;
}

QUrl ApiClient::apiUrl(const QString &base, const QString &path, const QVariantMap &query) const
{
    QUrl url(base + QStringLiteral("/api/v1") + path);
    if (!query.isEmpty()) {
        QUrlQuery q;
        for (auto it = query.constBegin(); it != query.constEnd(); ++it) {
            if (it.value().type() == QVariant::List || it.value().type() == QVariant::StringList) {
                for (const QVariant &v : it.value().toList())
                    q.addQueryItem(it.key(), v.toString());
            } else {
                q.addQueryItem(it.key(), it.value().toString());
            }
        }
        url.setQuery(q);
    }
    return url;
}

void ApiClient::send(const QByteArray &method, const QUrl &url, const QByteArray &body,
                     const QByteArray &token, Callback cb)
{
    QString reason;
    if (!url.isValid() || url.host().isEmpty()) {
        Result r;
        r.errorCode = QStringLiteral("invalid_url");
        r.error = tr("Invalid server address.");
        QTimer::singleShot(0, this, [cb, r]() { cb(r); });
        return;
    }
    if (!urlAllowed(url, &reason)) {
        Result r;
        r.errorCode = QStringLiteral("insecure_http");
        r.error = reason;
        QTimer::singleShot(0, this, [cb, r]() { cb(r); });
        return;
    }

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QByteArray(UserAgent));
    req.setRawHeader("Accept", "application/json");
    if (!body.isNull())
        req.setHeader(QNetworkRequest::ContentTypeHeader, QByteArray("application/json"));
    if (!token.isEmpty())
        req.setRawHeader("Authorization", QByteArray("Bearer ") + token);
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, false);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    req.setAttribute(QNetworkRequest::CacheSaveControlAttribute, false);

    QSslConfiguration ssl = QSslConfiguration::defaultConfiguration();
    ssl.setProtocol(QSsl::TlsV1_2OrLater);
    ssl.setPeerVerifyMode(QSslSocket::VerifyPeer);
    req.setSslConfiguration(ssl);

    // Qt 5.6 only has the QIODevice overload of sendCustomRequest().
    QBuffer *payload = new QBuffer;
    payload->setData(body);
    payload->open(QIODevice::ReadOnly);
    QNetworkReply *reply = m_nam->sendCustomRequest(req, method, payload);
    payload->setParent(reply);
    ++m_pending;
    emit pendingRequestsChanged();

    connect(reply, &QNetworkReply::sslErrors, this, [this, reply](const QList<QSslError> &errors) {
        QSslCertificate cert = reply->sslConfiguration().peerCertificate();
        if (cert.isNull() && !errors.isEmpty())
            cert = errors.first().certificate();
        const QUrl u = reply->url();
        const QString pinned = m_settings.value(pinKey(u.host(), u.port(443))).toString();
        if (!cert.isNull() && !pinned.isEmpty() && pinned == fingerprint(cert)) {
            reply->ignoreSslErrors(errors);
            return;
        }
        reply->setProperty("tlsRejected", certificateInfo(u, cert, errors));
    });

    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, reply, [reply]() {
        reply->setProperty("timedOut", true);
        reply->abort();
    });
    timer->start(m_timeoutMs);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cb]() {
        --m_pending;
        emit pendingRequestsChanged();
        handleFinished(reply, cb);
        reply->deleteLater();
    });
}

void ApiClient::handleFinished(QNetworkReply *reply, Callback cb)
{
    Result r;
    r.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    r.raw = reply->readAll();
    r.totalPages = reply->rawHeader("x-pagination-total-pages").toInt();

    if (reply->property("timedOut").toBool()) {
        r.errorCode = QStringLiteral("timeout");
        r.error = tr("The server did not respond in time.");
    } else if (reply->property("tlsRejected").isValid()) {
        r.errorCode = QStringLiteral("tls_untrusted");
        r.error = tr("The server's certificate is not trusted.");
        r.certificate = reply->property("tlsRejected").toMap();
    } else if (r.status == 0) {
        r.errorCode = QStringLiteral("network");
        r.error = tr("Could not reach the server.");
        qWarning("Network error for %s: %s", qPrintable(Redact::url(reply->url())),
                 qPrintable(Redact::text(reply->errorString())));
    } else if (r.status >= 300) {
        r.errorCode = QStringLiteral("http");
        const QString msg = serverMessage(r.raw);
        r.error = msg.isEmpty() ? tr("The server answered with error %1.").arg(r.status) : msg;
        r.data = QJsonDocument::fromJson(r.raw).toVariant();
    } else {
        r.ok = true;
        const QByteArray contentType = reply->header(QNetworkRequest::ContentTypeHeader).toByteArray();
        if (!r.raw.isEmpty() && contentType.contains("json")) {
            QJsonParseError err;
            const QJsonDocument doc = QJsonDocument::fromJson(r.raw, &err);
            if (err.error != QJsonParseError::NoError) {
                r.ok = false;
                r.errorCode = QStringLiteral("parse");
                r.error = tr("The server sent an unexpected response.");
            } else if (doc.isNull()) {
                r.data = QVariantList();
            } else {
                r.data = doc.toVariant();
            }
        }
    }
    cb(r);
}

void ApiClient::invoke(const QJSValue &callback, const Result &result)
{
    if (!callback.isCallable() || !m_engine)
        return;
    QJSValue fn(callback);
    QJSValue ret = fn.call(QJSValueList() << m_engine->toScriptValue(QVariant(result.toMap())));
    if (ret.isError())
        qWarning("Error in request callback: %s", qPrintable(ret.toString()));
}

// --- Server check and login --------------------------------------------------

void ApiClient::checkServerNative(const QString &input, Callback cb)
{
    const QString server = TextUtil::normalizeServerUrl(input);
    if (server.isEmpty()) {
        Result r;
        r.errorCode = QStringLiteral("invalid_url");
        r.error = tr("Enter a valid server address, e.g. https://vikunja.example.com");
        QTimer::singleShot(0, this, [cb, r]() { cb(r); });
        return;
    }
    send("GET", apiUrl(server, QStringLiteral("/info")), QByteArray(), QByteArray(), [this, server, cb](const Result &res) {
        Result r = res;
        if (r.ok) {
            const QVariantMap info = r.data.toMap();
            const QString version = info.value(QStringLiteral("version")).toString();
            if (!info.contains(QStringLiteral("version"))) {
                r.ok = false;
                r.errorCode = QStringLiteral("not_vikunja");
                r.error = tr("This does not look like a Vikunja server.");
            } else if (!versionAtLeast(version, MinimumMajor, MinimumMinor)) {
                r.ok = false;
                r.errorCode = QStringLiteral("version");
                r.error = tr("Vikunja %1 is too old. Version 0.24 or newer is required.").arg(version);
            }
            QVariantMap data = info;
            data.insert(QStringLiteral("server"), server);
            r.data = data;
        } else {
            QVariantMap data;
            data.insert(QStringLiteral("server"), server);
            r.data = data;
        }
        cb(r);
    });
}

void ApiClient::finishLogin(const QString &server, const QString &version, const QByteArray &token,
                            const QString &method, const QString &tokenId, const QString &expires, Callback cb)
{
    send("GET", apiUrl(server, QStringLiteral("/user")), QByteArray(), token,
         [this, server, version, token, method, tokenId, expires, cb](const Result &res) {
        Result r = res;
        if (!r.ok) {
            if (r.status == 401 || r.status == 403)
                r.error = tr("The token was rejected by the server.");
            cb(r);
            return;
        }
        m_server = server;
        m_serverVersion = version;
        m_token = token;
        m_authMethod = method;
        m_tokenExpires = expires;
        m_settings.setValue(QStringLiteral("session/server"), server);
        m_settings.setValue(QStringLiteral("session/version"), version);
        m_settings.setValue(QStringLiteral("session/authMethod"), method);
        m_settings.setValue(QStringLiteral("session/tokenId"), tokenId);
        m_settings.setValue(QStringLiteral("session/tokenExpires"), expires);
        m_settings.sync();
        if (m_store)
            m_store->write(QLatin1String(TokenSecret), token);
        emit sessionChanged();
        cb(r);
    });
}

void ApiClient::loginWithTokenNative(const QString &url, const QString &token, Callback cb)
{
    const QByteArray tok = token.trimmed().toUtf8();
    if (tok.isEmpty() || tok.contains(' ') || tok.contains('\n')) {
        Result r;
        r.errorCode = QStringLiteral("invalid_token");
        r.error = tr("Paste the API token exactly as shown by Vikunja.");
        QTimer::singleShot(0, this, [cb, r]() { cb(r); });
        return;
    }
    checkServerNative(url, [this, tok, cb](const Result &info) {
        if (!info.ok) {
            cb(info);
            return;
        }
        const QVariantMap data = info.data.toMap();
        finishLogin(data.value(QStringLiteral("server")).toString(), data.value(QStringLiteral("version")).toString(),
                    tok, QStringLiteral("token"), QString(), QString(), cb);
    });
}

void ApiClient::loginWithPasswordNative(const QString &url, const QString &username, const QString &password,
                                        const QString &totp, Callback cb)
{
    checkServerNative(url, [this, username, password, totp, cb](const Result &info) {
        if (!info.ok) {
            cb(info);
            return;
        }
        const QVariantMap data = info.data.toMap();
        const QString server = data.value(QStringLiteral("server")).toString();
        const QString version = data.value(QStringLiteral("version")).toString();

        QVariantMap login;
        login.insert(QStringLiteral("username"), username);
        login.insert(QStringLiteral("password"), password);
        login.insert(QStringLiteral("long_token"), false);
        if (!totp.trimmed().isEmpty())
            login.insert(QStringLiteral("totp_passcode"), totp.trimmed());
        const QByteArray body = QJsonDocument::fromVariant(login).toJson(QJsonDocument::Compact);

        send("POST", apiUrl(server, QStringLiteral("/login")), body, QByteArray(),
             [this, server, version, cb](const Result &res) {
            if (!res.ok) {
                Result r = res;
                const int code = res.data.toMap().value(QStringLiteral("code")).toInt();
                if (code == 1017)
                    r.errorCode = QStringLiteral("totp_required");
                else if (code == 1018)
                    r.errorCode = QStringLiteral("totp_invalid");
                cb(r);
                return;
            }
            const QByteArray jwt = res.data.toMap().value(QStringLiteral("token")).toString().toUtf8();
            // The login token is short lived. Use it once to mint a scoped,
            // revocable API token for this device, then forget it.
            send("GET", apiUrl(server, QStringLiteral("/routes")), QByteArray(), jwt,
                 [this, server, version, jwt, cb](const Result &routes) {
                if (!routes.ok) {
                    cb(routes);
                    return;
                }
                const QVariantMap all = routes.data.toMap();
                QVariantMap permissions;
                for (const QString &group : TokenPermissionGroups) {
                    if (all.contains(group))
                        permissions.insert(group, QVariant(all.value(group).toMap().keys()));
                }
                QVariantList other;
                if (all.value(QStringLiteral("other")).toMap().contains(QStringLiteral("user")))
                    other << QStringLiteral("user");
                if (!other.isEmpty())
                    permissions.insert(QStringLiteral("other"), other);

                const QDateTime expires = QDateTime::currentDateTimeUtc().addYears(1);
                QVariantMap tokenReq;
                tokenReq.insert(QStringLiteral("title"),
                                QStringLiteral("Sailfish OS app (%1)").arg(QDate::currentDate().toString(Qt::ISODate)));
                tokenReq.insert(QStringLiteral("expires_at"), expires.toString(Qt::ISODate));
                tokenReq.insert(QStringLiteral("permissions"), permissions);
                const QByteArray body = QJsonDocument::fromVariant(tokenReq).toJson(QJsonDocument::Compact);

                send("PUT", apiUrl(server, QStringLiteral("/tokens")), body, jwt,
                     [this, server, version, expires, cb](const Result &created) {
                    if (!created.ok) {
                        cb(created);
                        return;
                    }
                    const QVariantMap t = created.data.toMap();
                    const QByteArray apiToken = t.value(QStringLiteral("token")).toString().toUtf8();
                    if (apiToken.isEmpty()) {
                        Result r;
                        r.errorCode = QStringLiteral("parse");
                        r.error = tr("The server did not return an API token.");
                        cb(r);
                        return;
                    }
                    finishLogin(server, version, apiToken, QStringLiteral("password"),
                                t.value(QStringLiteral("id")).toString(), expires.toString(Qt::ISODate), cb);
                });
            });
        });
    });
}

bool ApiClient::restoreSession()
{
    const QString server = m_settings.value(QStringLiteral("session/server")).toString();
    if (server.isEmpty() || !m_store)
        return false;
    bool found = false;
    const QByteArray token = m_store->read(QLatin1String(TokenSecret), &found);
    if (!found || token.isEmpty())
        return false;
    m_server = server;
    m_token = token;
    m_serverVersion = m_settings.value(QStringLiteral("session/version")).toString();
    m_authMethod = m_settings.value(QStringLiteral("session/authMethod")).toString();
    m_tokenExpires = m_settings.value(QStringLiteral("session/tokenExpires")).toString();
    emit sessionChanged();
    return true;
}

void ApiClient::logout()
{
    if (m_store)
        m_store->remove(QLatin1String(TokenSecret));
    m_token.fill('\0');
    m_token.clear();
    m_authMethod.clear();
    m_tokenExpires.clear();
    m_settings.remove(QStringLiteral("session/authMethod"));
    m_settings.remove(QStringLiteral("session/tokenId"));
    m_settings.remove(QStringLiteral("session/tokenExpires"));
    m_settings.sync();
    emit sessionChanged();
}

// --- Generic requests ----------------------------------------------------------

void ApiClient::requestNative(const QString &method, const QString &path, const QVariantMap &query,
                              const QVariant &body, Callback cb)
{
    if (m_token.isEmpty() || m_server.isEmpty() || !path.startsWith(QLatin1Char('/')) || path.contains(QStringLiteral("://"))) {
        Result r;
        r.errorCode = QStringLiteral("not_authenticated");
        r.error = tr("Not signed in.");
        QTimer::singleShot(0, this, [cb, r]() { cb(r); });
        return;
    }
    QByteArray payload;
    if (body.isValid() && !body.isNull())
        payload = QJsonDocument::fromVariant(body).toJson(QJsonDocument::Compact);
    send(method.toUpper().toLatin1(), apiUrl(m_server, path, query), payload, m_token, [this, cb](const Result &r) {
        if (r.status == 401 && !m_token.isEmpty())
            emit sessionExpired();
        cb(r);
    });
}

void ApiClient::request(const QString &method, const QString &path, const QVariant &query,
                        const QVariant &body, const QJSValue &callback)
{
    QVariant b = body;
    if (b.userType() == qMetaTypeId<QJSValue>())
        b = b.value<QJSValue>().toVariant();
    QVariant q = query;
    if (q.userType() == qMetaTypeId<QJSValue>())
        q = q.value<QJSValue>().toVariant();
    requestNative(method, path, q.toMap(), b, [this, callback](const Result &r) { invoke(callback, r); });
}

void ApiClient::downloadNative(int taskId, int attachmentId, const QString &fileName, const QString &directory, Callback cb)
{
    requestNative(QStringLiteral("GET"),
                  QStringLiteral("/tasks/%1/attachments/%2").arg(taskId).arg(attachmentId),
                  QVariantMap(), QVariant(), [this, fileName, directory, cb](const Result &res) {
        Result r = res;
        if (!r.ok) {
            cb(r);
            return;
        }
        if (r.raw.size() > MaxDownloadBytes) {
            r.ok = false;
            r.errorCode = QStringLiteral("too_large");
            r.error = tr("The attachment is too large.");
            cb(r);
            return;
        }
        QDir dir(directory);
        if (!dir.exists())
            dir.mkpath(QStringLiteral("."));
        const QString safe = TextUtil::safeFileName(fileName);
        const QFileInfo base(safe);
        QString target = dir.filePath(safe);
        for (int i = 1; QFile::exists(target) && i < 1000; ++i) {
            const QString suffix = base.completeSuffix().isEmpty() ? QString() : QStringLiteral(".") + base.completeSuffix();
            target = dir.filePath(QStringLiteral("%1 (%2)%3").arg(base.baseName()).arg(i).arg(suffix));
        }
        QFile f(target);
        if (!f.open(QIODevice::WriteOnly) || f.write(r.raw) != r.raw.size()) {
            r.ok = false;
            r.errorCode = QStringLiteral("io");
            r.error = tr("Could not save the file.");
            cb(r);
            return;
        }
        f.close();
        r.data = target;
        r.raw.clear();
        cb(r);
    });
}

void ApiClient::downloadAttachment(int taskId, int attachmentId, const QString &fileName, const QJSValue &callback)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    downloadNative(taskId, attachmentId, fileName, dir, [this, callback](const Result &r) { invoke(callback, r); });
}

// --- QML wrappers ------------------------------------------------------------

void ApiClient::checkServer(const QString &url, const QJSValue &callback)
{
    checkServerNative(url, [this, callback](const Result &r) { invoke(callback, r); });
}

void ApiClient::loginWithToken(const QString &url, const QString &token, const QJSValue &callback)
{
    loginWithTokenNative(url, token, [this, callback](const Result &r) { invoke(callback, r); });
}

void ApiClient::loginWithPassword(const QString &url, const QString &username, const QString &password,
                                  const QString &totp, const QJSValue &callback)
{
    loginWithPasswordNative(url, username, password, totp, [this, callback](const Result &r) { invoke(callback, r); });
}

// --- Trust settings ------------------------------------------------------------

void ApiClient::trustCertificate(const QString &host, int port, const QString &sha256)
{
    m_settings.setValue(pinKey(host, port), sha256.toUpper());
    m_settings.sync();
}

QVariantList ApiClient::trustedCertificates()
{
    QVariantList out;
    m_settings.beginGroup(QStringLiteral("tls/pins"));
    for (const QString &key : m_settings.childKeys()) {
        QVariantMap m;
        m.insert(QStringLiteral("hostPort"), key);
        m.insert(QStringLiteral("sha256"), m_settings.value(key).toString());
        out << m;
    }
    m_settings.endGroup();
    return out;
}

void ApiClient::forgetCertificate(const QString &hostPort)
{
    m_settings.remove(QStringLiteral("tls/pins/") + hostPort);
    m_settings.sync();
}

void ApiClient::allowInsecureHost(const QString &host)
{
    QStringList hosts = m_settings.value(QStringLiteral("tls/insecureHosts")).toStringList();
    if (!hosts.contains(host.toLower()))
        hosts << host.toLower();
    m_settings.setValue(QStringLiteral("tls/insecureHosts"), hosts);
    m_settings.sync();
}

QStringList ApiClient::insecureHosts()
{
    return m_settings.value(QStringLiteral("tls/insecureHosts")).toStringList();
}

void ApiClient::forgetInsecureHost(const QString &host)
{
    QStringList hosts = m_settings.value(QStringLiteral("tls/insecureHosts")).toStringList();
    hosts.removeAll(host.toLower());
    m_settings.setValue(QStringLiteral("tls/insecureHosts"), hosts);
    m_settings.sync();
}

QVariant ApiClient::setting(const QString &key, const QVariant &defaultValue) const
{
    return m_settings.value(QStringLiteral("prefs/") + key, defaultValue);
}

void ApiClient::setSetting(const QString &key, const QVariant &value)
{
    m_settings.setValue(QStringLiteral("prefs/") + key, value);
}
