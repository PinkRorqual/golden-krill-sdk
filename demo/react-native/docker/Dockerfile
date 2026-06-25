# Builds the Expo / React Native demo APK. Extends the studio Flutter image (which already
# carries JDK 17 + the Android SDK + accepted licences) and adds Node.js, which RN/Expo need.
# Build the base first if missing:  docker build -t pinkrorqual-flutter:latest <any-app>/docker/
FROM pinkrorqual-flutter:latest

USER root
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
USER vscode
