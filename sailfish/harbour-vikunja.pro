TARGET = harbour-vikunja
VERSION = 0.2.10

CONFIG += sailfishapp c++11
QT += network dbus

DEFINES += APP_VERSION=\\\"$$VERSION\\\"

# Public headers of libsailfishsecrets 0.2.44 (BSD-3-Clause), vendored because
# the SDK targets ship the library but not its -devel package.
INCLUDEPATH += $$PWD/third_party/sailfish-secrets
LIBS += -l:libsailfishsecrets.so.0

# Public headers of libtimed-qt5 3.6.24 (LGPL-2.1), for the same reason.
# Scheduling reminders with timed is not allowed in Harbour; this is a
# sideload-only feature.
INCLUDEPATH += $$PWD/third_party/timed-qt5
LIBS += -l:libtimed-qt5.so.0

HEADERS += \
    src/alarms.h \
    src/apiclient.h \
    src/appsettings.h \
    src/appbridge.h \
    src/attachmentimages.h \
    src/redact.h \
    src/securestore.h \
    src/textutil.h

SOURCES += \
    src/main.cpp \
    src/alarms.cpp \
    src/apiclient.cpp \
    src/appbridge.cpp \
    src/attachmentimages.cpp \
    src/redact.cpp \
    src/securestore.cpp \
    src/textutil.cpp

DISTFILES += \
    qml/harbour-vikunja.qml \
    qml/cover/*.qml \
    qml/pages/*.qml \
    qml/components/*.qml \
    qml/js/*.js \
    rpm/harbour-vikunja.spec \
    harbour-vikunja.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

# Notification category: sound/vibration and a banner for reminders.
notificationcategory.files = notifications/x-harbour-vikunja.reminder.conf
notificationcategory.path = /usr/share/lipstick/notificationcategories
INSTALLS += notificationcategory
