TEMPLATE = app
TARGET = qmlsmoke
CONFIG += c++11
QT += quick qml network dbus
DEFINES += APP_VERSION=\\\"smoke\\\"

INCLUDEPATH += ../../src ../../third_party/sailfish-secrets ../../third_party/timed-qt5
LIBS += -l:libsailfishsecrets.so.0 -l:libtimed-qt5.so.0

HEADERS += ../../src/alarms.h ../../src/apiclient.h ../../src/appbridge.h ../../src/attachmentimages.h ../../src/redact.h ../../src/securestore.h ../../src/textutil.h
SOURCES += main.cpp ../../src/alarms.cpp ../../src/apiclient.cpp ../../src/appbridge.cpp ../../src/attachmentimages.cpp ../../src/redact.cpp ../../src/securestore.cpp ../../src/textutil.cpp
