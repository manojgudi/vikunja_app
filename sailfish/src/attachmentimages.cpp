#include "attachmentimages.h"

#include <QImage>
#include <QMutexLocker>

namespace {
const qint64 MaxCacheBytes = 40 * 1024 * 1024;
AttachmentImages *s_instance = nullptr;
}

AttachmentImages::AttachmentImages()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
    s_instance = this;
}

AttachmentImages *AttachmentImages::instance()
{
    return s_instance;
}

void AttachmentImages::insert(const QString &key, const QByteArray &data)
{
    QMutexLocker locker(&m_lock);
    if (m_data.contains(key)) {
        m_bytes -= m_data.value(key).size();
        m_order.removeAll(key);
    }
    m_data.insert(key, data);
    m_order.append(key);
    m_bytes += data.size();
    while (m_bytes > MaxCacheBytes && m_order.size() > 1) {
        const QString old = m_order.takeFirst();
        m_bytes -= m_data.take(old).size();
    }
}

void AttachmentImages::clear()
{
    QMutexLocker locker(&m_lock);
    for (auto it = m_data.begin(); it != m_data.end(); ++it)
        it->fill('\0');
    m_data.clear();
    m_order.clear();
    m_bytes = 0;
}

bool AttachmentImages::contains(const QString &key) const
{
    QMutexLocker locker(&m_lock);
    return m_data.contains(key);
}

QImage AttachmentImages::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    QByteArray data;
    {
        QMutexLocker locker(&m_lock);
        data = m_data.value(id);
    }
    QImage image = QImage::fromData(data);
    if (size)
        *size = image.size();
    if (!image.isNull() && requestedSize.isValid() && requestedSize.width() > 0 && requestedSize.height() > 0)
        image = image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return image;
}
