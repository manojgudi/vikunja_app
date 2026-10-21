#include "securestore.h"
#include "appsettings.h"

#include <Secrets/createcollectionrequest.h>
#include <Secrets/deletesecretrequest.h>
#include <Secrets/result.h>
#include <Secrets/secret.h>
#include <Secrets/secretmanager.h>
#include <Secrets/storedsecretrequest.h>
#include <Secrets/storesecretrequest.h>

#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QtGlobal>

using namespace Sailfish::Secrets;

namespace {
// Version 0.2.0 and older used "harbourvikunja". Depending on how the app
// was started (launcher booster or D-Bus activation) Secrets saw a different
// owner for it, so writes could be refused; a fresh collection avoids
// inheriting one created under the wrong owner.
const QString CollectionName = QStringLiteral("harbourvikunjasession");
const QString OldCollectionName = QStringLiteral("harbourvikunja");

Secret::Identifier identifierFor(const QString &name)
{
    return Secret::Identifier(name, CollectionName, SecretManager::DefaultEncryptedStoragePluginName);
}

QString describe(const Result &r)
{
    return QStringLiteral("%1 (code %2)").arg(r.errorMessage()).arg(int(r.errorCode()));
}

// The daemon normally answers in milliseconds. Without a limit a stuck
// daemon would freeze the app until D-Bus gives up, long enough for the
// home screen to kill it.
const int RequestTimeoutMs = 4000;
}

bool SecureStore::run(Request &req)
{
    if (!m_secretsReady && !m_connecting)
        return false;
    QElapsedTimer clock;
    clock.start();
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
    QObject::connect(&req, &Request::statusChanged, &loop, [&req, &loop]() {
        if (req.status() == Request::Finished)
            loop.quit();
    });
    req.startRequest();
    if (req.status() != Request::Finished) {
        timer.start(RequestTimeoutMs);
        loop.exec(QEventLoop::ExcludeUserInputEvents);
    }
    if (req.status() != Request::Finished) {
        // Give up on Secrets for the rest of this run.
        m_lastError = QStringLiteral("secrets daemon did not answer within %1 ms").arg(RequestTimeoutMs);
        qWarning("%s", qPrintable(m_lastError));
        m_secretsReady = false;
        m_secretsFailed = true;
        return false;
    }
    if (clock.elapsed() > 1000)
        qWarning("Sailfish Secrets took %lld ms", qint64(clock.elapsed()));
    return true;
}

SecureStore::SecureStore() = default;

SecureStore::~SecureStore()
{
    delete m_manager;
}

