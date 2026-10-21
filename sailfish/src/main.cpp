#include <QGuiApplication>
#include <QNetworkAccessManager>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlNetworkAccessManagerFactory>
#include <QQuickView>
#include <QScopedPointer>
#include <QSettings>
#include <QTimer>

#include <sailfishapp.h>
#include <cstdio>
#include <sys/stat.h>
#include <unistd.h>

#include "alarms.h"
#include "apiclient.h"
#include "attachmentimages.h"
#include "appbridge.h"
#include "redact.h"
#include "securestore.h"
#include "textutil.h"

namespace {
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

    SecureStore store;
    store.init();

    ApiClient api(&store);
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
    bridge.registerOnBus();
    QQuickView *window = view.data();
    QObject::connect(&bridge, &AppBridge::showRequested, window, [window]() {
        if (!window->isVisible())
            window->showFullScreen();
        window->raise();
        window->requestActivate();
    });
    // Silica crashes in its aboutToQuit handler when the app quits without its
    // window ever having been shown (seen in the background test), so a
    // background instance saves its settings and leaves directly.
    QObject::connect(&bridge, &AppBridge::backgroundFinished, &api, [&api]() {
        api.syncSettings();
        QSettings().sync();
        fflush(nullptr);
        ::_exit(0);
    });
    if (!bridge.background())
        view->show();
    else // Nothing asked for in time (e.g. a stale activation): just exit.
        QTimer::singleShot(60000, &bridge, &AppBridge::quitIfIdle);
    return app->exec();
}
