#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "Computing build version..."
echo ""
PRODUCT_VERSION=$(cargo run -q --bin mullvad-version versionName)
echo "Building Mullvad VPN $PRODUCT_VERSION for Android"
echo ""

BUILD_TYPE="release"
GRADLE_BUILD_TYPE="release"
GRADLE_TASKS=(createOssProdReleaseDistApk createPlayProdReleaseDistApk)
BUILD_BUNDLE="no"
BUNDLE_TASKS=(createPlayProdReleaseDistBundle)
RUN_PLAY_PUBLISH_TASKS="no"
PLAY_PUBLISH_TASKS=()
CARGO_ARGS=( "--release" )
CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-"target"}
SKIP_STRIPPING=${SKIP_STRIPPING:-"no"}

while [ -n "${1:-""}" ]; do
    if [[ "${1:-""}" == "--dev-build" ]]; then
        BUILD_TYPE="debug"
        GRADLE_BUILD_TYPE="debug"
        CARGO_ARGS=()
        GRADLE_TASKS=(createOssProdDebugDistApk)
        BUNDLE_TASKS=(createOssProdDebugDistBundle)
    elif [[ "${1:-""}" == "--fdroid" ]]; then
        GRADLE_BUILD_TYPE="fdroid"
        GRADLE_TASKS=(createOssProdFdroidDistApk)
        BUNDLE_TASKS=(createOssProdFdroidDistBundle)
    elif [[ "${1:-""}" == "--app-bundle" ]]; then
        BUILD_BUNDLE="yes"
    elif [[ "${1:-""}" == "--enable-play-publishing" ]]; then
        RUN_PLAY_PUBLISH_TASKS="yes"
    elif [[ "${1:-""}" == "--skip-stripping" ]]; then
        SKIP_STRIPPING="yes"
    fi

    shift 1
done

if [[ "$GRADLE_BUILD_TYPE" == "release" ]]; then
    if [ ! -f "$SCRIPT_DIR/android/credentials/keystore.properties" ]; then
        echo "ERROR: No keystore.properties file found" >&2
        echo "       Please configure the signing keys as described in the README" >&2
        exit 1
    fi
fi

if [[ "$BUILD_TYPE" == "release" ]]; then
    if [[ "$PRODUCT_VERSION" == *"-dev-"* ]]; then
        CARGO_ARGS+=( "--features" "api-override" )
        GRADLE_TASKS+=(createPlayDevmoleReleaseDistApk createPlayStagemoleReleaseDistApk)
        BUNDLE_TASKS+=(createPlayDevmoleReleaseDistBundle createPlayStagemoleReleaseDistBundle)
    elif [[ "$PRODUCT_VERSION" == *"-alpha"* ]]; then
        echo "Removing old Rust build artifacts"
        CARGO_ARGS+=( "--locked" )
        cargo clean
        CARGO_ARGS+=( "--features" "api-override" )
        GRADLE_TASKS+=(createPlayStagemoleReleaseDistApk)
        BUNDLE_TASKS+=(createPlayStagemoleReleaseDistBundle)
        PLAY_PUBLISH_TASKS=(publishPlayStagemoleReleaseBundle)
    else
        echo "Removing old Rust build artifacts"
        CARGO_ARGS+=( "--locked" )
        cargo clean
    fi
else
    CARGO_ARGS+=( "--features" "api-override" )
fi

pushd "$SCRIPT_DIR/android"

# Fallback to the system-wide gradle command if the gradlew script is removed.
# It is removed by the F-Droid build process before the build starts.
if [ -f "gradlew" ]; then
    GRADLE_CMD="./gradlew"
elif which gradle > /dev/null; then
    GRADLE_CMD="gradle"
else
    echo "ERROR: No gradle command found" >&2
    echo "       Please either install gradle or restore the gradlew file" >&2
    exit 2
fi

$GRADLE_CMD --console plain clean
mkdir -p "app/build/extraAssets"
mkdir -p "app/build/extraJni"
popd

for ARCHITECTURE in ${ARCHITECTURES:-aarch64 armv7 x86_64 i686}; do
    case "$ARCHITECTURE" in
        "x86_64")
            TARGET="x86_64-linux-android"
            ABI="x86_64"
            ;;
        "i686")
            TARGET="i686-linux-android"
            ABI="x86"
            ;;
        "aarch64")
            TARGET="aarch64-linux-android"
            ABI="arm64-v8a"
            ;;
        "armv7")
            TARGET="armv7-linux-androideabi"
            ABI="armeabi-v7a"
            ;;
    esac

    echo "Building mullvad-daemon for $TARGET"
    cargo build "${CARGO_ARGS[@]}" --target "$TARGET" --package mullvad-jni

    STRIP_TOOL="${NDK_TOOLCHAIN_DIR}/llvm-strip"
    TARGET_LIB_PATH="$SCRIPT_DIR/android/app/build/extraJni/$ABI/libmullvad_jni.so"
    UNSTRIPPED_LIB_PATH="$CARGO_TARGET_DIR/$TARGET/$BUILD_TYPE/libmullvad_jni.so"

    if [[ "$SKIP_STRIPPING" == "yes" ]]; then
        cp "$UNSTRIPPED_LIB_PATH" "$TARGET_LIB_PATH"
    else
        $STRIP_TOOL --strip-debug --strip-unneeded -o "$TARGET_LIB_PATH" "$UNSTRIPPED_LIB_PATH"
    fi
done

echo "Updating relays.json..."
cargo run --bin relay_list "${CARGO_ARGS[@]}" > android/app/build/extraAssets/relays.json

echo "Copying maybenot machines..."
cp dist-assets/maybenot_machines android/app/build/extraAssets/

cd "$SCRIPT_DIR/android"
$GRADLE_CMD --console plain "${GRADLE_TASKS[@]}"

if [[ "$BUILD_BUNDLE" == "yes" ]]; then
    $GRADLE_CMD --console plain "${BUNDLE_TASKS[@]}"
fi

if [[ "$RUN_PLAY_PUBLISH_TASKS" == "yes" && "${#PLAY_PUBLISH_TASKS[@]}" -ne 0 ]]; then
    $GRADLE_CMD --console plain "${PLAY_PUBLISH_TASKS[@]}"
fi

echo "**********************************"
echo ""
echo " The build finished successfully! "
echo " You have built:"
echo ""
echo " $PRODUCT_VERSION"
echo ""
echo "**********************************"
