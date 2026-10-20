TARGET = harbour-vikunja
VERSION = 0.1.0

CONFIG += sailfishapp c++11
QT += network dbus

DEFINES += APP_VERSION=\\\"$$VERSION\\\"

# Public headers of libsailfishsecrets 0.2.44 (BSD-3-Clause), vendored because
# the SDK targets ship the library but not its -devel package.
INCLUDEPATH += $$PWD/third_party/sailfish-secrets
LIBS += -l:libsailfishsecrets.so.0

HEADERS += \
    src/apiclient.h \
    src/appbridge.h \
    src/redact.h \
    src/securestore.h \
    src/textutil.h

SOURCES += \
    src/main.cpp \
    src/apiclient.cpp \
    src/appbridge.cpp \
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
