#include "securestore.h"

#include <Secrets/createcollectionrequest.h>
#include <Secrets/deletesecretrequest.h>
#include <Secrets/result.h>
#include <Secrets/secret.h>
#include <Secrets/secretmanager.h>
#include <Secrets/storedsecretrequest.h>
#include <Secrets/storesecretrequest.h>

#include <QEventLoop>
#include <QTimer>
#include <QtGlobal>

using namespace Sailfish::Secrets;

namespace {
const QString CollectionName = QStringLiteral("harbourvikunja");

Secret::Identifier identifierFor(const QString &name)
{
    return Secret::Identifier(name, CollectionName, SecretManager::DefaultEncryptedStoragePluginName);
}
}

SecureStore::SecureStore() = default;

SecureStore::~SecureStore()
{
    delete m_manager;
}

bool SecureStore::init()
{
    if (qEnvironmentVariableIsSet("HARBOUR_VIKUNJA_MEMORY_STORE")) {
        m_lastError = QStringLiteral("disabled by environment");
        return false;
    }
    if (!m_manager)
        m_manager = new SecretManager;
    m_persistent = ensureCollection();
    if (!m_persistent)
        qWarning("Secure storage unavailable, credentials will be kept in memory only: %s", qPrintable(m_lastError));
    return m_persistent;
}

bool SecureStore::ensureCollection()
{
    if (!m_manager->isInitialized()) {
        // The daemon connection may complete asynchronously.
        QEventLoop loop;
        QTimer::singleShot(3000, &loop, &QEventLoop::quit);
        QObject::connect(m_manager, &SecretManager::isInitializedChanged, &loop, &QEventLoop::quit);
        loop.exec();
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
    req.startRequest();
    req.waitForFinished();

    const Result result = req.result();
    if (result.code() == Result::Succeeded || result.errorCode() == Result::CollectionAlreadyExistsError)
        return true;
    m_lastError = result.errorMessage();
    return false;
}

bool SecureStore::write(const QString &name, const QByteArray &data)
{
    m_memory.insert(name, data);
    if (!m_persistent)
        return false;

    remove(name);
    m_memory.insert(name, data);

    Secret secret(identifierFor(name));
    secret.setType(Secret::TypeBlob);
    secret.setData(data);

    StoreSecretRequest req;
    req.setManager(m_manager);
    req.setSecretStorageType(StoreSecretRequest::CollectionSecret);
    req.setUserInteractionMode(SecretManager::PreventInteraction);
    req.setSecret(secret);
    req.startRequest();
    req.waitForFinished();
    if (req.result().code() != Result::Succeeded) {
        m_lastError = req.result().errorMessage();
        qWarning("Could not store secret: %s", qPrintable(m_lastError));
        return false;
    }
    return true;
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
    if (!m_persistent)
        return QByteArray();

    StoredSecretRequest req;
    req.setManager(m_manager);
    req.setIdentifier(identifierFor(name));
    req.setUserInteractionMode(SecretManager::PreventInteraction);
    req.startRequest();
    req.waitForFinished();
    if (req.result().code() != Result::Succeeded)
        return QByteArray();

    const QByteArray data = req.secret().data();
    m_memory.insert(name, data);
    if (found)
        *found = true;
    return data;
}

void SecureStore::remove(const QString &name)
{
    m_memory.remove(name);
    if (!m_persistent)
        return;

    DeleteSecretRequest req;
    req.setManager(m_manager);
    req.setIdentifier(identifierFor(name));
    req.setUserInteractionMode(SecretManager::PreventInteraction);
    req.startRequest();
    req.waitForFinished();
}
