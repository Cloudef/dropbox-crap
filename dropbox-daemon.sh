#!/bin/bash
#
# Daemon that watches folders and uploads to dropbox
#
# Depencies: inotifywait, bash

# Dropbox application keys
APP_KEY=""
APP_SECRET=""

# Full synchorization
# Remove or Upload all files locally that are removed or does not exist at remote location as well
DROPBOX_FULL_SYNC=0

# Full synchorization mode
#
# 0 = Remove files locally that does not exist at remote location
# 1 = Upload local files that does not exist at remote location
DROPBOX_FULL_SYNC_MODE=0

# Root Dropbox folder, create your remote dropbox folders here locally.
# And everything inside of them gets uploaded.
DROPBOX_ROOT="$HOME/dropbox-crap"

# Dropbox library
DROPBOX_LIBRARY="./dropbox.sh"

# Lock file
LOCK_FILE="/tmp/dropbox_lock"

# Bin Deps
BIN_DEPS="inotifywait bash"

# Error
error()
{
   echo -e "$@"
   test -z "`jobs -p`" || kill -9 `jobs -p`
   exit 1
}

# Warning
warning()
{
   echo -e "$@"
}

# Check depencies
check_deps()
{
   for i in $BIN_DEPS; do
      which $i > /dev/null
      if [ $? -ne 0 ]; then
         echo -e "Error: You don't have following depencies installed: $i"
         exit 1
      fi
   done

   [[ -f "$DROPBOX_LIBRARY" ]] || error "No dropbox library file was found"
   source "$DROPBOX_LIBRARY"
}

# Init
init()
{
   # Check depencies
   check_deps

   # Trim trailing slash
   DROPBOX_ROOT="${DROPBOX_ROOT%/}"
   DROPBOX_CACHE="${DROPBOX_CACHE%/}"

   # Remove lock file
   [ ! -f "$LOCK_FILE" ] || rm "$LOCK_FILE"

   trap error INT
}

# Upload to server
upload()
{
   local FILE="$2"
   [ -f "$2" ] || return

   if [[ "$FILE" ]] && [[ "$FILE" != "$DROPBOX_ROOT" ]]
   then
      FILE="${FILE#$DROPBOX_ROOT}"
   else
      FILE=""
   fi

   dropbox_upload "$FILE" "$2"
   notify-send "Uploaded: $FILE"
}

# Create directory
createdir()
{
   local FILE="$2"
   [ -d "$2" ] || return

   if [[ "$FILE" ]] && [[ "$FILE" != "$DROPBOX_ROOT" ]]
   then
      FILE="${FILE#$DROPBOX_ROOT}"
   else
      FILE=""
   fi

   dropbox_mkdir "$FILE" "$2"
}

# Delete from server
delete()
{
   local FILE="$2"
   if [[ "$FILE" ]] && [[ "$FILE" != "$DROPBOX_ROOT" ]]
   then
      FILE="${FILE#$DROPBOX_ROOT}"
   else
      FILE=""
   fi

   dropbox_delete "$FILE"
   notify-send "Deleted: $FILE"
}

# Handle inotify message
handle()
{
   REMOTE_FOLDER=${1#${DROPBOX_ROOT}}
   case "$2" in
      "CREATE") upload "$REMOTE_FOLDER" "$3";;
      "DELETE") delete "$REMOTE_FOLDER" "$3";;
      "MODIFY") upload "$REMOTE_FOLDER" "$3";;

      "CREATE,ISDIR") createdir "$REMOTE_FOLDER" "$3";;
      "DELETE,ISDIR") delete    "$REMOTE_FOLDER" "$3";;
   esac
}

# Parse inotify message
parse()
{
   FOLDER=""
   ACTION=""
   FILE=""
   for arg in $@
   do
      if [[ "$arg" != */ ]]; then
         FOLDER="${FOLDER}${arg} "
         shift 1
      else
         FOLDER="${FOLDER}${arg}"
         shift 1
         break
      fi
   done

   ACTION="$1"
   shift 1
   FILE="$@"

   # VIM creates this temporary file on edit, ignore it
   if [[ "$FILE" == "4913" ]]; then
      return;
   fi

   echo "FOLDER: $FOLDER"
   echo "ACTION: $ACTION"
   echo "FILE:   $FILE"
   echo "---------------"

   # Wait for sync
   while [ -f "$LOCK_FILE" ]
   do
      sleep 5s
   done

   handle "$FOLDER" "$ACTION" "${FOLDER}${FILE}"
}

# Check changes in dropbox folder
check()
{
   inotifywait -rm -e create,modify,delete "$DROPBOX_ROOT" | while read FILE
   do
      parse $FILE &
   done
}

# Sync helper
sync_handle()
{
   if [[ $DROPBOX_FULL_SYNC_MODE -eq 0 ]]
   then
      rm -r "$2"
   else
      upload "$1" "$2"
   fi
}

# Sync dropbox
sync_folders()
{
   [[ "$1" ]] || error "No root folder given"

   local DIR="$1"
   if [[ "$DIR" ]] && [[ "$DIR" != "$DROPBOX_ROOT" ]]
   then
      DIR="${DIR#$DROPBOX_ROOT}"
   else
      DIR=""
   fi

   # Get metadata of directory
   dropbox_get_metadata "$DIR"

   mkdir -p "$1"
   local CONTENTS=("${DROPBOX_CONTENTS[@]}")
   local ISDIR=("${DROPBOX_ISDIR[@]}")
   local i=0

   eval set -- ${CONTENTS[@]}
   for FILE in "$@"
   do
      echo "$FILE"
      if [[ "${ISDIR[$i]}" != "true" ]]
      then
         if [ ! -f "$DROPBOX_ROOT$FILE" ]
         then
            dropbox_download "$FILE" "$DROPBOX_ROOT$FILE"
         else
            local SIZE="$(stat -c "%s" "$DROPBOX_ROOT$FILE")"
            if [[ "$SIZE" != "${DROPBOX_BYTES[$i]}" ]]
            then
               dropbox_download "$FILE" "$DROPBOX_ROOT$FILE" "$SIZE"
            fi
         fi
      else
         sync_folders "$DROPBOX_ROOT$FILE"
      fi
      (( i=i+1 ))
   done

   [[ $DROPBOX_FULL_SYNC -eq 1 ]] || return

   # Check for removed files
   for FILE in "$DROPBOX_ROOT$DIR"/*
   do
      [[ "$FILE" != "$DROPBOX_ROOT$DIR/*" ]] || continue
      local found=0
      for MATCH in "$@"
      do
         if [[ "$FILE" == "$DROPBOX_ROOT$MATCH" ]]
         then
            found=1
            break
         fi
      done
      [[ $found -eq 1 ]] || sync_handle "$DIR" "$FILE"
   done
}

# Init daemon
init

# Init dropbox
dropbox_init "$APP_KEY" "$APP_SECRET" 0

# Auth to dropbox
dropbox_auth

# Sync every 50 seconds
while [[ 1 ]]
do
   touch "$LOCK_FILE"
   sync_folders "$DROPBOX_ROOT"
   [ ! -f "$LOCK_FILE" ] || rm "$LOCK_FILE"
   sleep 50s
done &

# Inotify loop
check

# Exit
test -z "`jobs -p`" || kill -9 `jobs -p`
