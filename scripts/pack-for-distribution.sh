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
# The following script creates a self-extracting shell script, which installs a 
# binary,creates a systemd unit file, and registers a systemd service in the user
# slice.

DATE=`date`

SCRIPT_BINARY=$1

if [ ! -f "$SCRIPT_BINARY" ]; then
  echo "Executable $SCRIPT_BINARY not found!"
  exit 1
fi

SCRIPT_BINARY_NAME=$(basename "SCRIPT_BINARY")
SCRIPT_BINARY_AND_BUILD="$(basename "`dirname "$SCRIPT_BINARY"`")/$(basename "$SCRIPT_BINARY")"
SCRIPT_NAME="miedl-meter"
SCRIPT_PERIOD=30000

echo -e "Creating the script for binary $SCRIPT_BINARY_AND_BUILD."

SCRIPT_READELF=$(readelf -d "$SCRIPT_BINARY")
SCRIPT_LINKING=""
SCRIPT_RPATH=0

echo "$SCRIPT_READELF" | grep -E '(libc\+\+|libstdc\+\+)' 2>/dev/null 1>/dev/null
if [ $? -eq 1 ]; then
  echo -e "Binary has statically linked standard libraries."
  SCRIPT_LINKING="${SCRIPT_LINKING}with statically linked libraries,"
fi

echo "$SCRIPT_READELF"  | grep 'RPATH' 2>/dev/null 1>/dev/null
if [ $? -eq 0 ]; then
  SCRIPT_RPATH=1
  echo -e "Binary has a runtime shared library search path."
  if [ ! -z "$SCRIPT_LINKING" ]; then
    SCRIPT_LINKING="${SCRIPT_LINKING} and "
  fi
  SCRIPT_LINKING="${SCRIPT_LINKING}with runtime shared library search path,"
fi

SCRIPT_COMMENT="This script was created on $DATE using a source binary $SCRIPT_BINARY_AND_BUILD, $SCRIPT_LINKING"

pushd "$PWD" 1>/dev/null 2>/dev/null
cd "$(dirname "$SCRIPT_BINARY")" 2>/dev/null

SCRIPT_GIT_COMMIT=$(git rev-parse --short HEAD)
if [ ! $? -eq 0 ]; then
  # not a git repo
  SCRIPT_COMMENT="$SCRIPT_COMMENT from an out-of-source location."
else
  SCRIPT_GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  SCRIPT_GIT_UNCOMMITED=""
  git status -s | grep -e '^\s*M' 2>/dev/null 1>/dev/null
  if [ $? -eq 0 ]; then
    SCRIPT_GIT_UNCOMMITED=", with uncommited changes in `git status -s | grep -e '^\s*M' 2>/dev/null | wc -l` files"
  fi
  SCRIPT_COMMENT="$SCRIPT_COMMENT from git branch $SCRIPT_GIT_BRANCH on commit with hash $SCRIPT_GIT_COMMIT${SCRIPT_GIT_UNCOMMITED}."
fi

popd 1>/dev/null 2>/dev/null

echo -e "Creating the script for $SCRIPT_BINARY"

SCRIPT_CHECKSUM=$(sha1sum "$SCRIPT_BINARY" | cut -d ' ' -f 1)

echo -e "Executable checksum: $SCRIPT_CHECKSUM"

ALL_BUNDLED=""

if [[ $SCRIPT_RPATH -eq 1 ]]; then
  read -p "Would you like to bundle all shared libraries? (y/n): " choice \
    && [[ $choice == [yY] || $choice == [yY][eE][sS] ]] \
    && GREP_STRING='(libc|libstdc|libgcc|librt|libm|libpthread)' \
    && ALL_BUNDLED=".all" \
    || GREP_STRING='(libc\+\+|libstdc\+\+)'
fi

SCRIPT_FILE_NAME="$SCRIPT_NAME.$(basename "`dirname "$SCRIPT_BINARY"`")${ALL_BUNDLED}.sh"
echo -e "Saving script in $SCRIPT_FILE_NAME"

