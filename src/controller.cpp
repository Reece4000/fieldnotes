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
    connect(m_process, &QProcess::readyReadStandardOutput, this, &Controller::receive);
    connect(m_process, &QProcess::readyReadStandardError, this, [this] {
        m_log.write(m_process->readAllStandardError());
        m_log.flush();
    });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (!m_closing) setError("The recording service could not start. Check the Python runtime in Resources/runtime.json.");
    });
    connect(m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this](int, QProcess::ExitStatus) {
        m_connected = false;
        m_active.clear();
        emit stateChanged();
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
        m_capture = event.value("capture").toObject().toVariantMap();
        m_paused = event.value("paused").toBool();
        m_engine = event.value("engine").toString();
        m_engineError = event.value("engineError").toString();
        if (m_deletionPending == documentId && document.value("deleted").toBool()) {
            m_deletionPending.clear();
            emit deleted();
            if (!m_notes.isEmpty()) selectNote(m_notes.first().toMap().value("id").toString());
            else {
                m_selected.clear(); m_document.clear(); emit documentChanged();
                send({{"action", "select"}, {"id", ""}});
            }
        }
        emit notesChanged();
        emit stateChanged();
        if (first) refreshDevices();
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
    } else if (type == "devices") {
        m_devices = event.value("devices").toArray().toVariantList();
        emit devicesChanged();
    } else if (type == "copy") {
        QString text = event.value("text").toString();
        text.remove(QRegularExpression("\\[\\d{2,}:\\d{2}:\\d{2}\\] ?"));
        QGuiApplication::clipboard()->setText(text);
        emit noteCopied(event.value("id").toString());
    } else if (type == "error") setError(event.value("message").toString());
}
void Controller::refreshDocument() { send({{"action", "select"}, {"id", m_selected}}); }
void Controller::selectNote(const QString &id) {
    if (id == m_selected) return;
    m_selectionPending = id;
    send({{"action", "select"}, {"id", id}});
}
void Controller::newNote(const QString &collection, const QString &workspace) {
    send({{"action", "new"}, {"collection", collection}, {"workspace", workspace}});
}
void Controller::query(const QString &workspace, const QString &collection, const QString &search, bool trash) {
    QJsonObject command{{"action", "query"}, {"workspace", workspace}, {"search", search}, {"trash", trash}};
    if (collection != "*") command.insert("collection", collection);
    send(command);
}
void Controller::loadMore() { send({{"action", "more"}}); }
void Controller::createWorkspace(const QString &name) { send({{"action", "workspace"}, {"name", name}}); }
void Controller::createCategory(const QString &workspace, const QString &name) { send({{"action", "category"}, {"workspace", workspace}, {"name", name}}); }
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
    m_seconds = m_level = 0;
    m_db = -90; m_waveform.clear();
    emit meterChanged();
    QJsonObject command{{"action", "record"}, {"collection", collection}, {"workspace", workspace}, {"voiceDb", voiceDb}};
    if (device >= 0) command.insert("device", device);
    send(command);
}
void Controller::stop() { send({{"action", "stop"}}); }
void Controller::pause() { send({{"action", "pause"}}); }
void Controller::updateField(const QString &key, const QString &value) {
    if (m_selected.isEmpty() || m_document.value(key).toString() == value) return;
    // Local edits are visible immediately; backend events acknowledge their save.
    m_document.insert(key, value);
    m_edits[m_selected].insert(key, value);
    emit stateChanged();
    send({{"action", "update"}, {"id", m_selected}, {key, value}});
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
void Controller::deleteNote() {
    if (m_selected.isEmpty()) return;
    m_deleted = m_selected;
    m_deletionPending = m_selected;
    send({{"action", "delete"}, {"id", m_selected}});
}
void Controller::undoDelete() { if (!m_deleted.isEmpty()) send({{"action", "restore"}, {"id", m_deleted}}); }
void Controller::restoreNote() { if (trashed()) send({{"action", "restore"}, {"id", m_selected}}); }
void Controller::retry() { send({{"action", "retry"}, {"id", m_selected}}); }
void Controller::refreshDevices() { send({{"action", "devices"}}); }
void Controller::dismissError() { m_error.clear(); emit errorChanged(); }
void Controller::setError(const QString &value) { m_error = value; emit errorChanged(); }
QString Controller::clock(double value) const {
    qint64 seconds = qMax<qint64>(0, qint64(value));
    return QString("%1:%2:%3").arg(seconds / 3600, 2, 10, QChar('0')).arg(seconds / 60 % 60, 2, 10, QChar('0')).arg(seconds % 60, 2, 10, QChar('0'));
}
void Controller::shutdown() {
    if (m_closing) return;
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
