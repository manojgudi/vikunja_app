#ifndef SECURESTORE_H
#define SECURESTORE_H

#include <QByteArray>
#include <QHash>
#include <QString>

namespace Sailfish { namespace Secrets { class SecretManager; } }

// Keeps credentials in an app-owned Sailfish Secrets collection
// (encrypted storage plugin, unlocked with the device lock, owner-only
// access). Every write is read back from the daemon; if Secrets refuses it,
// the value goes to a 0600 file in the app's private data folder instead,
// which sailjail hides from other apps. With HARBOUR_VIKUNJA_MEMORY_STORE
// set nothing is ever written anywhere (tests).
class SecureStore
{
public:
    enum Backend { Memory, Secrets, PrivateFile };

    SecureStore();
    ~SecureStore();

    // Connects to the daemon and creates the collection if needed.
    bool init();
    bool persistent() const { return m_backend != Memory; }
    Backend backend() const { return m_backend; }
    QString lastError() const { return m_lastError; }

    bool write(const QString &name, const QByteArray &data);
    QByteArray read(const QString &name, bool *found = nullptr);
    void remove(const QString &name);

    // Where the fallback file lives.
    static QString privateDir();

private:
    bool ensureCollection();
    void removeOldToken();
    bool secretsWrite(const QString &name, const QByteArray &data);
    QByteArray secretsRead(const QString &name, bool *found);
    void secretsRemove(const QString &name);
    bool fileWrite(const QString &name, const QByteArray &data);
    QByteArray fileRead(const QString &name, bool *found);
    void fileRemove(const QString &name);
    QString filePath(const QString &name) const;

    Sailfish::Secrets::SecretManager *m_manager = nullptr;
    Backend m_backend = Memory;
    bool m_secretsReady = false;
    QString m_lastError;
    QHash<QString, QByteArray> m_memory;
};

#endif // SECURESTORE_H
