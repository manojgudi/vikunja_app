#!/bin/bash
# Reminder tap lifecycle: sign in once, then each phase is a fresh process
# started like the D-Bus activated app. Runs inside the SDK build engine.
T=SailfishOS-5.2.0.15-i486
mkdir -p ~/build-smoke && cd ~/build-smoke
sb2 -t $T qmake ~/src/sailfish/tests/qmlsmoke/qmlsmoke.pro >/dev/null
sb2 -t $T make -j4 2>&1 | grep -E "error" | head -20
run() {
  sb2 -t $T env QT_QPA_PLATFORM=minimal SMOKE_PERSIST=1 SMOKE_PHASE=$2 $3 SMOKE_QML_DIR=/home/mersdk/src/sailfish/qml \
    SMOKE_DRIVER=/home/mersdk/src/sailfish/tests/qmlsmoke/$1 VIKUNJA_TEST_URL=http://localhost:3456 \
    VIKUNJA_TEST_USER=tester VIKUNJA_TEST_PASSWORD=Tester-pass-123 ./qmlsmoke 2>&1 | grep -E "SMOKE|Error|PROBLEM|rror:|vikunja-session|qml"
}
rm -rf ~/.local/share/harbour-vikunja-smoke ~/.config/harbour-vikunja-smoke
run RestartDriver.qml login
for phase in ${@:-tap tapslow donebg taplogin}; do
  echo "== $phase"
  run TapDriver.qml $phase SMOKE_BACKGROUND=1
done
