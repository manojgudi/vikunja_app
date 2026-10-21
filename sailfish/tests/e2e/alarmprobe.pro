TEMPLATE = app
TARGET = alarmprobe
CONFIG += c++11 console
QT = core dbus
INCLUDEPATH += ../../src ../../third_party/timed-qt5
LIBS += -l:libtimed-qt5.so.0
HEADERS += ../../src/alarms.h
SOURCES += alarmprobe.cpp ../../src/alarms.cpp
