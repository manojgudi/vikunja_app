#ifndef SECURESTORE_H
#define SECURESTORE_H

#include <QByteArray>
#include <QHash>
#include <QString>

namespace Sailfish { namespace Secrets { class SecretManager; } }

// Keeps credentials in an app-owned Sailfish Secrets collection
// (encrypted storage plugin, unlocked with the device lock, owner-only
// access). Every write is read back from the daemon. If Secrets refuses it,
// the value can go to a 0600 file in the app's private data folder (hidden
// from other apps by sailjail, not encrypted), but only once the user has
// allowed that; until then it stays in memory. With
// HARBOUR_VIKUNJA_MEMORY_STORE set nothing is ever written anywhere (tests).
class SecureStore
{
public:
    enum Backend { Memory, Secrets, PrivateFile };

    SecureStore();
    ~SecureStore();

    // Connects to the daemon and creates the collection if needed.
    bool init();
    // False only when storage is switched off entirely.
    bool persistent() const { return !m_disabled; }
    Backend backend() const { return m_backend; }
    QString lastError() const { return m_lastError; }

    bool write(const QString &name, const QByteArray &data);
    QByteArray read(const QString &name, bool *found = nullptr);
    void remove(const QString &name);

    // Whether the private-file fallback may be used (the user's choice).
    void setFileAllowed(bool allowed) { m_fileAllowed = allowed; }
    bool fileAllowed() const { return m_fileAllowed; }
    // Secrets refused a value (or one was found in a file) and the user has
    // not decided yet whether the file may be used.
    bool consentNeeded() const { return m_consentNeeded; }
    bool secretsWorking() const { return m_secretsReady && !m_secretsFailed; }
    // Deletes the file copy, e.g. when the user says no to the fallback.
    void forgetFile(const QString &name);

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
    bool m_secretsFailed = false;
    bool m_disabled = false;
    bool m_fileAllowed = false;
    bool m_consentNeeded = false;
    QString m_lastError;
    QHash<QString, QByteArray> m_memory;
};

#endif // SECURESTORE_H
