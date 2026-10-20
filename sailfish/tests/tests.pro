TEMPLATE = app
TARGET = tst_harbour_vikunja
CONFIG += c++11 testcase
QT += network dbus qml
QT -= gui

# The SDK targets ship libQt5Test but not its headers. Point QTTEST_INCLUDE at
# a copy of the Qt 5.6 testlib headers, or install qt5-qttest-devel instead.
isEmpty(QTTEST_INCLUDE) {
    QT += testlib
} else {
    INCLUDEPATH += $$QTTEST_INCLUDE $$QTTEST_INCLUDE/QtTest
    LIBS += -l:libQt5Test.so.5
    DEFINES += QT_TESTLIB_LIB
}
DEFINES += APP_VERSION=\\\"test\\\"

INCLUDEPATH += ../src ../third_party/sailfish-secrets
LIBS += -l:libsailfishsecrets.so.0

HEADERS += ../src/apiclient.h ../src/redact.h ../src/securestore.h ../src/textutil.h
SOURCES += tst_harbour_vikunja.cpp ../src/apiclient.cpp ../src/redact.cpp ../src/securestore.cpp ../src/textutil.cpp
