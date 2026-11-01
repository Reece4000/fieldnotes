#include <QtQuickTest/quicktest.h>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWheelEvent>

class EditorTestSetup : public QObject {
    Q_OBJECT
public:
    Q_INVOKABLE void pixelScroll(QQuickItem *item, int delta, int phase) {
        auto *window = item->window();
        const auto position = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
        QWheelEvent event(position, window->mapToGlobal(position), QPoint(0, delta), QPoint(),
                          Qt::NoButton, Qt::NoModifier, static_cast<Qt::ScrollPhase>(phase), false,
                          Qt::MouseEventSynthesizedBySystem);
        QCoreApplication::sendEvent(window, &event);
    }
public slots:
    void qmlEngineAvailable(QQmlEngine *engine) {
        engine->rootContext()->setContextProperty("trackpad", this);
    }
};

QUICK_TEST_MAIN_WITH_SETUP(fieldnotes_editor, EditorTestSetup)
#include "test_editor.moc"