[ -e "$SCRIPT_NAME" ] && rm -r "$SCRIPT_NAME"
mkdir "$SCRIPT_NAME"
cp "$SCRIPT_BINARY" "$SCRIPT_NAME/$SCRIPT_NAME"

if [ $SCRIPT_RPATH -eq 1 ]; then
  echo -ne "Bundling shared libraries... "
  LIBRARIES=$(ldd "$SCRIPT_BINARY" | grep -E "$GREP_STRING" | cut -d ' ' -f 3)

  for LIBRARY in $LIBRARIES; do
    echo -n "$(basename $LIBRARY) "
    cp -L "$LIBRARY" "$SCRIPT_NAME"
  done
  echo ""
fi

echo -e "Creating the archive..."
SCRIPT_ARCHIVE="$SCRIPT_NAME".tar.bz2
tar -cjf $SCRIPT_ARCHIVE $SCRIPT_NAME
rm -r "$SCRIPT_NAME"

SCRIPT_CHECKSUM_ARCHIVE=$(sha1sum "$SCRIPT_ARCHIVE" | cut -d ' ' -f 1)
echo -e "Archive checksum: $SCRIPT_CHECKSUM_ARCHIVE"

SCRIPT_COMMENT=$(echo "$SCRIPT_COMMENT" | fold -w 70 -s | awk '{print "# " $0}')

cat << __END_OF_SCRIPT__ > "$SCRIPT_FILE_NAME"
#!/usr/bin/env bash
$SCRIPT_COMMENT

NAME="$SCRIPT_NAME"

EXTRACT=0
INSTALL=0
UNINSTALL=0
BACKUP=0
SYSTEMD=0

FRSET="\e[0m"
FBOLD="\e[1m"
FUNDR="\e[4m"

command -v base64 1>/dev/null 2>/dev/null  || { echo "This script requires base64, which was not found."; exit 1; }
command -v sha1sum 1>/dev/null 2>/dev/null || { echo "This script requires sha1sum, which was not found."; exit 1; }

pidof systemd 1>/dev/null 2>/dev/null && SYSTEMD=1 || SYSTEMD=0

echo -e "This script contains a utilisation/frequency meter to support \${FBOLD}Philipp Miedl's\${FRSET} ongoing research. The script will install a systemd unit file under the user slice, which will run the meter every time the user logs in." | fold -w 70 -s

if [ \$SYSTEMD -eq 0 ]; then
  echo -e ""
  echo -e "Unfortunately, it seems that your system does not use systemd as the init system. This script is only compatible with systemd-based OSes. Aborting. " | fold -w 70 -s
  exit 1
fi

echo -e ""
echo -e "To \${FBOLD}monitor\${FRSET} the status of the service, run:"
echo -e "    \${FUNDR}systemctl status --user \$NAME\${FRSET}"
echo -e "To \${FBOLD}start\${FRSET} or \${FBOLD}stop\${FRSET} the service, run:"
echo -e "    \${FUNDR}systemctl {start,stop} --user \$NAME\${FRSET}"
echo -e "To \${FBOLD}disable\${FRSET} the service, run:"
echo -e "    \${FUNDR}systemctl disable --user \$NAME\${FRSET}"
echo -e ""
echo -e "Alternatively, use this script and select the \${FBOLD}Uninstall\${FRSET} option below. To simply extract the unit file and binary, choose the \${FBOLD}Extract\${FRSET} option." | fold -w 70 -s
echo -e ""
echo -e "Logs can be uploaded to:\nhttps://polybox.ethz.ch/index.php/s/0KEjpMMWKpRF7kn."
echo -e ""
echo -e "What would you like to do?"

select choice in "Install" "Uninstall" "Extract" "Abort" "Backup logs"; do
    case \$choice in
        "Abort" ) exit 1;;
        "Install" ) INSTALL=1; break;;
        "Uninstall" ) UNINSTALL=1; break;;
        "Extract" ) EXTRACT=1; break;;
        "Backup logs" ) BACKUP=1; break;;
        * ) echo -e "Unknown option";;
    esac
done

