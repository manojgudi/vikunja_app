#ifndef ATTACHMENTIMAGES_H
#define ATTACHMENTIMAGES_H

#include <QByteArray>
#include <QHash>
#include <QMutex>
#include <QQuickImageProvider>
#include <QStringList>

// Serves attachment previews to QML as image://attachment/<key> straight from
// memory, so viewing an image never writes it to the phone's storage.
class AttachmentImages : public QQuickImageProvider
{
public:
    AttachmentImages();

    static AttachmentImages *instance();
    void insert(const QString &key, const QByteArray &data);
    void clear();
    bool contains(const QString &key) const;

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    mutable QMutex m_lock;
    QHash<QString, QByteArray> m_data;
    QStringList m_order;
    qint64 m_bytes = 0;
};

#endif // ATTACHMENTIMAGES_H
