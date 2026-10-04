#pragma once
#include <QObject>
#include <QProcess>
#include <QJsonObject>
#include <QVariantList>
#include <QFile>
#include <QHash>
#include <QTimer>
#include "note_model.h"

class Controller : public QObject {
    Q_OBJECT
    Q_PROPERTY(QAbstractItemModel* notes READ notes CONSTANT)
    Q_PROPERTY(QVariantList workspaces READ workspaces NOTIFY notesChanged)
    Q_PROPERTY(QVariantList categories READ categories NOTIFY notesChanged)
    Q_PROPERTY(int total READ total NOTIFY notesChanged)
    Q_PROPERTY(double updated READ updated NOTIFY documentChanged)
    Q_PROPERTY(QVariantMap capture READ capture NOTIFY stateChanged)
    Q_PROPERTY(QString workspace READ workspace NOTIFY documentChanged)
    Q_PROPERTY(QVariantList waveform READ waveform NOTIFY meterChanged)
    Q_PROPERTY(double decibels READ decibels NOTIFY meterChanged)
    Q_PROPERTY(bool systemReduceMotion READ systemReduceMotion NOTIFY stateChanged)
    Q_PROPERTY(QUrl settingsFile READ settingsFile CONSTANT)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(QString selectedId READ selectedId NOTIFY documentChanged)
    Q_PROPERTY(QString title READ title NOTIFY documentChanged)
    Q_PROPERTY(QString body READ body NOTIFY documentChanged)
    Q_PROPERTY(QString collection READ collection NOTIFY documentChanged)
    Q_PROPERTY(QString noteStatus READ noteStatus NOTIFY documentChanged)
    Q_PROPERTY(bool editable READ editable NOTIFY documentChanged)
    Q_PROPERTY(bool trashed READ trashed NOTIFY documentChanged)
    Q_PROPERTY(int pending READ pending NOTIFY documentChanged)
    Q_PROPERTY(int failed READ failed NOTIFY documentChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY stateChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY stateChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY stateChanged)
    Q_PROPERTY(bool saving READ saving NOTIFY stateChanged)
    Q_PROPERTY(QString engineStatus READ engineStatus NOTIFY stateChanged)
    Q_PROPERTY(QString engineError READ engineError NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(double seconds READ seconds NOTIFY meterChanged)
    Q_PROPERTY(double level READ level NOTIFY meterChanged)
public:
    explicit Controller(QObject *parent = nullptr);
    ~Controller() override;
    void start();
    QAbstractItemModel *notes() { return &m_noteModel; }
    QVariantList workspaces() const { return m_workspaces; }
    QVariantList categories() const { return m_categories; }
    int total() const { return m_total; }
    double updated() const { return m_document.value("updated").toDouble(); }
    QVariantMap capture() const { return m_capture; }
    QString workspace() const { return m_document.value("workspace").toString(); }
    QVariantList waveform() const { return m_waveform; }
    double decibels() const { return m_db; }
    bool systemReduceMotion() const;
    QUrl settingsFile() const;
    QVariantList devices() const { return m_devices; }
    QString selectedId() const { return m_selected; }
    QString title() const { return m_document.value("title").toString(); }
    QString body() const { return m_document.value("body").toString(); }
    QString collection() const { return m_document.value("collection").toString(); }
    QString noteStatus() const { return m_document.value("status").toString(); }
    bool editable() const { return m_document.value("editable").toBool() && !trashed(); }
    bool trashed() const { return m_document.value("deleted").toBool(); }
    int pending() const { return m_document.value("pending").toInt(); }
    int failed() const { return m_document.value("errors").toInt(); }
    bool recording() const { return !m_active.isEmpty(); }
    bool paused() const { return m_paused; }
    bool connected() const { return m_connected; }
    bool saving() const { return !m_edits.isEmpty(); }
    QString engineStatus() const { return m_engine; }
    QString engineError() const { return m_engineError; }
    QString error() const { return m_error; }
    double seconds() const { return m_seconds; }
    double level() const { return m_level; }
    Q_INVOKABLE void selectNote(const QString &id);
    Q_INVOKABLE void newNote(const QString &collection = "", const QString &workspace = "inbox");
    Q_INVOKABLE void record(int device = -1, const QString &collection = "", const QString &workspace = "inbox", double voiceDb = -44);
    Q_INVOKABLE void query(const QString &workspace, const QString &collection, const QString &search, bool trash = false);
    Q_INVOKABLE void loadMore();
    Q_INVOKABLE void createWorkspace(const QString &name);
    Q_INVOKABLE void createCategory(const QString &workspace, const QString &name);
    Q_INVOKABLE void updateWorkspace(const QString &value);
    Q_INVOKABLE void stop();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void updateTitle(const QString &value);
    Q_INVOKABLE void updateCollection(const QString &value);
    Q_INVOKABLE void updateBody(const QString &value);
    Q_INVOKABLE void copy(bool timestamps = false);
    Q_INVOKABLE void copyNote(const QString &id);
    Q_INVOKABLE void exportNote(const QUrl &url);
    Q_INVOKABLE void deleteNote();
    Q_INVOKABLE void undoDelete();
    Q_INVOKABLE void restoreNote();
    Q_INVOKABLE void retry();
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void dismissError();
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE QString clock(double value) const;
signals:
    void notesChanged();
    void devicesChanged();
    void documentChanged();
    void stateChanged();
    void meterChanged();
    void errorChanged();
    void copied();
    void noteCopied(const QString &id);
    void exported();
    void deleted();
    void workspaceCreated(const QString &id);
    void categoryCreated(const QString &name);
private:
    void send(QJsonObject value);
    void receive();
    void handle(const QJsonObject &event);
    void setError(const QString &value);
    void updateField(const QString &key, const QString &value);
    void flushEdits();
    void doRecord(int device, const QString &collection, const QString &workspace, double voiceDb);
    void refreshDocument();
    QProcess *m_process;
    NoteModel m_noteModel;
    QFile m_log;
    QByteArray m_buffer;
    QVariantList m_notes, m_devices, m_workspaces, m_categories, m_waveform;
    int m_total = 0;
    QVariantMap m_document, m_capture;
    QHash<QString, QVariantMap> m_edits;
    QHash<QString, QVariantMap> m_pendingUpdates;
    QTimer m_editTimer;
    QString m_selected, m_active, m_engine = "loading", m_engineError, m_error, m_deleted, m_deletionPending, m_selectionPending;
    bool m_paused = false, m_connected = false, m_closing = false;
    double m_seconds = 0, m_level = 0, m_db = -90;
};
