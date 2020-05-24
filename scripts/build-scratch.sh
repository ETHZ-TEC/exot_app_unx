# Copyright (c) 2015-2020, Swiss Federal Institute of Technology (ETH Zurich)
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 
#!/usr/bin/env bash

ERRORED=0

u:info() {
    (echo >&2 -e "[\e[1m\e[34minfo\e[0m]\t" "$@")
}

u:warn() {
    (echo >&2 -e "[\e[1m\e[33mwarn\e[0m]\t" "$@")
}

u:erro() {
    (echo >&2 -e "[\e[1m\e[31merror\e[0m]\t" "$@")
    ERRORED=1
    exit 1
}

u:exit() {
    if [ $ERRORED -ne 0 ]; then
        u:warn "Exiting unsuccessfully!"
    fi
}

trap u:exit EXIT

PLATFORMS="x86_64 aarch64 arm armhf"
CONFIGS="Release RelWithDebInfo MinSizeRel Debug"
SCRIPT=${SCRIPT:-dock}

SOURCE=${SOURCE:-src}
BUILD=${BUILD:-build}

command -v docker 1>/dev/null 2>/dev/null ||
    u:err "The script requires the Docker container to be available. " \
        "Docker does not seem to be available on the host device."

docker ps -q 1>/dev/null 2>/dev/null ||
    u:err "The script requires the Docker container to be available. " \
        "Docker does not seem to be available on the host device."

command -v "$SCRIPT" 1>/dev/null 2>/dev/null ||
    u:err "The docker script $SCRIPT does not exist in PATH. " \
        "Please make the required images (in lib/tools/docker) and provide " \
        "the path to the launcher script with SCRIPT, or store in PATH."

u:info "Using source folder: $SOURCE"
test -e "$SOURCE/CMakeLists.txt" ||
    u:err "The provided source folder: $SOURCE, does not seem to contain a " \
        "CMakeLists.txt file."

TARGET=""
CONFIG=""
ARGUMENTS=""

u:info "This script will pass all arguments to the CMake configure command"

if [[ $# -ne 0 ]]; then
    u:info "The provided arguments are: " "$@"
    ARGUMENTS="$*"
else
    u:info "No additional arguments provided"
fi

u:info "Choose the target platform:"
select PLATFORM in $PLATFORMS; do
    u:info "Chose platform $REPLY) $PLATFORM"
    TARGET=$PLATFORM
    break
done

if [[ -z $TARGET ]]; then
    u:erro "No target specified! Choose one of: $PLATFORMS"
fi

u:info "Choose the build configuration:"
select CONF in $CONFIGS; do
    u:info "Chose config $REPLY) $CONF"
    CONFIG=$CONF
    break
done

FENCE=0
TIME_SOURCE=4

AVAILABLE_FENCE="Atomic Weak Strong None"
AVAILABLE_TIME_SOURCE="SteadyClock MonotonicCounter MonotonicClock \
    TimeStampCounter HardwarePerformanceCounter SoftwarePerformanceCounter"

CHOSEN_FENCE=""
CHOSEN_TIME_SOURCE=""

u:info "Choose default timing serialisation:"
select SERIAL in $AVAILABLE_FENCE; do
    FENCE=$((REPLY - 1))
    CHOSEN_FENCE="$SERIAL"
    u:info "Chose serialisation $REPLY) $SERIAL [$FENCE]"
    break
done

u:info "Choose default timing source:"
select TIMING in $AVAILABLE_TIME_SOURCE; do
    TIME_SOURCE=$((REPLY - 1))
    CHOSEN_TIME_SOURCE="$TIMING"
    u:info "Chose serialisation $REPLY) $TIMING [$TIME_SOURCE]"
    break
done

if [[ -z $CONFIG ]]; then
    u:erro "No configuration specified! Choose one of: $CONFIGS"
fi

u:cmake:configure() {
    $SCRIPT cmake \
        -DCMAKE_TOOLCHAIN_FILE="/tool/static/$PLATFORM.cmake" \
        -DEXOT_TIME_FENCE="$FENCE" \
        -DEXOT_TIME_SOURCE="$TIME_SOURCE" \
        "$ARGUMENTS" \
        -B"$BUILD/$TARGET" \
        -H"$SOURCE"
}

u:info "Running CMake configuration step..."
u:cmake:configure 1>/dev/null 2>/dev/null
u:cmake:configure # configure again to account for docker issue
test $? -eq 0 || u:erro "CMake configuration step failed!"

u:cmake:build() {
    $SCRIPT cmake \
        --build "$BUILD/$TARGET" --config "$CONFIG" \
        --target "$1" -- -j 10 --quiet --stop
}

u:info "Running CMake build step..."
u:cmake:build all-apps
u:cmake:build all-utilities

read -r -p "Copy the targets built for $TARGET to $TARGET/? (y/N) " choice
if [[ $choice == [yY] || $choice == [yY][eE][sS] ]]; then
    mkdir -p $TARGET || u:warn "mkdir failed to create directory $TARGET"
    u:info "Copying built targets over to $TARGET"
    find "$BUILD/$TARGET" \
        -maxdepth 1 -type f -executable \
        -exec cp -v {} "$TARGET/" \;

    cp "$BUILD/$TARGET/CMakeCache.txt" "$TARGET/CMakeCache.txt"
    cat << __EOF__ > "$TARGET/build_info.json"
{
    "platform": "$TARGET",
    "config": "$CONFIG",
    "commit": "$(git rev-parse HEAD)",
    "dirty": $(git diff --stat --quiet && echo false || echo true),
    "timing": {
        "fence_id": $FENCE,
        "source_id": $TIME_SOURCE,
        "fence": "$CHOSEN_FENCE",
        "source": "$CHOSEN_TIME_SOURCE"
    }
}
__EOF__
fi
