#include <QGuiApplication>
#include <QNetworkAccessManager>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlNetworkAccessManagerFactory>
#include <QQuickView>
#include <QScopedPointer>
#include <QFile>
#include <QFileInfo>
#include <QSettings>
#include <QTimer>

#include <sailfishapp.h>
#include <cstdio>
#include <csignal>
#include <cstring>
#include <execinfo.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "alarms.h"
#include "apiclient.h"
#include "appsettings.h"
#include "attachmentimages.h"
#include "appbridge.h"
#include "redact.h"
#include "securestore.h"
#include "textutil.h"

namespace {
// Crash trace for the session log: written with plain system calls only, as
// nothing else is safe inside a signal handler.
char s_logPath[512];

void onFatalSignal(int sig)
{
    const int fd = ::open(s_logPath, O_WRONLY | O_APPEND | O_CREAT, 0600);
    if (fd >= 0) {
        char line[96];
        const int n = snprintf(line, sizeof line, "crash: signal %d (%s), pid %d\n", sig, strsignal(sig), int(getpid()));
        if (n > 0 && ::write(fd, line, size_t(n)) < 0) {}
        if (sig != SIGTERM) {
            void *frames[48];
            backtrace_symbols_fd(frames, backtrace(frames, 48), fd);
        }
        ::close(fd);
    }
    ::signal(sig, SIG_DFL);
    ::raise(sig);
}

void installCrashLog()
{
    qstrncpy(s_logPath, QFile::encodeName(AppSettings::logPath()).constData(), sizeof s_logPath);
    for (int sig : { SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTERM })
        ::signal(sig, onFatalSignal);
}

// QML never needs the network: all API traffic goes through ApiClient.
// Blocking the engine's own network access means rich text (task
// descriptions, comments) can never load remote images or other content.
class OfflineNamFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        QNetworkAccessManager *nam = new QNetworkAccessManager(parent);
        nam->setNetworkAccessible(QNetworkAccessManager::NotAccessible);
        return nam;
    }
};
}

int main(int argc, char *argv[])
{
    // Every file this process creates (settings, downloads) is private to
    // the user; sailjail additionally hides the app's data from other apps.
    umask(0077);
    Redact::installMessageHandler();

    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setOrganizationName(QStringLiteral("io.github.manojgudi"));
    app->setApplicationName(QStringLiteral("harbour-vikunja"));
    app->setApplicationVersion(QStringLiteral(APP_VERSION));

    // Processes started by D-Bus activation may lack XDG_RUNTIME_DIR, and
    // Sailfish Secrets finds its daemon socket through it.
    if (qgetenv("XDG_RUNTIME_DIR").isEmpty()) {
        const QByteArray runtime = "/run/user/" + QByteArray::number(uint(getuid()));
        if (QFileInfo(QString::fromLatin1(runtime)).isDir())
            qputenv("XDG_RUNTIME_DIR", runtime);
    }
    AppSettings::diag(QStringLiteral("start: args=%1 XDG_RUNTIME_DIR=%2 DBUS_SESSION_BUS_ADDRESS set=%3")
                      .arg(app->arguments().mid(1).join(QLatin1Char(' ')))
                      .arg(QString::fromLocal8Bit(qgetenv("XDG_RUNTIME_DIR")))
                      .arg(!qgetenv("DBUS_SESSION_BUS_ADDRESS").isEmpty()));
    installCrashLog();
    QObject::connect(app.data(), &QCoreApplication::aboutToQuit, []() {
        AppSettings::diag(QStringLiteral("exit: quitting normally"));
    });

    SecureStore store;
    store.init();

    ApiClient api(&store);
    // Restore the session before any QML or D-Bus call can run. Talking to
    // Secrets spins a local event loop; done later, a reminder call arriving
    // during that loop restored the session a second time, re-entrantly, and
    // that second attempt found nothing and sent the window to the login page.
    api.restoreSession();
    Util util;
    AppBridge bridge;
    // sailjail starts the app with -prestart when timed or a notification
    // action needs it (ExecDBus); the window stays hidden until asked for.
    bridge.setBackground(app->arguments().contains(QStringLiteral("-prestart")));
    Alarms alarms;

    QScopedPointer<QQuickView> view(SailfishApp::createView());
    OfflineNamFactory namFactory;
    view->engine()->setNetworkAccessManagerFactory(&namFactory);
    api.setEngine(view->engine());
    view->engine()->addImageProvider(QStringLiteral("attachment"), new AttachmentImages);

    view->rootContext()->setContextProperty(QStringLiteral("api"), &api);
    view->rootContext()->setContextProperty(QStringLiteral("util"), &util);
    view->rootContext()->setContextProperty(QStringLiteral("appBridge"), &bridge);
    view->rootContext()->setContextProperty(QStringLiteral("alarms"), &alarms);
    view->rootContext()->setContextProperty(QStringLiteral("appVersion"), QStringLiteral(APP_VERSION));

    view->setSource(SailfishApp::pathToMainQml());
    // Only claim the bus name once the QML that handles the calls exists:
    // until then the bus keeps the call that started us (D-Bus activation)
    // waiting, instead of it arriving with nobody listening.
    const bool onBus = bridge.registerOnBus();
    AppSettings::diag(QStringLiteral("dbus: registered=%1 name=%2").arg(onBus).arg(bridge.service()));
    QQuickView *window = view.data();
    QObject::connect(&bridge, &AppBridge::showRequested, window, [window]() {
        AppSettings::diag(QStringLiteral("window: show, visible=%1").arg(window->isVisible()));
        if (!window->isVisible())
            window->showFullScreen();
        window->raise();
        window->requestActivate();
    });
    // Silica crashes in its aboutToQuit handler when the app quits without its
    // window ever having been shown (seen in the background test), so a
    // background instance saves its settings and leaves directly.
    QObject::connect(window, &QWindow::visibleChanged, window, [](bool visible) {
        AppSettings::diag(QStringLiteral("window: visible=%1").arg(visible));
    });
    QObject::connect(&bridge, &AppBridge::backgroundFinished, &api, [&api]() {
        AppSettings::diag(QStringLiteral("exit: background work done"));
        api.syncSettings();
        fflush(nullptr);
        ::_exit(0);
    });
    if (!bridge.background())
        view->show();
    else // Nothing asked for in time (e.g. a stale activation): just exit.
        QTimer::singleShot(60000, &bridge, &AppBridge::quitIfIdle);
    return app->exec();
}
