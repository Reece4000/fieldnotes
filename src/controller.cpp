#include "controller.h"
#include <QGuiApplication>
#include <QClipboard>
#include <QJsonDocument>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDir>
#include <QPermissions>
#include <QRegularExpression>
#include <QSaveFile>
#include <QProcessEnvironment>

bool fieldnotesSystemReduceMotion();
bool Controller::systemReduceMotion() const { return fieldnotesSystemReduceMotion(); }
QUrl Controller::settingsFile() const {
    QString data = qEnvironmentVariable("FIELDNOTES_DATA_DIR");
    if (data.isEmpty()) data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/Fieldnotes";
    return QUrl::fromLocalFile(data + "/preferences.ini");
}

Controller::Controller(QObject *parent) : QObject(parent), m_process(new QProcess(this)) {
    m_editTimer.setSingleShot(true);
    m_editTimer.setInterval(750);
    connect(&m_editTimer, &QTimer::timeout, this, &Controller::flushEdits);
    connect(m_process, &QProcess::readyReadStandardOutput, this, &Controller::receive);
    connect(m_process, &QProcess::readyReadStandardError, this, [this] {
        m_log.write(m_process->readAllStandardError());
        m_log.flush();
    });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (!m_closing && !m_restarting) setError("The recording service could not start. Check the Python runtime in Resources/runtime.json.");
    });
    connect(m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this](int, QProcess::ExitStatus) {
        m_connected = false;
        m_moving = false;
        m_active.clear();
        m_stopping = false;
        emit stateChanged();
        if (m_restarting && !m_closing) {
            m_restarting = false;
            m_buffer.clear();
            start();
            return;
        }
        if (!m_closing) setError("The recording service stopped. Reopen Fieldnotes to recover saved audio and notes.");
    });
}
Controller::~Controller() { shutdown(); }

