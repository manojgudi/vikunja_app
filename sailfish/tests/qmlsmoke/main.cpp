// Loads the real app QML with the real C++ backend, walks through every
// page against a live server and fails on any QML warning or JS error.
// Run with QT_QPA_PLATFORM=minimal: nothing is rendered, but every page is
// instantiated and its bindings and handlers are evaluated.
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QStringList>
#include <QTimer>
#include <QDir>
#include <QScopedPointer>
#include <QImage>
#include <QQuickItem>
#include <QQuickView>
#include <cstdio>

#include "alarms.h"
#include "apiclient.h"
#include "attachmentimages.h"
#include "appbridge.h"
#include "securestore.h"
#include "textutil.h"

static QStringList problems;

static void handler(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
    fprintf(stderr, "%s\n", qPrintable(msg));
    if (msg.startsWith(QLatin1String("SMOKE:")))
        return;
    // No Secrets daemon in the build engine; the store falls back by design.
    if (msg.contains(QLatin1String("secrets daemon")) || msg.startsWith(QLatin1String("vikunja-session:")))
        return;
    if (type != QtDebugMsg && type != QtInfoMsg
            && (msg.contains(QLatin1String(".qml")) || msg.contains(QLatin1String(".js"))
                || msg.contains(QLatin1String("Error"))))
        problems << msg;
}

int main(int argc, char **argv)
{
    // The restart test needs the real store; every other run stays in memory.
    if (!qEnvironmentVariableIsSet("SMOKE_PERSIST"))
        qputenv("HARBOUR_VIKUNJA_MEMORY_STORE", "1");
    qInstallMessageHandler(handler);
    QGuiApplication app(argc, argv);
    if (qEnvironmentVariableIsSet("SMOKE_REAL_NAMES")) {
        // Same settings and private folder as the installed app (e2e test).
        app.setOrganizationName(QStringLiteral("io.github.manojgudi"));
        app.setApplicationName(QStringLiteral("harbour-vikunja"));
    } else {
        app.setOrganizationName(QStringLiteral("harbour-vikunja-smoke"));
        app.setApplicationName(QStringLiteral("smoke"));
    }

    const QString qmlDir = QString::fromLocal8Bit(qgetenv("SMOKE_QML_DIR"));
    SecureStore store;
    store.init();
    ApiClient api(&store);
    api.restoreSession(); // as the app's main() does
    Util util;
    AppBridge bridge;
    Alarms alarms;
    // Like a start by D-Bus activation (-prestart): no window until asked.
    if (qEnvironmentVariableIsSet("SMOKE_BACKGROUND"))
        bridge.setBackground(true);
    if (qEnvironmentVariableIsSet("SMOKE_REGISTER_BUS"))
        bridge.registerOnBus();

    QQmlEngine engine;
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QCoreApplication::quit);
    api.setEngine(&engine);
    engine.addImageProvider(QStringLiteral("attachment"), new AttachmentImages);
    engine.rootContext()->setContextProperty(QStringLiteral("api"), &api);
    engine.rootContext()->setContextProperty(QStringLiteral("util"), &util);
    engine.rootContext()->setContextProperty(QStringLiteral("appBridge"), &bridge);
    engine.rootContext()->setContextProperty(QStringLiteral("alarms"), &alarms);
    engine.rootContext()->setContextProperty(QStringLiteral("appVersion"), QStringLiteral("smoke"));
    engine.rootContext()->setContextProperty(QStringLiteral("smokeUrl"), QString::fromLocal8Bit(qgetenv("VIKUNJA_TEST_URL")));
    engine.rootContext()->setContextProperty(QStringLiteral("smokeToken"), QString::fromLocal8Bit(qgetenv("VIKUNJA_TEST_TOKEN")));
    engine.rootContext()->setContextProperty(QStringLiteral("smokeQmlDir"), qmlDir);
    engine.rootContext()->setContextProperty(QStringLiteral("smokeUser"), QString::fromLocal8Bit(qgetenv("VIKUNJA_TEST_USER")));
    engine.rootContext()->setContextProperty(QStringLiteral("smokePassword"), QString::fromLocal8Bit(qgetenv("VIKUNJA_TEST_PASSWORD")));
    engine.rootContext()->setContextProperty(QStringLiteral("homeDir"), QDir::homePath());
    engine.rootContext()->setContextProperty(QStringLiteral("shotDir"), QString::fromLocal8Bit(qgetenv("SMOKE_SHOT_DIR")));
    engine.rootContext()->setContextProperty(QStringLiteral("smokePhase"), QString::fromLocal8Bit(qgetenv("SMOKE_PHASE")));

    // A photo in ~/Pictures, as the file picker would return it.
    QDir pictures(QDir::homePath() + QStringLiteral("/Pictures"));
    pictures.mkpath(QStringLiteral("."));
    const QString photo = pictures.filePath(QStringLiteral("smoke-photo.png"));
    QImage img(120, 80, QImage::Format_RGB32);
    img.fill(Qt::blue);
    img.save(photo, "PNG");
    engine.rootContext()->setContextProperty(QStringLiteral("smokePhoto"), photo);

    // Screenshots: the app's window shown in a real view, as main() does.
    QScopedPointer<QQuickView> view;
    if (qEnvironmentVariableIsSet("SMOKE_VIEW")) {
        view.reset(new QQuickView(&engine, nullptr));
        view->setResizeMode(QQuickView::SizeRootObjectToView);
        view->resize(540, 1080);
        view->setSource(QUrl::fromLocalFile(qmlDir + QStringLiteral("/harbour-vikunja.qml")));
        view->show();
        engine.rootContext()->setContextProperty(QStringLiteral("smokeRoot"), view->rootObject());
    } else {
        engine.rootContext()->setContextProperty(QStringLiteral("smokeRoot"), nullptr);
    }

    QQmlComponent driver(&engine, QUrl::fromLocalFile(QString::fromLocal8Bit(qgetenv("SMOKE_DRIVER"))));
    QObject *obj = driver.create();
    if (!obj) {
        for (const QQmlError &e : driver.errors())
            fprintf(stderr, "%s\n", qPrintable(e.toString()));
        return 2;
    }
    QTimer::singleShot(180000, &app, &QCoreApplication::quit);
    app.exec();
    const bool finished = obj->property("finished").toBool();
    const int steps = obj->property("steps").toInt();
    fprintf(stderr, "\nSMOKE RESULT: %d steps, finished=%d, %d problem(s)\n", steps, finished, problems.size());
    for (const QString &p : problems)
        fprintf(stderr, "  PROBLEM: %s\n", qPrintable(p));
    return (finished && problems.isEmpty()) ? 0 : 1;
}
