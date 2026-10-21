#include <QtTest>

#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QTemporaryDir>
#include <QTimer>
#include <QSettings>

#include <QImage>
#include <QMessageAuthenticationCode>

#include "apiclient.h"
#include "appsettings.h"
#include "attachmentimages.h"
#include "redact.h"
#include "securestore.h"
#include "textutil.h"

// Unit tests for the security helpers, plus integration tests that run
// against a live Vikunja server when VIKUNJA_TEST_URL and
// VIKUNJA_TEST_TOKEN are set.
class TestHarbourVikunja : public QObject
{
    Q_OBJECT

private:
    typedef std::function<void(ApiClient::Callback)> Call;

    ApiClient::Result wait(Call call)
    {
        ApiClient::Result out;
        bool done = false;
        QEventLoop loop;
        call([&](const ApiClient::Result &r) { out = r; done = true; loop.quit(); });
        if (!done) {
            QTimer::singleShot(30000, &loop, &QEventLoop::quit);
            loop.exec();
        }
        if (!done)
            out.errorCode = QStringLiteral("test_timeout");
        return out;
    }

    ApiClient::Result req(ApiClient &api, const QString &method, const QString &path,
                          const QVariant &body = QVariant(), const QVariantMap &query = QVariantMap())
    {
        return wait([&](ApiClient::Callback cb) { api.requestNative(method, path, query, body, cb); });
    }

    QString url() const { return qEnvironmentVariable("VIKUNJA_TEST_URL"); }
    QString token() const { return qEnvironmentVariable("VIKUNJA_TEST_TOKEN"); }
    void requireServer()
    {
        if (url().isEmpty() || token().isEmpty())
            QSKIP("VIKUNJA_TEST_URL / VIKUNJA_TEST_TOKEN not set");
    }

    static QString qEnvironmentVariable(const char *name) { return QString::fromLocal8Bit(qgetenv(name)); }

    // RFC 6238 code for a base32 secret, to test two-factor login.
    static QString totp(const QString &base32)
    {
        QByteArray key;
        int buffer = 0, bits = 0;
        for (QChar c : base32.toUpper()) {
            const int v = QStringLiteral("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567").indexOf(c);
            if (v < 0)
                continue;
            buffer = (buffer << 5) | v;
            bits += 5;
            if (bits >= 8) {
                key.append(char((buffer >> (bits - 8)) & 0xff));
                bits -= 8;
            }
        }
        quint64 counter = QDateTime::currentMSecsSinceEpoch() / 1000 / 30;
        QByteArray msg(8, 0);
        for (int i = 7; i >= 0; --i, counter >>= 8)
            msg[i] = char(counter & 0xff);
        const QByteArray h = QMessageAuthenticationCode::hash(msg, key, QCryptographicHash::Sha1);
        const int o = h.at(h.size() - 1) & 0x0f;
        const quint32 bin = ((quint32(uchar(h[o])) & 0x7f) << 24) | (quint32(uchar(h[o + 1])) << 16)
                | (quint32(uchar(h[o + 2])) << 8) | quint32(uchar(h[o + 3]));
        return QStringLiteral("%1").arg(bin % 1000000, 6, 10, QLatin1Char('0'));
    }