QString SecureStore::privateDir()
{
    // ~/.local/share/io.github.manojgudi/harbour-vikunja: under sailjail only
    // this app can see it.
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

bool SecureStore::init()
{
    if (qEnvironmentVariableIsSet("HARBOUR_VIKUNJA_MEMORY_STORE")) {
        m_lastError = QStringLiteral("disabled by environment");
        m_backend = Memory;
        m_disabled = true;
        return false;
    }
    // Connecting to Secrets waits for the daemon, so it happens on first
    // use, after the window is up, not here.
    m_wantSecrets = !qEnvironmentVariableIsSet("HARBOUR_VIKUNJA_FILE_STORE");
    return true;
}

void SecureStore::connectSecrets()
{
    if (!m_wantSecrets)
        return;
    m_wantSecrets = false;
    if (!m_manager)
        m_manager = new SecretManager;
    m_connecting = true;
    m_secretsReady = ensureCollection();
    m_connecting = false;
    if (m_secretsReady) {
        QSettings settings(AppSettings::path(), QSettings::IniFormat);
        if (!settings.value(QStringLiteral("security/oldTokenRemoved")).toBool()) {
            removeOldToken();
            settings.setValue(QStringLiteral("security/oldTokenRemoved"), true);
        }
    }
    if (m_backend == Memory && m_secretsReady)
        m_backend = Secrets;
    AppSettings::diag(QStringLiteral("secrets: ready=%1 %2").arg(m_secretsReady).arg(m_lastError));
}

bool SecureStore::ensureCollection()
{
    if (!m_manager)
        return false;
    if (!m_manager->isInitialized()) {
        // The daemon connection completes asynchronously, and right after
        // boot the daemon itself may still be starting.
        QEventLoop loop;
        QTimer::singleShot(RequestTimeoutMs, &loop, &QEventLoop::quit);
        QObject::connect(m_manager, &SecretManager::isInitializedChanged, &loop, &QEventLoop::quit);
        loop.exec(QEventLoop::ExcludeUserInputEvents);
    }
    if (!m_manager->isInitialized()) {
        m_lastError = QStringLiteral("secrets daemon not reachable");
        return false;
    }
    CreateCollectionRequest req;
    req.setManager(m_manager);
    req.setCollectionName(CollectionName);
    req.setCollectionLockType(CreateCollectionRequest::DeviceLock);
    req.setDeviceLockUnlockSemantic(SecretManager::DeviceLockKeepUnlocked);
    req.setAccessControlMode(SecretManager::OwnerOnlyMode);
    req.setUserInteractionMode(SecretManager::PreventInteraction);
    req.setStoragePluginName(SecretManager::DefaultEncryptedStoragePluginName);
    req.setEncryptionPluginName(SecretManager::DefaultEncryptedStoragePluginName);
    req.setAuthenticationPluginName(SecretManager::DefaultAuthenticationPluginName);
    if (!run(req))
        return false;

    const Result result = req.result();
    if (result.code() == Result::Succeeded || result.errorCode() == Result::CollectionAlreadyExistsError)
        return true;
    m_lastError = describe(result);
    return false;
}

bool SecureStore::write(const QString &name, const QByteArray &data)
{
    m_memory.insert(name, data);
    if (m_disabled)
        return false;
    connectSecrets();

    if (m_secretsReady) {
        bool found = false;
        if (secretsWrite(name, data) && secretsRead(name, &found) == data && found) {
            fileRemove(name);
            m_secretsFailed = false;
            m_consentNeeded = false;
            m_backend = Secrets;
            return true;
        }
        qWarning("Sailfish Secrets did not keep the value (%s)", qPrintable(m_lastError));
        secretsRemove(name);
    }
    m_secretsFailed = true;
    if (!m_fileAllowed) {
        // Kept in memory until the user decides.
        m_consentNeeded = true;
        m_backend = Memory;
        return false;
    }
    m_consentNeeded = false;
    if (fileWrite(name, data)) {
        m_backend = PrivateFile;
        return true;
    }
    qWarning("Could not store the session; you will need to sign in again next time");
    m_backend = Memory;
    return false;
}

QByteArray SecureStore::read(const QString &name, bool *found)
{
    if (found)
        *found = false;
    if (m_memory.contains(name)) {
        if (found)
            *found = true;
        return m_memory.value(name);
    }
    if (m_disabled)
        return QByteArray();
    connectSecrets();

    bool ok = false;
    QByteArray data;
    if (m_secretsReady) {
        data = secretsRead(name, &ok);
        if (ok)
            m_backend = Secrets;
    }
    if (!ok) {
        data = fileRead(name, &ok);
        if (ok) {
            m_backend = PrivateFile;
            // A file from before the user was asked (version 0.2.1).
            if (!m_fileAllowed)
                m_consentNeeded = true;
        }
    }
    if (!ok)
        return QByteArray();
    m_memory.insert(name, data);
    if (found)
        *found = true;
    return data;
}

void SecureStore::remove(const QString &name)
{
    if (m_memory.contains(name))
        m_memory[name].fill('\0');
    m_memory.remove(name);
    if (m_disabled)
        return;
    connectSecrets();
    if (m_secretsReady)
        secretsRemove(name);
    fileRemove(name);
}

void SecureStore::forgetFile(const QString &name)
{
    fileRemove(name);
    m_consentNeeded = false;
    if (m_backend == PrivateFile)
        m_backend = Memory;
}

// --- Sailfish Secrets ------------------------------------------------------------

void SecureStore::removeOldToken()
{
    // Best effort: only works when the old collection has the same owner.
    DeleteSecretRequest req;
    req.setManager(m_manager);
    req.setIdentifier(Secret::Identifier(QStringLiteral("api-token"), OldCollectionName,
                                         SecretManager::DefaultEncryptedStoragePluginName));
    req.setUserInteractionMode(SecretManager::PreventInteraction);
    if (!run(req))
        return;
}

bool SecureStore::secretsWrite(const QString &name, const QByteArray &data)
{
    secretsRemove(name);

    Secret secret(identifierFor(name));
    secret.setType(Secret::TypeBlob);
    secret.setData(data);

    StoreSecretRequest req;
    req.setManager(m_manager);
    req.setSecretStorageType(StoreSecretRequest::CollectionSecret);
    req.setUserInteractionMode(SecretManager::PreventInteraction);
    req.setSecret(secret);
    if (!run(req))
        return false;
    if (req.result().code() != Result::Succeeded) {
        m_lastError = describe(req.result());
        return false;
    }
    return true;
}

QByteArray SecureStore::secretsRead(const QString &name, bool *found)
{
    *found = false;
    StoredSecretRequest req;
    req.setManager(m_manager);
    req.setIdentifier(identifierFor(name));
    req.setUserInteractionMode(SecretManager::PreventInteraction);
    if (!run(req))
        return QByteArray();
    if (req.result().code() != Result::Succeeded) {
        m_lastError = describe(req.result());
        return QByteArray();
    }
    *found = true;
    return req.secret().data();
}

void SecureStore::secretsRemove(const QString &name)
{
    DeleteSecretRequest req;
    req.setManager(m_manager);
    req.setIdentifier(identifierFor(name));
    req.setUserInteractionMode(SecretManager::PreventInteraction);
    if (!run(req))
        return;
}

// --- Private file fallback -----------------------------------------------------

QString SecureStore::filePath(const QString &name) const
{
    // Names are fixed identifiers chosen by the app, never user input.
    QString safe = name;
    for (QChar &c : safe) {
        if (!c.isLetterOrNumber() && c != QLatin1Char('_') && c != QLatin1Char('-'))
            c = QLatin1Char('_');
    }
    return privateDir() + QStringLiteral("/") + safe + QStringLiteral(".secret");
}

bool SecureStore::fileWrite(const QString &name, const QByteArray &data)
{
    const QString dir = privateDir();
    if (dir.isEmpty() || !QDir().mkpath(dir))
        return false;
    QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

    QSaveFile file(filePath(name));
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    if (file.write(data) != data.size() || !file.commit()) {
        m_lastError = file.errorString();
        return false;
    }
    return QFile::setPermissions(filePath(name), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}

QByteArray SecureStore::fileRead(const QString &name, bool *found)
{
    *found = false;
    QFile file(filePath(name));
    if (!file.open(QIODevice::ReadOnly))
        return QByteArray();
    const QByteArray data = file.readAll();
    if (data.isEmpty())
        return QByteArray();
    *found = true;
    return data;
}

void SecureStore::fileRemove(const QString &name)
{
    QFile file(filePath(name));
    if (!file.exists())
        return;
    // Overwrite before deleting so the old value is not left in free blocks
    // of the file itself.
    if (file.open(QIODevice::ReadWrite)) {
        file.write(QByteArray(int(file.size()), '\0'));
        file.flush();
        file.close();
    }
    file.remove();
}
