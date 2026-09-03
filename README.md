# WhatsApp-Docker

Experimental Docker setup that runs an Android emulator with WhatsApp and exposes the emulator UI through noVNC.

## What it does

- Runs an Android 14 (API 34) x86_64 emulator inside Docker.
- Uses `/dev/kvm` when available for hardware acceleration.
- Exposes the Android screen through noVNC on port `6080`.
- Downloads the WhatsApp APK on first start instead of storing the APK in Git.
- Persists the Android emulator state in a Docker volume so registration/linking survives container restarts.
- Can optionally attempt to download and install the current APK every time the container starts.

## Requirements

A Linux Docker host is strongly recommended.

For usable emulator performance, the host should expose `/dev/kvm` to Docker.

Check with:

```bash
ls -l /dev/kvm
```

Docker Desktop on Windows/macOS generally cannot pass the Linux host KVM device through in the same way.

## Start

```bash
docker compose build
docker compose up -d
docker compose logs -f
```

Then open:

```text
http://<docker-host>:6080/vnc.html
```

Complete the WhatsApp setup interactively in the Android emulator.

## WhatsApp APK download

By default the startup script attempts to use WhatsApp's official Android direct-download endpoint:

```text
https://www.whatsapp.com/android/current/WhatsApp.apk
```

The APK is downloaded only when WhatsApp is not already installed.

If WhatsApp changes the direct-download mechanism, set an explicit official APK URL:

```yaml
environment:
  WHATSAPP_APK_URL: "https://.../WhatsApp.apk"
```

The download script verifies that the returned file has the basic APK/ZIP signature before installing it.

## Updating WhatsApp automatically

WhatsApp itself can perform application updates. For an additional container-side update attempt on every container start, set:

```yaml
environment:
  WHATSAPP_UPDATE_ON_START: "true"
```

The startup process then downloads the current APK and performs:

```bash
adb install -r WhatsApp.apk
```

This preserves the installed application's data.

For the initial setup, `WHATSAPP_UPDATE_ON_START` is intentionally disabled. Once APK download and emulator compatibility have been verified, enabling it is reasonable.

## Persistent data

Two volumes are used:

- `android-data` stores the Android virtual device and its application data.
- `whatsapp-cache` stores the downloaded APK.

Do **not** delete `android-data` unless you intentionally want to reset the emulated Android device. Removing it will also remove the WhatsApp application state and require setup again.

## Architecture warning

The initial image uses Google's `x86_64` Android emulator image because this provides good performance with KVM on normal x86 Linux servers.

Whether the current WhatsApp APK installs successfully on that ABI must be tested with the current WhatsApp release. If Meta distributes an ARM-only build through the direct-download channel, the next iteration should either:

1. use a compatible APK source/distribution path, or
2. change the emulator architecture.

The startup script reports the emulator ABI if installation fails.

## Security / scope

This initial version does not contain Frida or application instrumentation. It is intended only to provide a persistent Android environment in which the official WhatsApp application can run.

Future automation or Home Assistant integration should be implemented separately rather than depending on WhatsApp internal classes unless there is a specific need for runtime instrumentation.