    SecureStore m_store;
    AttachmentImages *m_images = nullptr;

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName(QStringLiteral("harbour-vikunja-tests"));
        QCoreApplication::setApplicationName(QStringLiteral("tst"));
        QSettings(AppSettings::path(), QSettings::IniFormat).clear();
        qputenv("HARBOUR_VIKUNJA_MEMORY_STORE", "1");
        m_store.init();
        m_images = new AttachmentImages;
    }

    void cleanupTestCase()
    {
        delete m_images;
    }

    // --- Unit tests -----------------------------------------------------------

    void normalizeServerUrl_data()
    {
        QTest::addColumn<QString>("input");
        QTest::addColumn<QString>("expected");
        QTest::newRow("plain host") << "vikunja.example.com" << "https://vikunja.example.com";
        QTest::newRow("trailing slash") << "https://v.example.com/" << "https://v.example.com";
        QTest::newRow("api suffix") << "https://v.example.com/api/v1/" << "https://v.example.com";
        QTest::newRow("spaces") << "  https://v.example.com :3456 " << "https://v.example.com:3456";
        QTest::newRow("sub path") << "https://example.com/vikunja" << "https://example.com/vikunja";
        QTest::newRow("http kept") << "http://192.168.1.2:3456" << "http://192.168.1.2:3456";
        QTest::newRow("userinfo rejected") << "https://user:pw@example.com" << "";
        QTest::newRow("other scheme") << "ftp://example.com" << "";
        QTest::newRow("query rejected") << "https://example.com/?x=1" << "";
        QTest::newRow("empty") << "" << "";
    }

    void normalizeServerUrl()
    {
        QFETCH(QString, input);
        QFETCH(QString, expected);
        QCOMPARE(TextUtil::normalizeServerUrl(input), expected);
    }

    void sanitizeHtml()
    {
        const QString dirty = QStringLiteral(
            "<p onclick=\"steal()\">Hi <b>there</b><img src=\"https://tracker.example/p.gif\"></p>"
            "<script>alert(1)</script><style>body{background:url(https://x)}</style>"
            "<a href=\"javascript:alert(1)\">bad</a><a href=\"https://ok.example\" style=\"x\">good</a>"
            "<iframe src=\"https://x\"></iframe><!-- <img src=x> -->");
        const QString clean = TextUtil::sanitizeHtml(dirty);
        QCOMPARE(clean, QStringLiteral("<p>Hi <b>there</b></p><a>bad</a><a href=\"https://ok.example\">good</a>"));
        QVERIFY(!clean.contains(QStringLiteral("img")));
        QVERIFY(!clean.contains(QStringLiteral("script")));
        QVERIFY(!clean.contains(QStringLiteral("onclick")));
    }

    void htmlPlainRoundTrip()
    {
        QCOMPARE(TextUtil::htmlToPlain(QStringLiteral("<p>Line one<br>Line &amp; two</p><p>Para &#8211; 2</p>")),
                 QStringLiteral("Line one\nLine & two\nPara \u2013 2"));
        QCOMPARE(TextUtil::plainToHtml(QStringLiteral("a < b\nnext\n\nsecond")),
                 QStringLiteral("<p>a &lt; b<br>next</p><p>second</p>"));
        QCOMPARE(TextUtil::plainToHtml(QStringLiteral("   ")), QString());
        QVERIFY(TextUtil::hasRichFormatting(QStringLiteral("<p><b>x</b></p>")));
        QVERIFY(!TextUtil::hasRichFormatting(QStringLiteral("<p>x<br>y</p>")));
    }

    void safeFileName_data()
    {
        QTest::addColumn<QString>("input");
        QTest::addColumn<QString>("expected");
        QTest::newRow("traversal") << "../../.ssh/authorized_keys" << "authorized_keys";
        QTest::newRow("windows") << "C:\\Users\\x\\evil.exe" << "evil.exe";
        QTest::newRow("hidden") << ".bashrc" << "bashrc";
        QTest::newRow("control") << QString::fromUtf8("a\nb\tc.txt") << "abc.txt";
        QTest::newRow("empty") << "/" << "attachment";
        QTest::newRow("normal") << "Report 2026.pdf" << "Report 2026.pdf";
    }

    void safeFileName()
    {
        QFETCH(QString, input);
        QFETCH(QString, expected);
        QCOMPARE(TextUtil::safeFileName(input), expected);
    }

    void redaction()
    {
        const QString line = QStringLiteral(
            "Authorization: Bearer tk_abc123 token tk_9f8e jwt eyJhbGciOi.eyJzdWIi.sig_-x "
            "{\"password\":\"hunter2\",\"totp_passcode\":\"123456\"}");
        const QString r = Redact::text(line);
        QVERIFY2(!r.contains(QStringLiteral("abc123")), qPrintable(r));
        QVERIFY(!r.contains(QStringLiteral("tk_9f8e")));
        QVERIFY(!r.contains(QStringLiteral("eyJhbGciOi")));
        QVERIFY(!r.contains(QStringLiteral("hunter2")));
        QVERIFY(!r.contains(QStringLiteral("123456")));
        QCOMPARE(Redact::url(QUrl(QStringLiteral("https://u:p@h.example/api/v1/tasks?filter=secret#x"))),
                 QStringLiteral("https://h.example/api/v1/tasks"));
    }

    void versionCheck()
    {
        QVERIFY(ApiClient::versionAtLeast(QStringLiteral("v2.7.1"), 0, 24));
        QVERIFY(ApiClient::versionAtLeast(QStringLiteral("v0.24.0"), 0, 24));
        QVERIFY(!ApiClient::versionAtLeast(QStringLiteral("v0.22.1"), 0, 24));
        QVERIFY(ApiClient::versionAtLeast(QStringLiteral("unstable"), 0, 24));
    }

    void insecureHttpBlocked()
    {
        ApiClient api(&m_store);
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.checkServerNative(QStringLiteral("http://vikunja.example.invalid"), cb); });
        QCOMPARE(r.errorCode, QStringLiteral("insecure_http"));
        QVERIFY(!r.ok);
    }

    void requestsNeedSession()
    {
        ApiClient api(&m_store);
        ApiClient::Result r = req(api, QStringLiteral("GET"), QStringLiteral("/projects"));
        QCOMPARE(r.errorCode, QStringLiteral("not_authenticated"));
    }

    // Sailjail keeps only ~/.config/<org>/<app>/; a settings file next to it
    // would be lost every time the app closes.
    void settingsLiveInsideTheSandboxFolder()
    {
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
        QVERIFY(AppSettings::path().startsWith(dir + QStringLiteral("/")));
        const QString defaultFile = QSettings().fileName();
        QFile::remove(defaultFile);
        {
            ApiClient api(&m_store);
            api.setSetting(QStringLiteral("probe"), QStringLiteral("1"));
            api.syncSettings();
        }
        QVERIFY(QFile::exists(AppSettings::path()));
        QVERIFY(!QFile::exists(defaultFile));
        ApiClient again(&m_store);
        QCOMPARE(again.setting(QStringLiteral("probe")).toString(), QStringLiteral("1"));
    }

    void memoryStoreNeverPersists()
    {
        QVERIFY(!m_store.persistent());
        m_store.write(QStringLiteral("k"), "v");
        bool found = false;
        QCOMPARE(m_store.read(QStringLiteral("k"), &found), QByteArray("v"));
        QVERIFY(found);
        m_store.remove(QStringLiteral("k"));
        m_store.read(QStringLiteral("k"), &found);
        QVERIFY(!found);
    }

    // --- TLS pinning against a local self-signed server ------------------------

    void selfSignedCertificateNeedsPin()
    {
        const QString tlsUrl = qEnvironmentVariable("VIKUNJA_TEST_TLS_URL");
        if (tlsUrl.isEmpty())
            QSKIP("VIKUNJA_TEST_TLS_URL not set");
        ApiClient api(&m_store);
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.checkServerNative(tlsUrl, cb); });
        QCOMPARE(r.errorCode, QStringLiteral("tls_untrusted"));
        const QString fp = r.certificate.value(QStringLiteral("sha256")).toString();
        QCOMPARE(fp.size(), 95); // 32 bytes as AA:BB:...
        const QString expected = qEnvironmentVariable("VIKUNJA_TEST_TLS_SHA256");
        if (!expected.isEmpty())
            QCOMPARE(fp, expected.toUpper());

        // A wrong pin must not be accepted.
        const QUrl u(tlsUrl);
        api.trustCertificate(u.host(), u.port(443), QString(fp).replace(0, 2, QStringLiteral("00")));
        r = wait([&](ApiClient::Callback cb) { api.checkServerNative(tlsUrl, cb); });
        QCOMPARE(r.errorCode, QStringLiteral("tls_untrusted"));

        api.trustCertificate(u.host(), u.port(443), fp);
        r = wait([&](ApiClient::Callback cb) { api.checkServerNative(tlsUrl, cb); });
        QVERIFY2(r.ok, qPrintable(r.error));
        api.forgetCertificate(QStringLiteral("%1:%2").arg(u.host()).arg(u.port(443)));
    }

    // --- Integration against a live server -------------------------------------

    void rejectsBadToken()
    {
        requireServer();
        ApiClient api(&m_store);
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), QStringLiteral("tk_definitelywrong"), cb); });
        QVERIFY(!r.ok);
        QVERIFY(!api.authenticated());
    }

    void fullCrudFlow()
    {
        requireServer();
        ApiClient api(&m_store);
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), token(), cb); });
        QVERIFY2(r.ok, qPrintable(r.error));
        QVERIFY(api.authenticated());
        QCOMPARE(api.authMethod(), QStringLiteral("token"));

        // Project
        QVariantMap project;
        project.insert(QStringLiteral("title"), QStringLiteral("Sailfish test project"));
        r = req(api, QStringLiteral("PUT"), QStringLiteral("/projects"), project);
        QVERIFY2(r.ok, qPrintable(r.error));
        const int projectId = r.data.toMap().value(QStringLiteral("id")).toInt();
        QVERIFY(projectId > 0);

        // Task create + update
        QVariantMap task;
        task.insert(QStringLiteral("title"), QStringLiteral("Write the Sailfish port"));
        task.insert(QStringLiteral("description"), QStringLiteral("<p>Hello</p>"));
        task.insert(QStringLiteral("priority"), 3);
        r = req(api, QStringLiteral("PUT"), QStringLiteral("/projects/%1/tasks").arg(projectId), task);
        QVERIFY2(r.ok, qPrintable(r.error));
        QVariantMap created = r.data.toMap();
        const int taskId = created.value(QStringLiteral("id")).toInt();
        QVERIFY(taskId > 0);

        created.insert(QStringLiteral("done"), true);
        created.insert(QStringLiteral("due_date"), QStringLiteral("2030-01-02T10:00:00Z"));
        QVariantList reminders;
        QVariantMap reminder;
        reminder.insert(QStringLiteral("reminder"), QStringLiteral("2030-01-02T09:00:00Z"));
        reminders << reminder;
        created.insert(QStringLiteral("reminders"), reminders);
        r = req(api, QStringLiteral("POST"), QStringLiteral("/tasks/%1").arg(taskId), created);
        QVERIFY2(r.ok, qPrintable(r.error));
        QCOMPARE(r.data.toMap().value(QStringLiteral("done")).toBool(), true);
        QCOMPARE(r.data.toMap().value(QStringLiteral("reminders")).toList().size(), 1);

        r = req(api, QStringLiteral("GET"), QStringLiteral("/tasks/%1").arg(taskId));
        QVERIFY(r.ok);
        QCOMPARE(r.data.toMap().value(QStringLiteral("due_date")).toString(), QStringLiteral("2030-01-02T10:00:00Z"));

        // Filtered listing with repeated query keys
        QVariantMap query;
        query.insert(QStringLiteral("filter"), QStringLiteral("done = true"));
        query.insert(QStringLiteral("sort_by"), QVariantList() << QStringLiteral("due_date") << QStringLiteral("id"));
        query.insert(QStringLiteral("order_by"), QVariantList() << QStringLiteral("asc") << QStringLiteral("desc"));
        r = req(api, QStringLiteral("GET"), QStringLiteral("/tasks"), QVariant(), query);
        QVERIFY2(r.ok, qPrintable(r.error));
        bool listed = false;
        for (const QVariant &t : r.data.toList())
            listed |= t.toMap().value(QStringLiteral("id")).toInt() == taskId;
        QVERIFY(listed);

        // Labels
        QVariantMap label;
        label.insert(QStringLiteral("title"), QStringLiteral("sailfish"));
        label.insert(QStringLiteral("hex_color"), QStringLiteral("1973ff"));
        r = req(api, QStringLiteral("PUT"), QStringLiteral("/labels"), label);
        QVERIFY2(r.ok, qPrintable(r.error));
        const int labelId = r.data.toMap().value(QStringLiteral("id")).toInt();
        QVariantMap bulk;
        QVariantMap labelRef;
        labelRef.insert(QStringLiteral("id"), labelId);
        bulk.insert(QStringLiteral("labels"), QVariantList() << labelRef);
        r = req(api, QStringLiteral("POST"), QStringLiteral("/tasks/%1/labels/bulk").arg(taskId), bulk);
        QVERIFY2(r.ok, qPrintable(r.error));
        r = req(api, QStringLiteral("GET"), QStringLiteral("/tasks/%1").arg(taskId));
        QCOMPARE(r.data.toMap().value(QStringLiteral("labels")).toList().size(), 1);

        // Comments
        QVariantMap comment;
        comment.insert(QStringLiteral("comment"), QStringLiteral("<p>First!</p>"));
        r = req(api, QStringLiteral("PUT"), QStringLiteral("/tasks/%1/comments").arg(taskId), comment);
        QVERIFY2(r.ok, qPrintable(r.error));
        const int commentId = r.data.toMap().value(QStringLiteral("id")).toInt();
        comment.insert(QStringLiteral("comment"), QStringLiteral("<p>Edited</p>"));
        r = req(api, QStringLiteral("POST"), QStringLiteral("/tasks/%1/comments/%2").arg(taskId).arg(commentId), comment);
        QVERIFY2(r.ok, qPrintable(r.error));
        r = req(api, QStringLiteral("GET"), QStringLiteral("/tasks/%1/comments").arg(taskId));
        QCOMPARE(r.data.toList().size(), 1);
        QCOMPARE(r.data.toList().first().toMap().value(QStringLiteral("comment")).toString(), QStringLiteral("<p>Edited</p>"));
        r = req(api, QStringLiteral("DELETE"), QStringLiteral("/tasks/%1/comments/%2").arg(taskId).arg(commentId));
        QVERIFY2(r.ok, qPrintable(r.error));

        // Kanban: find the kanban view, add a bucket, move the task there
        r = req(api, QStringLiteral("GET"), QStringLiteral("/projects/%1/views").arg(projectId));
        QVERIFY2(r.ok, qPrintable(r.error));
        int kanbanId = 0;
        for (const QVariant &v : r.data.toList()) {
            if (v.toMap().value(QStringLiteral("view_kind")).toString() == QLatin1String("kanban"))
                kanbanId = v.toMap().value(QStringLiteral("id")).toInt();
        }
        QVERIFY(kanbanId > 0);
        QVariantMap bucket;
        bucket.insert(QStringLiteral("title"), QStringLiteral("Review"));
        bucket.insert(QStringLiteral("limit"), 3);
        r = req(api, QStringLiteral("PUT"), QStringLiteral("/projects/%1/views/%2/buckets").arg(projectId).arg(kanbanId), bucket);
        QVERIFY2(r.ok, qPrintable(r.error));
        const int bucketId = r.data.toMap().value(QStringLiteral("id")).toInt();
        QVariantMap move;
        move.insert(QStringLiteral("task_id"), taskId);
        move.insert(QStringLiteral("bucket_id"), bucketId);
        move.insert(QStringLiteral("project_view_id"), kanbanId);
        move.insert(QStringLiteral("project_id"), projectId);
        r = req(api, QStringLiteral("POST"), QStringLiteral("/projects/%1/views/%2/buckets/%3/tasks").arg(projectId).arg(kanbanId).arg(bucketId), move);
        QVERIFY2(r.ok, qPrintable(r.error));
        r = req(api, QStringLiteral("GET"), QStringLiteral("/projects/%1/views/%2/tasks").arg(projectId).arg(kanbanId));
        QVERIFY2(r.ok, qPrintable(r.error));
        bool inBucket = false;
        for (const QVariant &b : r.data.toList()) {
            const QVariantMap bm = b.toMap();
            if (bm.value(QStringLiteral("id")).toInt() != bucketId)
                continue;
            for (const QVariant &t : bm.value(QStringLiteral("tasks")).toList())
                inBucket |= t.toMap().value(QStringLiteral("id")).toInt() == taskId;
        }
        QVERIFY(inBucket);

        // Attachment download with a hostile file name
        const QString attachment = qEnvironmentVariable("VIKUNJA_TEST_ATTACHMENT");
        if (!attachment.isEmpty()) {
            const QStringList parts = attachment.split(QLatin1Char(':'));
            QTemporaryDir dir;
            r = wait([&](ApiClient::Callback cb) {
                api.downloadNative(parts.at(0).toInt(), parts.at(1).toInt(), QStringLiteral("../../escape.txt"), dir.path(), cb);
            });
            QVERIFY2(r.ok, qPrintable(r.error));
            QCOMPARE(r.data.toString(), dir.path() + QStringLiteral("/escape.txt"));
            QVERIFY(QFile::exists(dir.path() + QStringLiteral("/escape.txt")));
        }

        // Cleanup
        r = req(api, QStringLiteral("DELETE"), QStringLiteral("/tasks/%1").arg(taskId));
        QVERIFY2(r.ok, qPrintable(r.error));
        r = req(api, QStringLiteral("DELETE"), QStringLiteral("/labels/%1").arg(labelId));
        QVERIFY2(r.ok, qPrintable(r.error));
        r = req(api, QStringLiteral("DELETE"), QStringLiteral("/projects/%1").arg(projectId));
        QVERIFY2(r.ok, qPrintable(r.error));

        api.logout();
        QVERIFY(!api.authenticated());
        QVERIFY(!api.restoreSession());
    }

    void sessionExpiresAfterInactivity()
    {
        requireServer();
        ApiClient api(&m_store);
        api.setSetting(QStringLiteral("layout/1"), QStringLiteral("list"));
        api.setSetting(QStringLiteral("theme"), QStringLiteral("dark"));
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), token(), cb); });
        QVERIFY2(r.ok, qPrintable(r.error));

        // Used 29 days ago: still signed in.
        {
            ApiClient again(&m_store);
            again.setLastUsedForTest(QDateTime::currentDateTimeUtc().addDays(-29));
            QVERIFY(again.restoreSession());
            again.touchSession(); // opening the app restarts the 30 days
        }
        {
            ApiClient again(&m_store);
            QVERIFY(again.restoreSession());
            // 31 days without opening the app: signed out, token wiped.
            again.setLastUsedForTest(QDateTime::currentDateTimeUtc().addDays(-31));
        }
        ApiClient later(&m_store);
        QVERIFY(!later.restoreSession());
        QCOMPARE(later.sessionNotice(), QStringLiteral("inactive"));
        QVERIFY(!later.authenticated());
        ApiClient after(&m_store);
        QVERIFY(!after.restoreSession());
        bool found = true;
        m_store.read(QStringLiteral("api-token"), &found);
        QVERIFY(!found);
        // Account preferences are gone, the theme stays.
        QVERIFY(!after.setting(QStringLiteral("layout/1")).isValid());
        QCOMPARE(after.setting(QStringLiteral("theme")).toString(), QStringLiteral("dark"));
    }

    // A real restart: a new process has a new SecureStore with nothing cached
    // in memory. No Secrets daemon runs in the test environment, so this goes
    // through the same fallback the phone uses when Secrets refuses the token.
    void sessionSurvivesRestart()
    {
        requireServer();
        qunsetenv("HARBOUR_VIKUNJA_MEMORY_STORE");
        const QString file = SecureStore::privateDir() + QStringLiteral("/api-token.secret");
        QFile::remove(file);
        QSettings(AppSettings::path(), QSettings::IniFormat).remove(QStringLiteral("security/fileFallback"));
        {
            // Not asked yet: nothing is written, the app asks first.
            SecureStore store;
            QVERIFY(store.init());
            QVERIFY(store.persistent());
            ApiClient api(&store);
            ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), token(), cb); });
            QVERIFY2(r.ok, qPrintable(r.error));
            QVERIFY(!api.secretsWorking());
            QVERIFY(api.storageChoiceNeeded());
            QCOMPARE(api.tokenStorage(), QStringLiteral("memory"));
            QVERIFY(!QFile::exists(file));
            // "Don't": still nothing on disk, and no second prompt.
            api.setFileFallback(false);
            QVERIFY(!api.storageChoiceNeeded());
            QVERIFY(!QFile::exists(file));
        }
        {
            SecureStore store;
            store.init();
            ApiClient api(&store);
            QVERIFY(!api.restoreSession());
            ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), token(), cb); });
            QVERIFY2(r.ok, qPrintable(r.error));
            QVERIFY(!api.storageChoiceNeeded());
            QVERIFY(!QFile::exists(file));
            // Changed in Settings: the current token is saved right away.
            api.setFileFallback(true);
            QCOMPARE(api.tokenStorage(), QStringLiteral("file"));
        }
        QVERIFY(QFile::exists(file));
        // Owner only: no group or other bits on the file or its folder.
        const QFileDevice::Permissions others = QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ExeGroup
                | QFileDevice::ReadOther | QFileDevice::WriteOther | QFileDevice::ExeOther;
        QCOMPARE(int(QFile::permissions(file) & others), 0);
        QCOMPARE(int(QFile::permissions(file) & QFileDevice::ExeOwner), 0);
        QCOMPARE(int(QFileInfo(SecureStore::privateDir()).permissions() & others), 0);
        {
            SecureStore store;
            store.init();
            ApiClient api(&store);
            QVERIFY(api.restoreSession());
            QVERIFY(api.authenticated());
            ApiClient::Result r = req(api, QStringLiteral("GET"), QStringLiteral("/user"));
            QVERIFY2(r.ok, qPrintable(r.error));
            api.logout();
        }
        QVERIFY(!QFile::exists(file));
        {
            SecureStore store;
            store.init();
            ApiClient api(&store);
            QVERIFY(!api.restoreSession());
            // Sign in again, then leave the app unused for 31 days.
            ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), token(), cb); });
            QVERIFY2(r.ok, qPrintable(r.error));
            api.setLastUsedForTest(QDateTime::currentDateTimeUtc().addDays(-31));
        }
        QVERIFY(QFile::exists(file));
        {
            SecureStore store;
            store.init();
            ApiClient api(&store);
            QVERIFY(!api.restoreSession());
            QCOMPARE(api.sessionNotice(), QStringLiteral("inactive"));
        }
        QVERIFY(!QFile::exists(file));
        {
            // Saying no later deletes the file.
            SecureStore store;
            store.init();
            ApiClient api(&store);
            ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), token(), cb); });
            QVERIFY2(r.ok, qPrintable(r.error));
            QVERIFY(QFile::exists(file));
            api.setFileFallback(false);
            QVERIFY(!QFile::exists(file));
            api.logout();
        }
        QSettings(AppSettings::path(), QSettings::IniFormat).remove(QStringLiteral("security/fileFallback"));
        qputenv("HARBOUR_VIKUNJA_MEMORY_STORE", "1");
    }

    // The token is split between Secrets and a pad file in the private folder.
    // Uses a stand-in for the Secrets daemon (none runs in the build engine).
    void splitTokenStorage()
    {
        qunsetenv("HARBOUR_VIKUNJA_MEMORY_STORE");
        QHash<QString, QByteArray> fake;
        SecureStore::s_fakeSecrets = &fake;
        const QString pad = SecureStore::privateDir() + QStringLiteral("/api-token.pad");
        const QByteArray token = "tk_0123456789abcdef0123456789abcdef";
        {
            SecureStore store;
            store.init();
            QVERIFY(store.write(QStringLiteral("api-token"), token));
            QCOMPARE(store.backend(), SecureStore::Secrets);
        }
        // Neither half holds the token.
        QVERIFY(QFile::exists(pad));
        QCOMPARE(QFile::permissions(pad) & (QFileDevice::ReadGroup | QFileDevice::ReadOther), QFileDevice::Permissions());
        const QByteArray cipher = fake.value(QStringLiteral("harbourvikunjasplit/api-token"));
        QFile padFile(pad);
        QVERIFY(padFile.open(QIODevice::ReadOnly));
        const QByteArray padData = padFile.readAll();
        padFile.close();
        QCOMPARE(cipher.size(), token.size());
        QVERIFY(cipher != token && padData != token);
        // A new process (launcher or reminder start) reads it back.
        {
            SecureStore store;
            store.init();
            bool found = false;
            QCOMPARE(store.read(QStringLiteral("api-token"), &found), token);
            QVERIFY(found);
        }
        // Without the pad the Secrets half is useless.
        QFile::rename(pad, pad + QStringLiteral(".bak"));
        {
            SecureStore store;
            store.init();
            bool found = true;
            store.read(QStringLiteral("api-token"), &found);
            QVERIFY(!found);
        }
        QFile::rename(pad + QStringLiteral(".bak"), pad);
        // Sign-out removes both halves.
        {
            SecureStore store;
            store.init();
            store.remove(QStringLiteral("api-token"));
        }
        QVERIFY(!QFile::exists(pad));
        QVERIFY(fake.isEmpty());
        // A token from 0.2.1 - 0.2.6 (whole, owner-only collection) is moved.
        fake.insert(QStringLiteral("harbourvikunjasession/api-token"), token);
        {
            SecureStore store;
            store.init();
            bool found = false;
            QCOMPARE(store.read(QStringLiteral("api-token"), &found), token);
            QVERIFY(found);
        }
        QVERIFY(!fake.contains(QStringLiteral("harbourvikunjasession/api-token")));
        QVERIFY(fake.contains(QStringLiteral("harbourvikunjasplit/api-token")));
        QVERIFY(QFile::exists(pad));
        {
            SecureStore store;
            store.init();
            bool found = false;
            QCOMPARE(store.read(QStringLiteral("api-token"), &found), token);
            store.remove(QStringLiteral("api-token"));
        }
        SecureStore::s_fakeSecrets = nullptr;
        qputenv("HARBOUR_VIKUNJA_MEMORY_STORE", "1");
    }

    // "+" in a query value must reach the server as "+", not as a space.
    void queryPlusIsEncoded()
    {
        requireServer();
        ApiClient api(&m_store);
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), token(), cb); });
        QVERIFY2(r.ok, qPrintable(r.error));
        QVariantMap q;
        q.insert(QStringLiteral("filter"), QStringLiteral("done = false && due_date < now+2d"));
        q.insert(QStringLiteral("filter_include_nulls"), QStringLiteral("false"));
        r = req(api, QStringLiteral("GET"), QStringLiteral("/tasks"), QVariant(), q);
        QVERIFY2(r.ok, qPrintable(r.error));
        api.logout();
    }

    void attachmentUploadAndPreview()
    {
        requireServer();
        ApiClient api(&m_store);
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithTokenNative(url(), token(), cb); });
        QVERIFY2(r.ok, qPrintable(r.error));
        QVariantMap project;
        project.insert(QStringLiteral("title"), QStringLiteral("Attachment test"));
        r = req(api, QStringLiteral("PUT"), QStringLiteral("/projects"), project);
        QVERIFY2(r.ok, qPrintable(r.error));
        const int projectId = r.data.toMap().value(QStringLiteral("id")).toInt();
        QVariantMap task;
        task.insert(QStringLiteral("title"), QStringLiteral("Has a photo"));
        r = req(api, QStringLiteral("PUT"), QStringLiteral("/projects/%1/tasks").arg(projectId), task);
        QVERIFY2(r.ok, qPrintable(r.error));
        const int taskId = r.data.toMap().value(QStringLiteral("id")).toInt();

        // A picture in the user's Pictures folder, as the picker returns it.
        QDir pictures(QDir::homePath() + QStringLiteral("/Pictures"));
        pictures.mkpath(QStringLiteral("."));
        const QString photo = pictures.filePath(QStringLiteral("vikunja-test \"photo\".png"));
        QImage img(64, 48, QImage::Format_RGB32);
        img.fill(Qt::red);
        QVERIFY(img.save(photo, "PNG"));
        r = wait([&](ApiClient::Callback cb) { api.uploadNative(taskId, QStringLiteral("file://") + photo, cb); });
        QVERIFY2(r.ok, qPrintable(r.error));
        QFile::remove(photo);

        r = req(api, QStringLiteral("GET"), QStringLiteral("/tasks/%1").arg(taskId));
        const QVariantList atts = r.data.toMap().value(QStringLiteral("attachments")).toList();
        QCOMPARE(atts.size(), 1);
        const QVariantMap att = atts.first().toMap();
        QVERIFY(!att.value(QStringLiteral("file")).toMap().value(QStringLiteral("name")).toString().contains(QLatin1Char('"')));
        const int attId = att.value(QStringLiteral("id")).toInt();

        // Preview straight from memory.
        r = wait([&](ApiClient::Callback cb) { api.previewNative(taskId, attId, cb); });
        QVERIFY2(r.ok, qPrintable(r.error));
        const QString key = r.data.toString().mid(QStringLiteral("image://attachment/").size());
        QSize size;
        const QImage back = m_images->requestImage(key, &size, QSize());
        QCOMPARE(back.size(), QSize(64, 48));

        // Files outside the user's folders are refused.
        r = wait([&](ApiClient::Callback cb) { api.uploadNative(taskId, QStringLiteral("/etc/passwd"), cb); });
        QVERIFY(!r.ok);
        r = wait([&](ApiClient::Callback cb) {
            api.uploadNative(taskId, QSettings(AppSettings::path(), QSettings::IniFormat).fileName(), cb); // the app's own settings
        });
        QVERIFY(!r.ok);
        // Only Pictures, Documents and Downloads: not the rest of home, and
        // not Music or Videos, which the sandbox no longer grants.
        for (const QString &folder : { QStringLiteral("/Music"), QStringLiteral("/Videos"), QString() }) {
            QDir dir(QDir::homePath() + folder);
            dir.mkpath(QStringLiteral("."));
            const QString file = dir.filePath(QStringLiteral("vikunja-test-refused.png"));
            QVERIFY(img.save(file, "PNG"));
            r = wait([&](ApiClient::Callback cb) { api.uploadNative(taskId, file, cb); });
            QFile::remove(file);
            QVERIFY2(!r.ok, qPrintable(folder));
        }
        QDir docs(QDir::homePath() + QStringLiteral("/Documents"));
        docs.mkpath(QStringLiteral("."));
        const QString doc = docs.filePath(QStringLiteral("vikunja-test.png"));
        QVERIFY(img.save(doc, "PNG"));
        r = wait([&](ApiClient::Callback cb) { api.uploadNative(taskId, doc, cb); });
        QFile::remove(doc);
        QVERIFY2(r.ok, qPrintable(r.error));

        r = req(api, QStringLiteral("DELETE"), QStringLiteral("/projects/%1").arg(projectId));
        QVERIFY2(r.ok, qPrintable(r.error));
        // Signing out drops the preview cache.
        api.logout();
        QVERIFY(m_images->requestImage(key, &size, QSize()).isNull());
    }

    void twoFactorLogin()
    {
        const QString user = qEnvironmentVariable("VIKUNJA_TEST_TOTP_USER");
        const QString secret = qEnvironmentVariable("VIKUNJA_TEST_TOTP_SECRET");
        if (url().isEmpty() || user.isEmpty() || secret.isEmpty())
            QSKIP("VIKUNJA_TEST_TOTP_USER / VIKUNJA_TEST_TOTP_SECRET not set");
        const QString pass = qEnvironmentVariable("VIKUNJA_TEST_TOTP_PASSWORD");
        ApiClient api(&m_store);
        // Step 1: username and password only. The server asks for the code.
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithPasswordNative(url(), user, pass, QString(), cb); });
        QVERIFY(!r.ok);
        QCOMPARE(r.errorCode, QStringLiteral("totp_required"));
        QVERIFY(!api.authenticated());
        // A wrong code is rejected.
        r = wait([&](ApiClient::Callback cb) { api.loginWithPasswordNative(url(), user, pass, QStringLiteral("000000"), cb); });
        QVERIFY(!r.ok);
        QCOMPARE(r.errorCode, QStringLiteral("totp_invalid"));
        // Step 2: the right code.
        r = wait([&](ApiClient::Callback cb) { api.loginWithPasswordNative(url(), user, pass, totp(secret), cb); });
        QVERIFY2(r.ok, qPrintable(r.error));
        QVERIFY(api.authenticated());
        QCOMPARE(api.authMethod(), QStringLiteral("password"));
        api.logout();
    }

    void passwordLoginMintsScopedToken()
    {
        const QString user = qEnvironmentVariable("VIKUNJA_TEST_USER");
        const QString pass = qEnvironmentVariable("VIKUNJA_TEST_PASSWORD");
        if (url().isEmpty() || user.isEmpty())
            QSKIP("VIKUNJA_TEST_USER / VIKUNJA_TEST_PASSWORD not set");
        ApiClient api(&m_store);
        ApiClient::Result r = wait([&](ApiClient::Callback cb) { api.loginWithPasswordNative(url(), user, QStringLiteral("wrong"), QString(), cb); });
        QVERIFY(!r.ok);
        QVERIFY(!api.authenticated());

        r = wait([&](ApiClient::Callback cb) { api.loginWithPasswordNative(url(), user, pass, QString(), cb); });
        QVERIFY2(r.ok, qPrintable(r.error));
        QVERIFY(api.authenticated());
        QCOMPARE(api.authMethod(), QStringLiteral("password"));
        QVERIFY(!api.tokenExpires().isEmpty());

        // The minted token works for normal API calls...
        r = req(api, QStringLiteral("GET"), QStringLiteral("/projects"));
        QVERIFY2(r.ok, qPrintable(r.error));
        // ...but was not granted unrelated permissions such as teams.
        r = req(api, QStringLiteral("GET"), QStringLiteral("/teams"));
        QVERIFY(!r.ok);
        api.logout();
    }
};

QTEST_GUILESS_MAIN(TestHarbourVikunja)
#include "tst_harbour_vikunja.moc"
