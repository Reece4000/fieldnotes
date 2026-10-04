#include "note_model.h"

QVariant NoteModel::data(const QModelIndex &index, int role) const {
    if (role != Qt::UserRole + 1 || !index.isValid() || index.row() >= m_items.size()) return {};
    return m_items[index.row()];
}

void NoteModel::setNotes(const QVariantList &items) {
    for (int row = 0; row < items.size(); ++row) {
        const auto id = items[row].toMap().value("id");
        if (row >= m_items.size() || m_items[row].toMap().value("id") != id) {
            int found = -1;
            for (int candidate = row + 1; candidate < m_items.size(); ++candidate) {
                if (m_items[candidate].toMap().value("id") == id) { found = candidate; break; }
            }
            if (found >= 0) {
                beginMoveRows({}, found, found, {}, row);
                m_items.move(found, row);
                endMoveRows();
            } else {
                beginInsertRows({}, row, row);
                m_items.insert(row, items[row]);
                endInsertRows();
            }
        }
        if (m_items[row] != items[row]) {
            m_items[row] = items[row];
            emit dataChanged(index(row), index(row), {Qt::UserRole + 1});
        }
    }
    if (m_items.size() > items.size()) {
        beginRemoveRows({}, items.size(), m_items.size() - 1);
        m_items.erase(m_items.begin() + items.size(), m_items.end());
        endRemoveRows();
    }
}
