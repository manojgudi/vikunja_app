#ifndef APICLIENT_H
#define APICLIENT_H

#include <QByteArray>
#include <QJSValue>
#include <QObject>
#include <QPointer>
#include <QSettings>
#include <QUrl>
#include <QVariant>
#include <functional>

#include <QJSEngine>
class QNetworkAccessManager;
class QNetworkReply;
class SecureStore;

// Talks to the Vikunja REST API.
//
// Security properties:
//  * The API token lives only here and in SecureStore. QML can never read it.
//  * TLS certificates are validated normally. A certificate that fails
//    validation is only accepted if the user pinned its exact SHA-256
//    fingerprint for that host and port (trust on first use).
//  * Plain http:// is refused unless the host is loopback or the user
//    explicitly allowed it for that host.
//  * Redirects are not followed, so the Authorization header never leaves
//    the configured server.
//  * Errors and logs never include request headers or tokens.
class ApiClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY sessionChanged)
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY sessionChanged)
    Q_PROPERTY(QString serverVersion READ serverVersion NOTIFY sessionChanged)
    Q_PROPERTY(QString authMethod READ authMethod NOTIFY sessionChanged)
    Q_PROPERTY(QString tokenExpires READ tokenExpires NOTIFY sessionChanged)
    Q_PROPERTY(bool insecureConnection READ insecureConnection NOTIFY sessionChanged)
    Q_PROPERTY(bool persistentLogin READ persistentLogin CONSTANT)
    Q_PROPERTY(int pendingRequests READ pendingRequests NOTIFY pendingRequestsChanged)

public:
    struct Result {
        bool ok = false;
        int status = 0;
        QVariant data;
        QString error;        // human readable, safe to show
        QString errorCode;    // machine readable: network, timeout, tls_untrusted, insecure_http, http, parse, invalid_url
        QVariantMap certificate;
        int totalPages = 0;
        QByteArray raw;
        QVariantMap toMap() const;
    };
    typedef std::function<void(const Result &)> Callback;

    static const int MinimumMajor = 0;
    static const int MinimumMinor = 24;

    explicit ApiClient(SecureStore *store, QObject *parent = nullptr);

    void setEngine(QJSEngine *engine) { m_engine = engine; }
    void setRequestTimeout(int ms) { m_timeoutMs = ms; }

    QString serverUrl() const { return m_server; }
    bool authenticated() const { return !m_token.isEmpty(); }
    QString serverVersion() const { return m_serverVersion; }
    QString authMethod() const { return m_authMethod; }
    QString tokenExpires() const { return m_tokenExpires; }
    bool insecureConnection() const;
    bool persistentLogin() const;
    int pendingRequests() const { return m_pending; }

    // QML API. Every callback receives one object:
    // { ok, status, data, error, errorCode, certificate, totalPages }
    Q_INVOKABLE void checkServer(const QString &url, const QJSValue &callback);
    Q_INVOKABLE void loginWithToken(const QString &url, const QString &token, const QJSValue &callback);
    Q_INVOKABLE void loginWithPassword(const QString &url, const QString &username, const QString &password,
                                       const QString &totp, const QJSValue &callback);
    Q_INVOKABLE bool restoreSession();
    Q_INVOKABLE void logout();
    Q_INVOKABLE void request(const QString &method, const QString &path, const QVariant &query,
                             const QVariant &body, const QJSValue &callback);
    Q_INVOKABLE void downloadAttachment(int taskId, int attachmentId, const QString &fileName,
                                        const QJSValue &callback);

    Q_INVOKABLE void trustCertificate(const QString &host, int port, const QString &sha256);
    Q_INVOKABLE QVariantList trustedCertificates();
    Q_INVOKABLE void forgetCertificate(const QString &hostPort);
    // Non-sensitive preferences (theme of the UI, reminder options, ...).
    Q_INVOKABLE QVariant setting(const QString &key, const QVariant &defaultValue = QVariant()) const;
    Q_INVOKABLE void setSetting(const QString &key, const QVariant &value);

    Q_INVOKABLE void allowInsecureHost(const QString &host);
    Q_INVOKABLE QStringList insecureHosts();
    Q_INVOKABLE void forgetInsecureHost(const QString &host);

    // C++ API, used by the QML wrappers above and by tests.
    void checkServerNative(const QString &url, Callback cb);
    void loginWithTokenNative(const QString &url, const QString &token, Callback cb);
    void loginWithPasswordNative(const QString &url, const QString &username, const QString &password,
                                 const QString &totp, Callback cb);
    void requestNative(const QString &method, const QString &path, const QVariantMap &query,
                       const QVariant &body, Callback cb);
    void downloadNative(int taskId, int attachmentId, const QString &fileName, const QString &directory, Callback cb);

    static bool versionAtLeast(const QString &version, int major, int minor);

signals:
    void sessionChanged();
    void sessionExpired();
    void pendingRequestsChanged();

private:
    void send(const QByteArray &method, const QUrl &url, const QByteArray &body,
              const QByteArray &token, Callback cb);
    void handleFinished(QNetworkReply *reply, Callback cb);
    bool urlAllowed(const QUrl &url, QString *reason) const;
    QUrl apiUrl(const QString &base, const QString &path, const QVariantMap &query = QVariantMap()) const;
    void finishLogin(const QString &server, const QString &version, const QByteArray &token,
                     const QString &method, const QString &tokenId, const QString &expires, Callback cb);
    void invoke(const QJSValue &callback, const Result &result);
    QString pinKey(const QString &host, int port) const;

    SecureStore *m_store;
    QNetworkAccessManager *m_nam;
    QPointer<QJSEngine> m_engine;
    QSettings m_settings;
    QString m_server;
    QString m_serverVersion;
    QString m_authMethod;
    QString m_tokenExpires;
    QByteArray m_token;
    int m_pending = 0;
    int m_timeoutMs = 20000;
};

#endif // APICLIENT_H
