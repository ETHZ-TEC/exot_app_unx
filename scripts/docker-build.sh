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
#
# This script bootstraps builds and compiles all apps for toolchains
# available in the Docker container.

platforms='x86_64 aarch64'
configurations='debug release'
build_dir=${BUILD_DIR:-build}
script=${SCRIPT:-dock}
arg=$1
source=${arg:-.}

u:to_title() {
    sed 's/.*/\L&/; s/[a-z]*/\u&/g' <<<"$1"
}

u:to_lower() {
    tr \[:upper:\] \[:lower:\] <<<"$1"
}

u:to_upper() {
    tr \[:lower:\] \[:upper:\] <<<"$1"
}

u:info() {
    (echo >&2 -e "–– Info  ––" "$@")
}

u:err() {
    (echo >&2 -e "–– Error ––" "$@")
    exit 1
}

command -v docker 1>/dev/null 2>/dev/null ||
    u:err "The script requires the Docker container to be available. " \
        "Docker does not seem to be available on the host device."

docker ps -q 1>/dev/null 2>/dev/null ||
    u:err "The script requires the Docker container to be available. " \
        "Docker does not seem to be available on the host device."

command -v "$script" 1>/dev/null 2>/dev/null ||
    u:err "The docker script $script does not exist in PATH. " \
        "Please make the required images (in lib/tools/docker) and provide " \
        "the path to the launcher script with SCRIPT, or store in PATH."

u:info "Using source folder: $source"
test -e "$source/CMakeLists.txt" ||
    u:err "The provided source folder: $source, does not seem to contain a " \
        "CMakeLists.txt file."

read -r -p "–– Input –– Would you like to set up build directories for all platforms? (y/n): " \
    choice && [[ $choice == [yY] || $choice == [yY][eE][sS] ]] &&
    u:info "Build directories wil be set up in: $build_dir" &&
    {
        for platform in $platforms; do
            u:info "Setting up for toolchain: $platform"
            for configuration in $configurations; do
                u:info "Setting up for configuration: $configuration"
                $script cmake \
                    -DCMAKE_TOOLCHAIN_FILE=/tool/static/"$platform".cmake \
                    -DCMAKE_BUILD_TYPE="$(u:to_title "$configuration")" \
                    -B"$build_dir/$platform/$configuration" -H"$source" \
                    1>/dev/null 2>/dev/null
                $script cmake \
                    -DCMAKE_TOOLCHAIN_FILE=/tool/static/"$platform".cmake \
                    -DCMAKE_BUILD_TYPE="$(u:to_title "$configuration")" \
                    -B"$build_dir/$platform/$configuration" -H"$source" \
                    1>/dev/null 2>/dev/null
                test $? -eq 0 || u:err "CMake setup failed!"
            done
        done
    }

read -r -p "–– Input –– Would you like to compile all targets for all platforms? (y/n): " \
    choice && [[ $choice == [yY] || $choice == [yY][eE][sS] ]] &&
    {
        CONCURRENCY=4
        command -v lscpu 1>/dev/null 2>/dev/null &&
            CONCURRENCY=$(lscpu -p | grep -c "^[0-9]")

        u:info "Concurrency: $CONCURRENCY"

        for platform in $platforms; do
            u:info "Building for toolchain: $platform"
            for configuration in $configurations; do
                u:info "Building for configuration: $configuration"
                $script cmake --build "$build_dir/$platform/$configuration" \
                    --target all-apps -- -j "$CONCURRENCY" --quiet --stop
            done
        done
    }

read -r -p "–– Input –– Would you like to export a list of executables to '../exe' directory? (y/n): " \
    choice && [[ $choice == [yY] || $choice == [yY][eE][sS] ]] &&
    {
        u:info "Entering $build_dir"
        pushd "$PWD" 1>/dev/null 2>/dev/null &&
            u:info "Saving working directory: pushing $PWD"
        cd "$build_dir" || u:err
        mkdir -p ../exe
        how_many=$(find . -maxdepth 3 -type f -executable | wc -l)
        u:info "$how_many executables will be copied to $PWD/../exe"
        find . -maxdepth 3 -type f -executable -exec cp --parent '{}' ../exe \;
        u:info "Find terminated with status: $?"
        popd 1>/dev/null 2>/dev/null && u:info "Restoring working directory"
    }

read -r -p "–– Input –– Would you like to compress the 'exe' directory? (y/n): " \
    choice && [[ $choice == [yY] || $choice == [yY][eE][sS] ]] &&
    {
        if command -v pbzip2 1>/dev/null 2>/dev/null; then
            tar -I pbzip2 -cf exe-"$(date -I)".tbz exe
        else
            tar -cjf exe-"$(date -I)".tbz exe
        fi
        u:info "Archive saved at exe-$(date -I).tbz"
    }
