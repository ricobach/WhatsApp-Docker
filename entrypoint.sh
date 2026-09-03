#!/usr/bin/env bash
set -euo pipefail

AVD_NAME="${AVD_NAME:-whatsapp}"
DISPLAY_NUM="${DISPLAY:-:0}"
WHATSAPP_PACKAGE="com.whatsapp"
CACHE_DIR="/opt/whatsapp/cache"
APK_PATH="${CACHE_DIR}/WhatsApp.apk"

mkdir -p "${CACHE_DIR}"

log() { echo "[whatsapp-docker] $*"; }

log "Starting virtual display and noVNC..."
pkill -9 -f "Xvfb ${DISPLAY_NUM} " 2>/dev/null || true
rm -f "/tmp/.X${DISPLAY_NUM#:}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM#:}"
Xvfb "${DISPLAY_NUM}" -screen 0 720x1280x24 &
XVFB_PID=$!

for _ in $(seq 1 15); do
  [ -e "/tmp/.X11-unix/X${DISPLAY_NUM#:}" ] && break
  kill -0 "${XVFB_PID}" 2>/dev/null || { log "Xvfb exited unexpectedly"; exit 1; }
  sleep 1
done

fluxbox >/tmp/fluxbox.log 2>&1 &
x11vnc -display "${DISPLAY_NUM}" -forever -nopw -quiet -rfbport 5900 \
  -afteraccept "adb shell monkey -p ${WHATSAPP_PACKAGE} -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true" &
websockify --web=/usr/share/novnc 6080 localhost:5900 &

log "Ensuring Android 16 virtual device exists..."
if [ ! -d "${HOME}/.android/avd/${AVD_NAME}.avd" ]; then
  echo "no" | avdmanager create avd \
    --force \
    --name "${AVD_NAME}" \
    --package "system-images;android-36;google_apis;x86_64" \
    --device "pixel_6"
fi

CONFIG_INI="${HOME}/.android/avd/${AVD_NAME}.avd/config.ini"
sed -i 's/^hw\.lcd\.height = .*/hw.lcd.height = 1280/' "${CONFIG_INI}" || true
sed -i 's/^hw\.lcd\.width = .*/hw.lcd.width = 720/' "${CONFIG_INI}" || true
sed -i 's/^hw\.lcd\.density = .*/hw.lcd.density = 320/' "${CONFIG_INI}" || true

find "${HOME}/.android/avd/${AVD_NAME}.avd" -name '*.lock' -exec rm -rf {} + 2>/dev/null || true

ACCEL_FLAGS="-accel off -gpu swiftshader_indirect"
if [ -e /dev/kvm ]; then
  log "/dev/kvm detected; enabling hardware acceleration."
  ACCEL_FLAGS="-accel on -gpu swiftshader_indirect"
else
  log "WARNING: /dev/kvm not available; emulator will use slow software emulation."
fi

log "Booting Android 16 emulator..."
# shellcheck disable=SC2086
emulator -avd "${AVD_NAME}" -no-audio -no-boot-anim -no-snapshot ${ACCEL_FLAGS} &
EMULATOR_PID=$!

adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  kill -0 "${EMULATOR_PID}" 2>/dev/null || { log "Android emulator exited unexpectedly"; exit 1; }
  sleep 2
done
log "Android 16 boot complete."

resolve_whatsapp_url() {
  if [ -n "${WHATSAPP_APK_URL:-}" ]; then
    printf '%s\n' "${WHATSAPP_APK_URL}"
    return 0
  fi

  printf '%s\n' "https://www.whatsapp.com/android/current/WhatsApp.apk"
}

download_whatsapp() {
  local url
  url="$(resolve_whatsapp_url)"
  log "Downloading current WhatsApp APK from the official WhatsApp download endpoint..."
  curl -fL --retry 3 --retry-delay 2 \
    -A 'Mozilla/5.0 (Linux; Android 16)' \
    -o "${APK_PATH}.tmp" "${url}"

  if [ "$(head -c 2 "${APK_PATH}.tmp" 2>/dev/null || true)" != "PK" ]; then
    rm -f "${APK_PATH}.tmp"
    log "ERROR: downloaded file is not an APK. Set WHATSAPP_APK_URL to an official APK URL and restart."
    return 1
  fi

  mv "${APK_PATH}.tmp" "${APK_PATH}"
}

if ! adb shell pm list packages | grep -q "package:${WHATSAPP_PACKAGE}$"; then
  download_whatsapp
  log "Installing WhatsApp..."
  if ! adb install -r "${APK_PATH}"; then
    log "ERROR: WhatsApp installation failed. The current official APK may not support this emulator ABI."
    log "Emulator ABI: $(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
    exit 1
  fi
else
  log "WhatsApp is already installed in the persistent Android volume."
fi

if [ "${WHATSAPP_UPDATE_ON_START:-false}" = "true" ]; then
  download_whatsapp
  log "Attempting WhatsApp update..."
  adb install -r "${APK_PATH}" || log "WARNING: update failed; keeping currently installed version."
fi

log "Launching WhatsApp..."
adb shell monkey -p "${WHATSAPP_PACKAGE}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true

cat <<EOF
============================================================
 WhatsApp Android 16 emulator is running.

 noVNC:  http://<docker-host>:${NOVNC_PORT:-6080}/vnc.html
 Package: ${WHATSAPP_PACKAGE}

 First run:
   Open noVNC and complete WhatsApp registration/linking.
   Android state is stored in the persistent android-data volume.

 Automatic APK update on container start:
   WHATSAPP_UPDATE_ON_START=true
============================================================
EOF

wait "${EMULATOR_PID}"
