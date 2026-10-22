FROM eclipse-temurin:21-jre AS java21

FROM node:22-bookworm-slim

# Firebase's Firestore emulator requires a JVM. Network access is permitted
# only while this image is built; the test container itself uses --network none.
RUN apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    curl \
    iproute2 \
  && rm -rf /var/lib/apt/lists/*

# Firebase CLI 15 requires Java 21+. Copy the pinned-major Temurin runtime
# during the network-enabled image build; the isolated test container remains
# offline and receives no host mounts or credentials.
COPY --from=java21 /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk

RUN npm install --global firebase-tools@15.29.0

ENV HOME=/opt/mood-v2-home
ENV PATH=/opt/java/openjdk/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /workspace

COPY functions/package.json functions/package-lock.json ./functions/
RUN npm ci --prefix functions

COPY functions ./functions
COPY firebase.mood-v2.emulators.json firestore.rules firestore.indexes.json ./
RUN npm run build --prefix functions \
  && java -version \
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
