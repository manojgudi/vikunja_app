TEMPLATE = app
TARGET = qmlsmoke
CONFIG += c++11
QT += quick qml network dbus
DEFINES += APP_VERSION=\\\"smoke\\\"

INCLUDEPATH += ../../src ../../third_party/sailfish-secrets
LIBS += -l:libsailfishsecrets.so.0

HEADERS += ../../src/apiclient.h ../../src/appbridge.h ../../src/redact.h ../../src/securestore.h ../../src/textutil.h
SOURCES += main.cpp ../../src/apiclient.cpp ../../src/appbridge.cpp ../../src/redact.cpp ../../src/securestore.cpp ../../src/textutil.cpp
