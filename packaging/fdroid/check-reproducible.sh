#!/usr/bin/env bash
# Checks that F-Droid's build of a commit reproduces a signed APK from the GitHub release job
# (RELEASING.md 4.6): builds the commit in F-Droid's buildserver image the way fdroiddata's CI
# job runs the recipe (sudo: as root, build: as vagrant in /home/vagrant/build/<appid>, with
# SOURCE_DATE_EPOCH), then copies the signature over with apksigcopier and verifies.
#
# Usage: packaging/fdroid/check-reproducible.sh <commit> <signed.apk>
#   e.g. the plasmai-test-apk artifact of a hand-run release.yml, or a release's APK.
# Needs: docker, apksigcopier (pip), apksigner on PATH (Android build-tools).
# Keep the setup below in step with the recipe's sudo: block.
set -euo pipefail
COMMIT="${1:?commit}"
SIGNED="$(realpath "${2:?signed APK}")"
OUT="$(mktemp -d)"
IMAGE=registry.gitlab.com/fdroid/fdroidserver:buildserver-trixie

cat > "$OUT/run.sh" <<'EOF'
set -e -u -o pipefail
source /etc/profile.d/bsenv.sh || true
export DEBIAN_FRONTEND=noninteractive
apt-get update -q > /dev/null
apt-get install -y -q openjdk-21-jdk-headless sudo git > /dev/null
update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java
SDK=${ANDROID_HOME:-/opt/android-sdk}
# The recipe's sudo:
apt-get install -y --no-install-recommends cmake ninja-build python3-pip perl make g++ libegl1 \
    libgl1 libxkbcommon0 libfontconfig1 libdbus-1-3 > /dev/null
pip install -q --break-system-packages aqtinstall
aqt install-qt linux android 6.7.3 android_arm64_v8a -m qtshadertools -O /opt/plasmai-qt > /dev/null
aqt install-qt linux desktop 6.7.3 linux_gcc_64 -m qtshadertools -O /opt/plasmai-qt > /dev/null
yes | sdkmanager --licenses > /dev/null || true
sdkmanager "ndk;28.2.13676358" "platforms;android-34" "build-tools;34.0.0" > /dev/null
chown -R vagrant "$SDK"
B=/home/vagrant/build/com.github.shrippen.plasmai
mkdir -p /home/vagrant/build
git clone -q https://github.com/shrippen/Plasmai.git $B
git -C $B checkout -q "$COMMIT"
# The recipe's scandelete:
rm -f $B/app/libs/openssl/arm64-v8a/libssl_3.so $B/app/libs/openssl/arm64-v8a/libcrypto_3.so
SDE=$(git -C $B log -n1 --pretty=%ct)
chown -R vagrant /home/vagrant
cd $B
sudo -u vagrant env HOME=/home/vagrant PATH="$PATH" SOURCE_DATE_EPOCH="$SDE" \
    bash -e -u -o pipefail -c "ANDROID_SDK_ROOT=$SDK scripts/build-apk-reproducible.sh" > /out/build.log 2>&1 \
    || { tail -n 50 /out/build.log; exit 1; }
cp app/build-android/android-build/build/outputs/apk/release/android-build-release-unsigned.apk /out/unsigned.apk
chmod a+rw /out/unsigned.apk /out/build.log
EOF

echo "Building $COMMIT in $IMAGE (log: $OUT/build.log)..."
docker run --rm -e COMMIT="$COMMIT" -v "$OUT:/out" "$IMAGE" bash /out/run.sh
apksigcopier compare --unsigned "$SIGNED" "$OUT/unsigned.apk" \
    && echo "REPRODUCIBLE: F-Droid's build of $COMMIT plus the signature of $SIGNED verifies."
