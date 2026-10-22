FROM node:22-bookworm-slim

# Firebase's Firestore emulator requires a JVM. Network access is permitted
# only while this image is built; the test container itself uses --network none.
RUN apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    curl \
    default-jre-headless \
    iproute2 \
  && rm -rf /var/lib/apt/lists/*

RUN npm install --global firebase-tools@15.29.0

ENV HOME=/opt/mood-v2-home
ENV PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /workspace

COPY functions/package.json functions/package-lock.json ./functions/
RUN npm ci --prefix functions

COPY functions ./functions
COPY firebase.mood-v2.emulators.json firestore.rules firestore.indexes.json ./
RUN npm run build --prefix functions \
  && mkdir -p "$HOME" \
  && firebase setup:emulators:firestore \
  && printf '%s\n' 'SUPER_ADMIN_UID=mood-v2-ci-super-admin' > functions/.env.local \
  && chmod 600 functions/.env.local

COPY ci/run_mood_v2_staging_identity_docker_container.sh /usr/local/bin/mood-v2-mode-b-run
RUN chmod 755 /usr/local/bin/mood-v2-mode-b-run \
  && useradd --create-home --uid 10001 moodv2 \
  && chown -R moodv2:moodv2 /workspace "$HOME"

USER moodv2
ENTRYPOINT ["/usr/local/bin/mood-v2-mode-b-run"]
