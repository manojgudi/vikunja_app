#!/bin/bash
# Setup used here: Xvfb + a Qt 5.15 QtWayland compositor (wl_shell; weston dropped
# it) on the host, and the host i386 Mesa + glibc in $H, because the SDK target
# has no software GL driver. Images are saved with alpha; flatten them on a
# dark background to view.
# Screenshots: needs weston --backend=headless with its socket at $WL.
T=SailfishOS-5.2.0.15-i486
WL=${WL:-/home/mersdk/wl}
OUT=${OUT:-/home/mersdk/probe/shots}
mkdir -p $OUT ~/build-smoke && cd ~/build-smoke
sb2 -t $T qmake ~/src/sailfish/tests/qmlsmoke/qmlsmoke.pro >/dev/null
sb2 -t $T make -j4 2>&1 | grep -E "error" | head -20
# The target's Mesa has no software rasteriser driver, so the host's i386
# Mesa (with its newer glibc) is loaded instead from $H.
H=${H:-/home/mersdk/probe/h32}
env QT_PLUGIN_PATH=/srv/mer/targets/$T/usr/lib/qt5/plugins QML2_IMPORT_PATH=/srv/mer/targets/$T/usr/lib/qt5/qml __EGL_VENDOR_LIBRARY_DIRS=$H/glvnd LIBGL_DRIVERS_PATH=$H/dri GALLIUM_DRIVER=llvmpipe LIBGL_ALWAYS_SOFTWARE=1 QT_QPA_PLATFORM=wayland-egl XDG_RUNTIME_DIR=$WL WAYLAND_DISPLAY=wayland-1 QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
  QT_QPA_EGLFS_PHYSICAL_WIDTH=65 QT_QPA_EGLFS_PHYSICAL_HEIGHT=130 SMOKE_VIEW=1 SMOKE_PERSIST=1 SMOKE_SHOT_DIR=$OUT SMOKE_PHASE="$1" \
  SMOKE_QML_DIR=/home/mersdk/src/sailfish/qml SMOKE_DRIVER=/home/mersdk/src/sailfish/tests/qmlsmoke/ShotDriver.qml \
  VIKUNJA_TEST_URL=http://localhost:3456 $H/ld-linux.so.2 --library-path $H:/srv/mer/targets/$T/usr/lib:/srv/mer/targets/$T/lib ./qmlsmoke 2>&1 > $OUT/run.log 2>&1; echo rc=$?; grep -vE "secrets daemon|^$|Theme dir|zN.M|Image dir" $OUT/run.log | tail -25
