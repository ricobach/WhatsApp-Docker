FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    DISPLAY=:0

ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator"

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk-headless \
    curl unzip ca-certificates \
    libgl1 libpulse0 libxcomposite1 libxcursor1 libxi6 libxtst6 libnss3 \
    libxss1 libasound2t64 libxrandr2 libxdamage1 libxfixes3 fonts-dejavu-core \
    xvfb x11vnc fluxbox novnc websockify \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
       https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    && unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip

RUN yes | sdkmanager --licenses >/dev/null \
    && sdkmanager --install \
       "platform-tools" \
       "emulator" \
       "system-images;android-36;google_apis;x86_64"

COPY entrypoint.sh /opt/whatsapp/entrypoint.sh
RUN chmod +x /opt/whatsapp/entrypoint.sh

EXPOSE 6080

VOLUME ["/root/.android", "/opt/whatsapp/cache"]

ENTRYPOINT ["/opt/whatsapp/entrypoint.sh"]