echo ""

INSTALL="\$HOME/.local/bin"
LOG="\$HOME/.local/share/miedl-meter"
SYSTEMD="\$HOME/.config/systemd/user"

BINARY_FOLDER="\$INSTALL/\$NAME"
BINARY="\$BINARY_FOLDER/\$NAME"
SERVICE_NAME="\$NAME.service"
SERVICE="\$SYSTEMD/\$SERVICE_NAME"

if [ \$BACKUP -eq 1 ]; then

  FILES=\$(ls -1 \$LOG/**.{csv,txt})

  echo -e "The following files will be packed:"
  echo -e ""
  ls \$LOG
  echo -e ""

  BACKUP_ARCHIVE="miedl-meter_\${USER}_\$(date '+%Y-%m-%d_%H-%M').tar.bz2"

  tar -cjSf \$BACKUP_ARCHIVE --strip-components=3 -C \$LOG . 2>/dev/null 1>/dev/null

  read -p "Would you like to delete the original logs? (y/n): " choice \\
    && [[ \$choice == [yY] || \$choice == [yY][eE][sS] ]] && rm \$FILES

  read -p "Would you like to send the archive to the log server? (y/n): " choice \\
    && [[ \$choice == [yY] || \$choice == [yY][eE][sS] ]] && SEND=1 || SEND=0

  if [ \$SEND -eq 1 ]; then
    read -p "Enter your log server username: " USERNAME
    read -p "Enter the destination folder: " DESTINATION

    scp -P 22 "\$BACKUP_ARCHIVE" \$USERNAME@pc-10145.ethz.ch:\$DESTINATION
  fi

  exit 0
fi

if [ \$UNINSTALL -eq 1 ]; then

  if [ -f \$SERVICE ]; then
    systemctl stop --user \$SERVICE_NAME
    RS_STOP=\$?
    systemctl kill --user \$SERVICE_NAME
    RS_KILL=\$?
    systemctl disable --user \$SERVICE_NAME
    RS_DISABLE=\$?

    RS=\$((RS_STOP+RS_KILL+RS_DISABLE))

    if [ ! \$RS -eq 0 ]; then
      echo -e "One of the cleanup procedures might have returned a non-zero status."
    fi

    rm \$SERVICE
    if [ \$? -eq 0 ]; then
      echo -e "Removed the service file from \$SERVICE"
    fi
  fi

  if [ -f \$BINARY_FOLDER ]; then
    rm -r \$BINARY_FOLDER
    echo -e "Removed the binary folder from \$BINARY_FOLDER"
  fi

  read -p "Would you also like to delete the log folder? (y/n): " choice \\
    && [[ \$choice == [yY] || \$choice == [yY][eE][sS] ]] && rm -r \$LOG 

  exit 0
fi

if [ \$EXTRACT -eq 0 ]; then

  echo -e "The \${FUNDR}binary\${FRSET} will be installed to \${FBOLD}\$INSTALL\${FRSET}"
  mkdir -p "\$INSTALL"

  echo -e "The \${FUNDR}log files\${FRSET} will be stored in \${FBOLD}\$LOG\${FRSET}"
  mkdir -p "\$LOG"

  echo -e "The \${FUNDR}unit file\${FRSET} will be stored in \${FBOLD}\$SYSTEMD\${FRSET}"
  mkdir -p "\$SYSTEMD"

  echo ""

  if [ -f \$SERVICE ]; then
    systemctl stop --user \$SERVICE_NAME
    systemctl disable --user \$SERVICE_NAME
    rm \$SERVICE
  fi

else

  SERVICE="./\$SERVICE_NAME"
  BINARY_FOLDER="./\$NAME"
  BINARY="\$BINARY_FOLDER/\$NAME"

fi

read -p "Would you like to increase logging verbosity? (y/n): " choice \\
  && [[ \$choice == [yY] || \$choice == [yY][eE][sS] ]] && VERBOSITY="--loglevel debug" || VERBOSITY=""

echo -e "Extracting the unit file to \$SERVICE"

# Enabled options:
#   --timestamp  append timestamp to app log filenames
#   --rotate     create up to 10 log files of max 160 MiB
#   -l           app log file
#   -dl          debug log file
#   --period     sampling period, 30 ms
#   --asap       start logging without waiting for a signal

# systemd unit file
#   - the binary will be called after every boot and resume event
#   - the log file will contain the user name and host name
cat << __EOF__ > "\$SERVICE"
[Unit]
Description=utilisation and frequency meter [TIK]
After=default.target

[Service]
Type=simple
ExecStartPre=/usr/bin/env bash -c 'if [ \$((\$(du -b \$LOG | cut -f 1) > 20000000000)) -eq 0 ]; then exit 0; else echo "Logs directory exceeds 20GB! Consider backing up the logs."; exit 1; fi'
ExecStartPre=/usr/bin/env bash -c 'echo "Current log folder size: \$(echo \$(du -h \$LOG | cut -f 1))iB."; exit 0;'
ExecStart=\$BINARY \$VERBOSITY --timestamp --append_governor -l \$LOG/log_%u_%H.csv -dl \$LOG/debug_%u_%H.txt --period $SCRIPT_PERIOD --asap
ExecStopPost=/usr/bin/env bash -c "echo \"\$NAME stopped, created log file \$(ls -lh \$LOG | tail -n 1 | cut -d ' ' -f 6,10 | awk '{print(\$2 ", " \$1 "iB in size")}').\""
KillMode=process
KillSignal=SIGINT
TimeoutStopSec=5
Restart=always

[Install]
WantedBy=default.target
__EOF__

chmod 644 "\$SERVICE"

CHECKSUM="$SCRIPT_CHECKSUM"
CHECKSUM_ARCHIVE="$SCRIPT_CHECKSUM_ARCHIVE"

ARCHIVE="\$NAME.tar.bz2"

echo -e "Extracting the archive to \$ARCHIVE"

base64 --decode << __ARCHIVE__ > \$ARCHIVE
__END_OF_SCRIPT__

base64 "$SCRIPT_ARCHIVE" >> "$SCRIPT_FILE_NAME"
rm "$SCRIPT_ARCHIVE"

cat << __END_OF_SCRIPT__ >> "$SCRIPT_FILE_NAME"
__ARCHIVE__

echo -ne "Vecifying archive checksum... "
echo "\$CHECKSUM_ARCHIVE  \$ARCHIVE" | sha1sum -c -

if [ ! \$? -eq 0 ]; then
  echo "\${FBOLD}Checksum check failed!\${FRSET}"
  exit 1
fi

echo -e "Extracting archive... "

tar -xjf \$ARCHIVE -C \$(dirname "\$BINARY_FOLDER")
[ ! \$? -eq 0 ] && echo "\${FBOLD}Extracting failed!\${FRSET}" && exit 1 || echo -e "Extacted the archive to \$BINARY_FOLDER"

echo -ne "Verifying binary checksum... "
echo "\$CHECKSUM  \$BINARY" | sha1sum -c -

if [ ! \$? -eq 0 ]; then
  echo "\${FBOLD}Checksum check failed!\${FRSET}"
  exit 1
fi

chmod 755 "\$BINARY"

if [ \$EXTRACT -eq 1 ]; then
  exit
else
  rm \$ARCHIVE
fi

echo -ne "Enabling the service... "

systemctl enable --user \$SERVICE_NAME 2>/dev/null 1>/dev/null
systemctl daemon-reload --user 2>/dev/null 1>/dev/null
systemctl start --user \$SERVICE_NAME 2>/dev/null 1>/dev/null

sleep 1

systemctl list-units --state=failed | grep \$NAME 1>/dev/null 2>/dev/null

if [ \$? -eq 1 ]; then
  echo -e "\${FBOLD}success!\${FRSET}"
  systemctl status --user --no-pager -l \$SERVICE_NAME
else
  echo -e "\${FBOLD}failed!\${FRSET}"
  systemctl list-units --no-pager --state failed
fi

__END_OF_SCRIPT__

echo -e "Finished"
