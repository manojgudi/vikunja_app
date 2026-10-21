#!/bin/bash
# End-to-end reminder test with the real timed from the SDK target, a mock
# notification server, and the real app binary started by D-Bus activation.
T=SailfishOS-5.2.0.15-i486
# Runs inside the SDK build engine. Expects this folder at $D, the i486 RPM in
# ~/b-i486/RPMS, a Vikunja server on localhost:3456 and a token in
# ~/probe/apitoken.txt; adjust D and those paths for your setup.
D=/home/mersdk/probe/e2e
SB="sb2 -t $T"
set -e
cd $D
rm -f notify.log app.log e2e.log
# Start signed out, like a fresh install; the running app signs in and its
# token must still be there for the instance D-Bus starts later.
rm -rf ~/.local/share/io.github.manojgudi/harbour-vikunja ~/.config/io.github.manojgudi
# The app as installed on a phone.
$SB -m sdk-install -R rpm -U --force --nodeps ~/b-i486/RPMS/harbour-vikunja-*.i486.rpm
$SB rpm -q --requires harbour-vikunja | grep -i -E "timed|secrets|notif"
grep -A1 X-Sailjail /srv/mer/targets/$T/usr/share/applications/harbour-vikunja.desktop; grep ExecDBus /srv/mer/targets/$T/usr/share/applications/harbour-vikunja.desktop
# What sailjaild generates from ExecDBus, plus the headless platform.
cat > services/io.github.manojgudi.harbour-vikunja.service <<S
[D-BUS Service]
Name=io.github.manojgudi.harbour-vikunja
Exec=$D/launch.sh
S
cat > launch.sh <<S
#!/bin/sh
echo "APP STARTED \$(date -Is) args: -prestart" >> $D/app.log
# On the phone every session process has these; our private buses need them spelled out.
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$D/sys.sock DBUS_SESSION_BUS_ADDRESS=unix:path=$D/ses.sock
export QT_QPA_PLATFORM=minimal
/usr/bin/harbour-vikunja -prestart >> $D/app.log 2>&1
echo "APP EXITED \$(date -Is) rc=\$?" >> $D/app.log
S
chmod +x launch.sh
bash $D/start.sh
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$D/sys.sock DBUS_SESSION_BUS_ADDRESS=unix:path=$D/ses.sock
mkdir -p ~/build-e2e && cd ~/build-e2e
$SB qmake ~/src/sailfish/tests/e2e/notifyd.pro >/dev/null && $SB make -j4 >/dev/null
nohup $SB ./notifyd > $D/notify.log 2>&1 &
sleep 2
cd ~/build-smoke
$SB qmake ~/src/sailfish/tests/qmlsmoke/qmlsmoke.pro >/dev/null && $SB make -j4 2>&1 | grep -E "error" || true
nohup $SB dbus-monitor --session > $D/sesmon.log 2>&1 &
echo "== app running, $(date -Is)"
set +e
$SB env QT_QPA_PLATFORM=minimal SMOKE_REGISTER_BUS=1 SMOKE_PERSIST=1 SMOKE_REAL_NAMES=1 SMOKE_QML_DIR=/home/mersdk/src/sailfish/qml \
  SMOKE_DRIVER=/home/mersdk/src/sailfish/tests/e2e/E2EDriver.qml VIKUNJA_TEST_URL=http://localhost:3456 \
  VIKUNJA_TEST_TOKEN=$(cat ~/probe/apitoken.txt) ./qmlsmoke > $D/e2e.log 2>&1
echo "== app closed rc=$?, $(date -Is)"
grep -E "E2E|Error|PROBLEM|RESULT" $D/e2e.log
echo "== events in timed after the app closed:"
$SB dbus-send --system --print-reply --dest=com.nokia.time /com/nokia/time com.nokia.time.get_cookies_by_attributes dict:string:string:APPLICATION,harbour_vikunja | grep uint32 | wc -l
echo "== waiting for the due date (app is not running)"
sleep 50
echo "--- app process after the reminder (should have exited by itself):"
pgrep -af "[a]rgv0 /usr/bin/harbour-vikunja" | cut -c1-60 || echo "  none"
pkill -f "[a]rgv0 /usr/bin/harbour-vikunja"
echo "== tapping the reminder like lipstick does (app is not running)"
# lipstick sends the action's arguments exactly as the app stored them: a
# QDataStream of QVariants after the method name, base64-encoded.
ACTION=$(grep -A1 '"x-nemo-remote-action-default"' $D/sesmon.log | tail -1 | sed 's/.*string "//; s/"$//')
echo "  action: $ACTION"
set -- $ACTION
ARGS=""
HEX=$(echo "$5" | base64 -d | od -An -tx1 -v | tr -d ' \n')
while [ -n "$HEX" ]; do
  TYPE=$((16#${HEX:0:8})); HEX=${HEX:10}
  case $TYPE in
    2) ARGS="$ARGS int32:$((16#${HEX:0:8}))"; HEX=${HEX:8} ;;
    6) ARGS="$ARGS double:$(python3 -c "import struct;print(struct.unpack('>d',bytes.fromhex('${HEX:0:16}'))[0])" 2>/dev/null || echo 0)"; HEX=${HEX:16} ;;
    *) echo "  unknown variant type $TYPE"; HEX="" ;;
  esac
done
echo "  call: $4$ARGS"
$SB dbus-send --session --print-reply --dest=$1 $2 $3.$4 $ARGS 2>&1 | head -3
sleep 8
echo "--- app process after the tap (should be showing its window):"
pgrep -af "[a]rgv0 /usr/bin/harbour-vikunja" | cut -c1-60 || echo "  none"
pkill -f "[a]rgv0 /usr/bin/harbour-vikunja"
echo "--- session log"; tail -25 ~/.cache/io.github.manojgudi/harbour-vikunja/session.log
echo "== $(date -Is)"
echo "--- notification server log"; cat $D/notify.log
echo "--- app log"; cat $D/app.log
echo "--- timed log (tail)"; tail -15 $D/timed.log
