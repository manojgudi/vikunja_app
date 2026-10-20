#ifndef SECURESTORE_H
#define SECURESTORE_H

#include <QByteArray>
#include <QHash>
#include <QString>

namespace Sailfish { namespace Secrets { class SecretManager; } }

// Keeps credentials in an app-owned Sailfish Secrets collection
// (encrypted storage plugin, unlocked with the device lock, owner-only
// access). When the Secrets daemon is unavailable the store falls back to
// memory only: nothing is ever written to disk in plain form.
class SecureStore
{
public:
    SecureStore();
    ~SecureStore();

    // Connects to the daemon and creates the collection if needed.
    bool init();
    bool persistent() const { return m_persistent; }
    QString lastError() const { return m_lastError; }

    bool write(const QString &name, const QByteArray &data);
    QByteArray read(const QString &name, bool *found = nullptr);
    void remove(const QString &name);

private:
    bool ensureCollection();

    Sailfish::Secrets::SecretManager *m_manager = nullptr;
    bool m_persistent = false;
    QString m_lastError;
    QHash<QString, QByteArray> m_memory;
};

#endif // SECURESTORE_H
