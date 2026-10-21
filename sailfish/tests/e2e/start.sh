#!/bin/bash
# Starts a private system and session bus plus the real timed from the target.
T=SailfishOS-5.2.0.15-i486
D=/home/mersdk/probe/e2e
cd $D
pkill -f "[a]rgv0 timed"; pkill -f "[a]rgv0 notifyd"; pkill -f "[a]rgv0 /usr/bin/harbour-vikunja"; pkill -f "[a]rgv0 dbus-daemon"; sleep 1
rm -f $D/sys.sock $D/ses.sock
sed "s#SOCK#$D/sys.sock#" bus.tmpl > sys.conf
sed "s#SOCK#$D/ses.sock#" bus.tmpl > ses.conf
nohup sb2 -t $T dbus-daemon --nofork --config-file=$D/sys.conf > sysbus.log 2>&1 &
nohup sb2 -t $T dbus-daemon --nofork --config-file=$D/ses.conf > sesbus.log 2>&1 &
sleep 2
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$D/sys.sock DBUS_SESSION_BUS_ADDRESS=unix:path=$D/ses.sock
nohup sb2 -t $T timed > timed.log 2>&1 &
sleep 3
sb2 -t $T dbus-send --system --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames | grep string
# On a phone dsme/lipstick tell timed the device reached USER mode; until then
# timed keeps its queue frozen.
sb2 -t $T dbus-send --system --type=signal /com/nokia/startup/signal com.nokia.startup.signal.desktop_visible
sleep 1
grep -v dsme timed.log | tail -3
