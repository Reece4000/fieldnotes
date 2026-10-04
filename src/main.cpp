#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStyleHints>
#include <QWindow>
#include <QLockFile>
#include <QStandardPaths>
#include <QDir>
#include <sys/stat.h>
#include "controller.h"

void fieldnotesStyleWindow(QWindow *window);

int main(int argc, char *argv[]) {
    umask(0077);
    QGuiApplication app(argc, argv);
    app.setApplicationName("Fieldnotes");
    app.setOrganizationName("Fieldnotes");
    app.setApplicationVersion("0.3.0");
    app.styleHints()->setColorScheme(Qt::ColorScheme::Light);
    QQuickStyle::setStyle("Basic");
    QString data = qEnvironmentVariable("FIELDNOTES_DATA_DIR");
    if (data.isEmpty()) data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/Fieldnotes";
    QDir().mkpath(data);
    QLockFile lock(data + "/window.lock");
    lock.setStaleLockTime(0);
    if (!lock.tryLock(100)) return 0;
    Controller controller;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("appController", &controller);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Fieldnotes", "Main");
    if (engine.rootObjects().isEmpty()) return 1;
    if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().first())) fieldnotesStyleWindow(window);
    controller.start();
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &controller, &Controller::shutdown);
    return app.exec();
}
