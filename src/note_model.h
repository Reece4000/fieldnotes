#pragma once
#include <QAbstractListModel>
#include <QVariantList>

// Update rows by identity so inference acknowledgements don't reset scrolling.
class NoteModel : public QAbstractListModel {
    Q_OBJECT
public:
    using QAbstractListModel::QAbstractListModel;
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : m_items.size(); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override { return {{Qt::UserRole + 1, "modelData"}}; }
    void setNotes(const QVariantList &items);
private:
    QVariantList m_items;
};
