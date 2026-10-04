#include "controller.h"
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QtTest>
#include <memory>

// These tests exercise public controller commands through its real QProcess.
bool fieldnotesSystemReduceMotion() { return false; }

class SaveDebounceTest : public QObject {
    Q_OBJECT
    std::unique_ptr<QTemporaryDir> data;
    std::unique_ptr<Controller> controller;
    QList<QJsonObject> commands(const QString &action = {}) {
        QFile log(data->filePath("commands.jsonl"));
        if (!log.open(QIODevice::ReadOnly)) return {};
        QList<QJsonObject> result;
        for (const auto &line : log.readAll().split('\n')) {
            if (line.isEmpty()) continue;
            const auto command = QJsonDocument::fromJson(line).object();
            if (action.isEmpty() || command.value("action").toString() == action) result.append(command);
        }
        return result;
    }
private slots:
    void init() {
        data = std::make_unique<QTemporaryDir>();
        QVERIFY(data->isValid());
        qputenv("FIELDNOTES_DATA_DIR", data->path().toUtf8());
        qputenv("FIELDNOTES_TEST_COMMANDS", data->filePath("commands.jsonl").toUtf8());
        qunsetenv("FIELDNOTES_TEST_ACK_DELAY");
        controller = std::make_unique<Controller>();
        controller->start();
        QTRY_VERIFY_WITH_TIMEOUT(controller->connected(), 5000);
        QCOMPARE(controller->selectedId(), QString("first"));
    }
    void cleanup() {
        controller.reset();
        data.reset();
        qunsetenv("FIELDNOTES_DATA_DIR");
        qunsetenv("FIELDNOTES_TEST_COMMANDS");
        qunsetenv("FIELDNOTES_TEST_ACK_DELAY");
    }
    void batchesLatestTitleAndBodyAfterQuietPeriod() {
        controller->updateBody("First keystrokes");
        QTest::qWait(250);
        controller->updateTitle("Latest title");
        QTest::qWait(300);
        controller->updateBody("Latest complete transcript");
        QElapsedTimer quiet; quiet.start();
        QTest::qWait(600);
        QCOMPARE(commands("update").size(), 0);
        QVERIFY(controller->saving());
        QCOMPARE(controller->body(), QString("Latest complete transcript"));
        QTRY_VERIFY_WITH_TIMEOUT(!controller->saving(), 2000);
        QVERIFY(quiet.elapsed() >= 700);
        const auto updates = commands("update");
        QCOMPARE(updates.size(), 1);
        QCOMPARE(updates.first().value("body").toString(), QString("Latest complete transcript"));
        QCOMPARE(updates.first().value("title").toString(), QString("Latest title"));
    }
    void switchingNotesFlushesToOriginalNoteBeforeSelection() {
        controller->updateBody("Pending first note");
        controller->selectNote("second");
        QTRY_COMPARE_WITH_TIMEOUT(controller->selectedId(), QString("second"), 2000);
        const auto updates = commands("update");
        QCOMPARE(updates.size(), 1);
        QCOMPARE(updates.first().value("id").toString(), QString("first"));
        QCOMPARE(updates.first().value("body").toString(), QString("Pending first note"));
        const auto all = commands();
        int update = -1, select = -1;
        for (int i = 0; i < all.size(); ++i) {
            if (all[i].value("action") == "update") update = i;
            if (all[i].value("action") == "select") select = i;
        }
        QVERIFY(update >= 0 && select > update);
        QCOMPARE(controller->body(), QString("Original second"));
        controller->selectNote("first");
        QTRY_COMPARE_WITH_TIMEOUT(controller->body(), QString("Pending first note"), 2000);
    }
    void closingFlushesBeforeShutdown() {
        controller->updateBody("Last keystroke before quitting");
        controller->shutdown();
        const auto updates = commands("update");
        QCOMPARE(updates.size(), 1);
        QCOMPARE(updates.first().value("body").toString(), QString("Last keystroke before quitting"));
        QCOMPARE(commands().last().value("action").toString(), QString("shutdown"));
    }
    void organisationChangesFlushImmediatelyWithText() {
        controller->updateBody("Pending text");
        controller->updateCollection("HCI tests");
        QTRY_VERIFY_WITH_TIMEOUT(!controller->saving(), 500);
        const auto updates = commands("update");
        QCOMPARE(updates.size(), 1);
        QCOMPARE(updates.first().value("body").toString(), QString("Pending text"));
        QCOMPARE(updates.first().value("collection").toString(), QString("HCI tests"));
    }
    void oldAcknowledgementDoesNotOverwriteNewerQueuedText() {
        controller.reset();
        qputenv("FIELDNOTES_TEST_ACK_DELAY", "0.25");
        controller = std::make_unique<Controller>(); controller->start();
        QTRY_VERIFY_WITH_TIMEOUT(controller->connected(), 5000);
        controller->updateBody("Older sent text");
        QTRY_COMPARE_WITH_TIMEOUT(commands("update").size(), 1, 2000);
        controller->updateBody("Newer queued text");
        QTest::qWait(350);
        QCOMPARE(controller->body(), QString("Newer queued text"));
        QVERIFY(controller->saving());
        QTRY_VERIFY_WITH_TIMEOUT(!controller->saving(), 2000);
        QCOMPARE(controller->body(), QString("Newer queued text"));
        QCOMPARE(commands("update").size(), 2);
    }
    void trashingAnotherNotePreservesSelectionAndUndoTargetsThatNote() {
        QSignalSpy deleted(controller.get(), &Controller::deleted);
        controller->trashNote("second");
        QTRY_COMPARE_WITH_TIMEOUT(deleted.count(), 1, 2000);
        QCOMPARE(controller->selectedId(), QString("first"));
        QCOMPARE(controller->body(), QString("Original first"));
        QCOMPARE(commands("delete").first().value("id").toString(), QString("second"));
        controller->undoDelete();
        QTRY_COMPARE_WITH_TIMEOUT(commands("restore").size(), 1, 2000);
        QCOMPARE(commands("restore").first().value("id").toString(), QString("second"));
        QCOMPARE(controller->selectedId(), QString("first"));
        QCOMPARE(commands("select").size(), 0);
    }
    void trashingTheSelectedNoteOpensTheAdjacentRemainingNote() {
        controller->trashNote("first");
        QTRY_COMPARE_WITH_TIMEOUT(controller->selectedId(), QString("second"), 2000);
        QCOMPARE(controller->body(), QString("Original second"));
    }
};
QTEST_GUILESS_MAIN(SaveDebounceTest)
#include "test_save_debounce.moc"