void Controller::start() {
    QString resources = QCoreApplication::applicationDirPath() + "/../Resources";
    QFile config(resources + "/runtime.json");
    if (!config.open(QIODevice::ReadOnly)) {
        setError("The app runtime configuration is missing. Rebuild Fieldnotes using scripts/build.sh.");
        return;
    }
    QString python = QJsonDocument::fromJson(config.readAll()).object().value("python").toString();
    if (qEnvironmentVariableIsSet("FIELDNOTES_PYTHON")) python = qEnvironmentVariable("FIELDNOTES_PYTHON");
    QString data = qEnvironmentVariable("FIELDNOTES_DATA_DIR");
    if (data.isEmpty()) data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/Fieldnotes";
    QDir().mkpath(data);
    QString log = data + "/engine.log";
    if (QFileInfo(log).size() > 4 * 1024 * 1024) {
        QFile::remove(log + ".old");
        QFile::rename(log, log + ".old");
    }
    m_log.close();
    m_log.setFileName(log);
    if (!m_log.open(QIODevice::WriteOnly | QIODevice::Append)) {
        setError("The notes folder is not writable. Free disk space or check folder permissions, then reopen Fieldnotes.");
        return;
    }
    m_log.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert("PYTHONUNBUFFERED", "1");
    env.insert("PYTHONDONTWRITEBYTECODE", "1");
    m_process->setProcessEnvironment(env);
    m_process->start(python, {"-u", resources + "/worker/backend.py", "--data", data + "/notes.sqlite3"});
}
void Controller::send(QJsonObject value) {
    if (m_process->state() != QProcess::Running) {
        setError("The recording service is unavailable. Reopen Fieldnotes; saved notes stay on this Mac.");
        return;
    }
    m_process->write(QJsonDocument(value).toJson(QJsonDocument::Compact) + '\n');
}
void Controller::receive() {
    m_buffer += m_process->readAllStandardOutput();
    int newline;
    while ((newline = m_buffer.indexOf('\n')) >= 0) {
        const auto line = m_buffer.left(newline);
        m_buffer.remove(0, newline + 1);
        const auto doc = QJsonDocument::fromJson(line);
        if (doc.isObject()) handle(doc.object());
    }
}
void Controller::handle(const QJsonObject &event) {
    const auto type = event.value("event").toString();
    if (type == "state") {
        const bool first = !m_connected;
        m_connected = true;
        m_notes = event.value("notes").toArray().toVariantList();
        QStringList visibleIds;
        for (const auto &note : m_notes) visibleIds.append(note.toMap().value("id").toString());
        const auto previousSelection = m_selectedNoteIds;
        m_selectedNoteIds.removeIf([&visibleIds](const QString &id) { return !visibleIds.contains(id); });
        if (previousSelection != m_selectedNoteIds) emit noteSelectionChanged();
        m_noteModel.setNotes(m_notes);
        m_workspaces = event.value("workspaces").toArray().toVariantList();
        m_categories = event.value("categories").toArray().toVariantList();
        m_total = event.value("total").toInt();
        auto document = event.value("document").toObject().toVariantMap();
        const auto documentId = document.value("id").toString();
        if (m_selectionPending == documentId && !documentId.isEmpty()) {
            m_selected = documentId;
            m_selectionPending.clear();
        }
        if (m_selected.isEmpty()) m_selected = documentId;
        // Acknowledgements never overwrite later local keystrokes.
        if (m_edits.contains(documentId)) {
            auto &edits = m_edits[documentId];
            for (auto it = edits.begin(); it != edits.end();) {
                if (document.value(it.key()) == it.value()) it = edits.erase(it);
                else { document.insert(it.key(), it.value()); ++it; }
            }
            if (edits.isEmpty()) m_edits.remove(documentId);
        }
        if (documentId == m_selected && document != m_document) {
            m_document = document;
            emit documentChanged();
        }
        m_active = event.value("active").toString();
        if (m_active.isEmpty()) m_stopping = false;
        else if (event.value("stopping").toBool()) m_stopping = true;
        m_capture = event.value("capture").toObject().toVariantMap();
        m_paused = event.value("paused").toBool();
        m_engine = event.value("engine").toString();
        m_engineError = event.value("engineError").toString();
        if (m_deletionPending == documentId && document.value("deleted").toBool()) {
            m_deletionPending.clear();
            emit deleted(m_deletedIds.size());
            if (!m_notes.isEmpty()) selectNote(m_notes[qMin(m_deletionIndex, int(m_notes.size()) - 1)].toMap().value("id").toString());
            else {
                m_selected.clear(); m_document.clear(); emit documentChanged();
                send({{"action", "select"}, {"id", ""}});
            }
        }
        emit notesChanged();
        emit stateChanged();
        if (first) {
            if (!m_selected.isEmpty() && documentId != m_selected) selectNote(m_selected);
            flushEdits();
            refreshDevices();
        }
    } else if (type == "restart") {
        setError(event.value("message").toString());
        m_pendingUpdates = m_edits;
        m_restarting = true;
        m_process->kill();
    } else if (type == "saved") {
        const auto id = event.value("id").toString();
        if (m_edits.contains(id)) {
            auto &edits = m_edits[id];
            const auto fields = event.value("fields").toObject().toVariantMap();
            for (auto it = fields.begin(); it != fields.end(); ++it) {
                if (edits.value(it.key()) == it.value()) edits.remove(it.key());
            }
            if (edits.isEmpty()) m_edits.remove(id);
            emit stateChanged();
        }
    } else if (type == "meter") {
        m_seconds = event.value("seconds").toDouble();
        m_level = event.value("level").toDouble();
        m_db = event.value("db").toDouble(-90);
        m_waveform = event.value("waveform").toArray().toVariantList();
        emit meterChanged();
    } else if (type == "select") {
        m_selectionPending = event.value("id").toString();
        if (m_selectionPending.isEmpty()) { m_selected.clear(); m_document.clear(); emit documentChanged(); }
        // The following state contains the newly created note.
    } else if (type == "workspace") {
        emit workspaceCreated(event.value("id").toString());
    } else if (type == "category") {
        emit categoryCreated(event.value("name").toString());
    } else if (type == "category_changed") {
        emit categoryChanged(event.value("message").toString());
    } else if (type == "moved") {
        m_moving = false;
        clearNoteSelection();
        emit stateChanged();
        emit notesMoved(event.value("count").toInt(), event.value("collection").toString());
    } else if (type == "deleted") {
        m_deletedIds.clear();
        for (const auto &id : event.value("ids").toArray()) m_deletedIds.append(id.toString());
        if (m_deletedIds.isEmpty()) m_deletedIds.append(event.value("id").toString());
        // The selected-note state below also chooses a replacement document.
        if (!m_deletedIds.contains(m_selected)) emit deleted(m_deletedIds.size());
    } else if (type == "devices") {
        m_devices = event.value("devices").toArray().toVariantList();
        emit devicesChanged();
    } else if (type == "copy") {
        QString text = event.value("text").toString();
        text.remove(QRegularExpression("\\[\\d{2,}:\\d{2}:\\d{2}\\] ?"));
        QGuiApplication::clipboard()->setText(text);
        emit noteCopied(event.value("id").toString());
    } else if (type == "error") {
        m_moving = false;
        emit stateChanged();
        setError(event.value("message").toString());
    }
}
void Controller::clearNoteSelection() {
    m_selectionAnchor.clear();
    if (m_selectedNoteIds.isEmpty()) return;
    m_selectedNoteIds.clear();
    emit noteSelectionChanged();
}
void Controller::selectNoteRow(const QString &id, bool toggle, bool extend) {
    QStringList ids;
    for (const auto &note : m_notes) ids.append(note.toMap().value("id").toString());
    const int row = ids.indexOf(id), anchor = ids.indexOf(m_selectionAnchor);
    if (row < 0) return;
    if (extend && anchor >= 0) {
        if (!toggle) m_selectedNoteIds.clear();
        for (int i = qMin(row, anchor); i <= qMax(row, anchor); ++i)
            if (!m_selectedNoteIds.contains(ids[i])) m_selectedNoteIds.append(ids[i]);
    } else if (toggle) {
        if (m_selectedNoteIds.contains(id)) m_selectedNoteIds.removeAll(id);
        else m_selectedNoteIds.append(id);
        m_selectionAnchor = id;
    } else {
        m_selectedNoteIds = {id};
        m_selectionAnchor = id;
    }
    emit noteSelectionChanged();
    if (!toggle && !extend) selectNote(id);
}
void Controller::selectAllNotes() {
    m_selectedNoteIds.clear();
    for (const auto &note : m_notes) m_selectedNoteIds.append(note.toMap().value("id").toString());
    m_selectionAnchor = m_selectedNoteIds.value(0);
    emit noteSelectionChanged();
}
void Controller::selectNotes(const QStringList &ids) {
    m_selectedNoteIds.clear();
    for (const auto &note : m_notes) {
        const auto id = note.toMap().value("id").toString();
        if (ids.contains(id)) m_selectedNoteIds.append(id);
    }
    m_selectionAnchor = m_selectedNoteIds.value(0);
    emit noteSelectionChanged();
}
void Controller::moveNotes(const QStringList &ids, const QString &workspace, const QString &collection) {
    if (!m_connected || m_moving || ids.isEmpty()) return;
    flushEdits();
    m_moving = true;
    emit stateChanged();
    send({{"action", "move"}, {"ids", QJsonArray::fromStringList(ids)}, {"workspace", workspace}, {"collection", collection}});
}
void Controller::refreshDocument() { send({{"action", "select"}, {"id", m_selected}}); }
void Controller::selectNote(const QString &id) {
    if (id == m_selected) return;
    flushEdits();
    m_selectionPending = id;
    send({{"action", "select"}, {"id", id}});
}
void Controller::newNote(const QString &collection, const QString &workspace) {
    flushEdits();
    send({{"action", "new"}, {"collection", collection}, {"workspace", workspace}});
}
void Controller::query(const QString &workspace, const QString &collection, const QString &search, bool trash, bool all, const QString &select) {
    clearNoteSelection();
    flushEdits();
    QJsonObject command{{"action", "query"}, {"workspace", workspace}, {"search", search}, {"trash", trash}, {"all", all}};
    if (collection != "*") command.insert("collection", collection);
    if (!select.isEmpty()) command.insert("select", select);
    send(command);
}
void Controller::loadMore() { send({{"action", "more"}}); }
void Controller::createWorkspace(const QString &name) { send({{"action", "workspace"}, {"name", name}}); }
void Controller::createCategory(const QString &workspace, const QString &name) { send({{"action", "category"}, {"workspace", workspace}, {"name", name}}); }
void Controller::renameCategory(const QString &workspace, const QString &name, const QString &replacement) { flushEdits(); send({{"action", "rename_category"}, {"workspace", workspace}, {"name", name}, {"replacement", replacement}}); }
void Controller::removeCategory(const QString &workspace, const QString &name) { flushEdits(); send({{"action", "remove_category"}, {"workspace", workspace}, {"name", name}}); }
void Controller::reorderCategories(const QString &workspace, const QStringList &names) { send({{"action", "reorder_categories"}, {"workspace", workspace}, {"names", QJsonArray::fromStringList(names)}}); }
void Controller::updateWorkspace(const QString &value) { updateField("workspace", value); }
void Controller::record(int device, const QString &collection, const QString &workspace, double voiceDb) {
    if (recording()) return;
    const QMicrophonePermission permission;
    auto status = qApp->checkPermission(permission);
    if (status == Qt::PermissionStatus::Undetermined) {
        qApp->requestPermission(permission, this, [this, device, collection, workspace, voiceDb](const QPermission &result) {
            if (result.status() == Qt::PermissionStatus::Granted) doRecord(device, collection, workspace, voiceDb);
            else setError("Microphone access is needed to record. Enable Fieldnotes in System Settings → Privacy & Security → Microphone, then record again.");
        });
    } else if (status == Qt::PermissionStatus::Granted) doRecord(device, collection, workspace, voiceDb);
    else setError("Microphone access is disabled. Enable Fieldnotes in System Settings → Privacy & Security → Microphone, then record again.");
}
void Controller::doRecord(int device, const QString &collection, const QString &workspace, double voiceDb) {
    flushEdits();
    m_seconds = m_level = 0;
    m_db = -90; m_waveform.clear();
    emit meterChanged();
    QJsonObject command{{"action", "record"}, {"collection", collection}, {"workspace", workspace}, {"voiceDb", voiceDb}};
    if (device >= 0) command.insert("device", device);
    send(command);
}
void Controller::stop() {
    if (!recording() || m_stopping) return;
    m_stopping = true;
    emit stateChanged();
    send({{"action", "stop"}});
}
void Controller::pause() { send({{"action", "pause"}}); }
void Controller::updateField(const QString &key, const QString &value) {
    if (m_selected.isEmpty() || m_document.value(key).toString() == value) return;
    // Local edits are visible immediately; backend events acknowledge their save.
    m_document.insert(key, value);
    m_edits[m_selected].insert(key, value);
    emit stateChanged();
    m_pendingUpdates[m_selected].insert(key, value);
    if (key == "body" || key == "title") m_editTimer.start();
    else flushEdits();
}
void Controller::flushEdits() {
    m_editTimer.stop();
    // Keep acknowledgements in m_edits until the backend commits them.
    // Capture each note's ID so switching notes cannot redirect a queued edit.
    const auto updates = m_pendingUpdates;
    m_pendingUpdates.clear();
    for (auto it = updates.cbegin(); it != updates.cend(); ++it) {
        auto command = QJsonObject::fromVariantMap(it.value());
        command.insert("action", "update");
        command.insert("id", it.key());
        send(command);
    }
}
void Controller::updateTitle(const QString &value) { updateField("title", value); }
void Controller::updateCollection(const QString &value) { updateField("collection", value); }
void Controller::updateBody(const QString &value) { if (editable()) updateField("body", value); }
void Controller::copy(bool timestamps) {
    QString text = body();
    if (!timestamps) text.remove(QRegularExpression("\\[\\d{2,}:\\d{2}:\\d{2}\\] ?"));
    QGuiApplication::clipboard()->setText(text);
    emit copied();
}
void Controller::copyNote(const QString &id) {
    if (id.isEmpty()) return;
    if (id == m_selected) {
        // Include edits which have not yet been acknowledged by the backend.
        QString text = body();
        text.remove(QRegularExpression("\\[\\d{2,}:\\d{2}:\\d{2}\\] ?"));
        QGuiApplication::clipboard()->setText(text);
        emit noteCopied(id);
    } else send({{"action", "copy"}, {"id", id}});
}
void Controller::exportNote(const QUrl &url) {
    QSaveFile file(url.toLocalFile());
    const auto text = ("# " + title() + "\n\n" + body() + "\n").toUtf8();
    if (!file.open(QIODevice::WriteOnly) || file.write(text) != text.size() || !file.commit()) {
        setError("The note could not be exported. Choose a writable folder and try again.");
        return;
    }
    emit exported();
}
void Controller::deleteNote() { trashNote(m_selected); }
void Controller::trashNote(const QString &id) { trashNotes({id}); }
void Controller::trashNotes(const QStringList &ids) {
    if (ids.isEmpty() || ids.contains(QString())) return;
    flushEdits();
    if (ids.contains(m_selected)) {
        m_deletionPending = m_selected;
        m_deletionIndex = 0;
        for (int i = 0; i < m_notes.size(); ++i) {
            if (m_notes[i].toMap().value("id").toString() == m_selected) { m_deletionIndex = i; break; }
        }
    }
    send({{"action", "delete"}, {"id", ids.first()}, {"ids", QJsonArray::fromStringList(ids)}});
}
void Controller::discardIfEmpty(const QString &id) {
    if (id.isEmpty()) return;
    flushEdits();
    send({{"action", "discard"}, {"id", id}});
}
void Controller::undoDelete() {
    if (!m_deletedIds.isEmpty()) send({{"action", "restore"}, {"id", m_deletedIds.first()}, {"ids", QJsonArray::fromStringList(m_deletedIds)}});
}
void Controller::restoreNote(const QString &id) {
    if (!id.isEmpty() || trashed()) send({{"action", "restore"}, {"id", id.isEmpty() ? m_selected : id}});
}
void Controller::retry(const QString &id) { send({{"action", "retry"}, {"id", id.isEmpty() ? m_selected : id}}); }
void Controller::refreshDevices() { send({{"action", "devices"}}); }
void Controller::dismissError() { m_error.clear(); emit errorChanged(); }
void Controller::setError(const QString &value) { m_error = value; emit errorChanged(); }
QString Controller::clock(double value) const {
    qint64 seconds = qMax<qint64>(0, qint64(value));
    return QString("%1:%2:%3").arg(seconds / 3600, 2, 10, QChar('0')).arg(seconds / 60 % 60, 2, 10, QChar('0')).arg(seconds % 60, 2, 10, QChar('0'));
}
void Controller::shutdown() {
    if (m_closing) return;
    flushEdits();
    m_closing = true;
    if (m_process->state() == QProcess::Running) {
        send({{"action", "shutdown"}});
        m_process->closeWriteChannel();
        if (!m_process->waitForFinished(15000)) {
            // Never kill an audio writer mid-save. It exits after EOF/save.
            m_process->disconnect(this);
            m_process->setParent(nullptr);
        }
    }
}
