#include <QGuiApplication>
#include <QNetworkAccessManager>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlNetworkAccessManagerFactory>
#include <QQuickView>
#include <QScopedPointer>
#include <QSettings>

#include <sailfishapp.h>
#include <sys/stat.h>

#include "apiclient.h"
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
    bridge.registerOnBus();

    QScopedPointer<QQuickView> view(SailfishApp::createView());
    OfflineNamFactory namFactory;
    view->engine()->setNetworkAccessManagerFactory(&namFactory);
    api.setEngine(view->engine());

    view->rootContext()->setContextProperty(QStringLiteral("api"), &api);
    view->rootContext()->setContextProperty(QStringLiteral("util"), &util);
    view->rootContext()->setContextProperty(QStringLiteral("appBridge"), &bridge);
    view->rootContext()->setContextProperty(QStringLiteral("appVersion"), QStringLiteral(APP_VERSION));

    view->setSource(SailfishApp::pathToMainQml());
    view->show();
    return app->exec();
}
