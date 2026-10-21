#!/bin/bash
# Separate processes act like closing and reopening the app.
mkdir -p ~/build-smoke && cd ~/build-smoke
sb2 -t SailfishOS-5.2.0.15-i486 qmake ~/src/sailfish/tests/qmlsmoke/qmlsmoke.pro >/dev/null
sb2 -t SailfishOS-5.2.0.15-i486 make -j4 2>&1 | grep -E "error" | head -20
run() {
  sb2 -t SailfishOS-5.2.0.15-i486 env QT_QPA_PLATFORM=minimal SMOKE_PERSIST=1 SMOKE_PHASE=$1 SMOKE_QML_DIR=/home/mersdk/src/sailfish/qml SMOKE_DRIVER=/home/mersdk/src/sailfish/tests/qmlsmoke/RestartDriver.qml VIKUNJA_TEST_URL=http://localhost:3456 VIKUNJA_TEST_USER=tester VIKUNJA_TEST_PASSWORD=Tester-pass-123 ./qmlsmoke 2>&1 | grep -E "SMOKE|Error|PROBLEM"
  # What sailjail keeps between runs: only ~/.config/<org>/<app>/,
  # ~/.local/share/<org>/<app>/ and ~/.cache/<org>/<app>/.
  for d in ~/.config/harbour-vikunja-smoke ~/.local/share/harbour-vikunja-smoke ~/.cache/harbour-vikunja-smoke; do
    [ -d "$d" ] && find "$d" -mindepth 1 -maxdepth 1 ! -name smoke -exec rm -rf {} +
  done
  echo "  config: $(ls ~/.config/harbour-vikunja-smoke/smoke/ 2>/dev/null)"
  echo "  files: $(ls -l ~/.local/share/harbour-vikunja-smoke/smoke/ 2>/dev/null | tail -n +2 | awk '{print $1, $NF}')"
}
for seq in "decline after" "login reopen reminder stale cover signout after"; do
  echo "== $seq"
  rm -rf ~/.local/share/harbour-vikunja-smoke ~/.config/harbour-vikunja-smoke
  for phase in $seq; do run $phase; done
done
