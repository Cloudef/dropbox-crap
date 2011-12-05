#!/bin/bash
#
# Dropbox library
#

# Dropbox API
DROPBOX_API="https://api.dropbox.com/1"
DROPBOX_CONTENT_API="https://api-content.dropbox.com/1"
DROPBOX_LOGIN_URL="https://www.dropbox.com/login"

# For automatic authentication
DROPBOX_EMAIL=""
DROPBOX_PASSWD=""

# Dropbox key
DROPBOX_APP_KEY=""
DROPBOX_APP_SECRET=""
DROPBOX_AUTOAUTH=0

# OAuth.sh path
OAUTH_LIBRARY="./OAuth.sh"

# Depencies
DROPBOX_BIN_DEPS="curl jsawk bash sed perl"

# OAuth stuff
OAUTH_VER="1.0"
OAUTH_METHOD="HMAC-SHA1"
OAUTH_TOKEN=""
OAUTH_SECRET=""
OAUTH_UID=""

# Account array
# Default fields, which gets replaced on dropbox_get_account_info
DROPBOX_ACCOUNT=(
   "referral_link"
   "display_name"
   "uid"
   "country"
   "email"
   "shared"
   "quota"
   "normal"
)

# Metadata array
# Default fields, which gets replaced on dropbox_get_metadata
DROPBOX_METADATA=(
   "hash"
   "bytes"
   "path"
   "is_dir"
   "size (human readable)"
   "root"
   "contents"
   "revision"
)

# Dropbox contents array
DROPBOX_CONTENTS=(
)

# Dropbox is_dir array for contents
DROPBOX_ISDIR=(
)

# Dropbox bytes array for contents
DROPBOX_BYTES=(
)

# Dropbox revision array for contents
DROPBOX_REVISION=(
)

#
# COMMON FUNCTIONS ==========>
#

# Error
_dropbox_error()
{
   echo -e "$@"
   exit 1
}

# Warning
_dropbox_warning()
{
   echo -e "$@"
}

# Check depencies
_dropbox_check_deps()
{
   for i in $DROPBOX_BIN_DEPS; do
      which $i > /dev/null
      if [ $? -ne 0 ]; then
         _dropbox_error "Error: You don't have following depencies installed: $i"
      fi
   done

   [[ -f "$OAUTH_LIBRARY" ]] || _dropbox_error "No OAuth.sh found!"
   source "$OAUTH_LIBRARY"
}

_dropbox_check_auth()
{
   [[ "$OAUTH_TOKEN"  ]] || _dropbox_error "No OAUTH_TOKEN, forgot dropbox_auth?"
   [[ "$OAUTH_SECRET" ]] || _dropbox_error "No OAUTH_SECRET, forgot dropbox_auth?"
}

_dropbox_auto_auth()
{
   local RET=""

   _dropbox_error "Auto authentication not working yet."

   RET="$(curl -sL "$1")"
   RET=$(echo "$RET" | tr -d '\n' | sed 's/.*<form action="\/login"[^>]*>\s*<input type="hidden" name="t" value="\([a-z 0-9]*\)".*/\1/')
   [[ "$RET" ]] || _dropbox_error "Failed to get Authentication token!"

   curl -s -i --data-urlencode -c "cookie.txt" -d "login_email=$DROPBOX_EMAIL&login_password=$DROPBOX_PASSWD&t=$RET&login_submit=1" "$DROPBOX_LOGIN_URL?cont=$1" > /dev/null
   curl -s -i -b "cookie.txt" -d "login_email=$DROPBOX_EMAIL&login_password=$DROPBOX_PASSWD&t=$RET&login_submit=1" "$1" > /dev/null
   [[ $? == 0 ]] || _dropbox_error "Automatic authentication failed"
}

# Split the metadata contents to array
# Returns in DROPBOX_CONTENTS
_DROPBOX_SPLIT=""
_dropbox_split()
{
   local CONTENTS=("")
   local SPLIT="$1"
   shift 1

   if [[ "$@" == "[]" ]]
   then
      echo "${CONTENTS[@]}"
      return
   fi

   OIFS="$IFS"
   IFS="$SPLIT"
   CONTENTS=($@)
   IFS=$OIFS

   _DROPBOX_SPLIT=("${CONTENTS[@]}")
}

#
# OAUTH HELPERS ==========>
#

# Extract OAuth variables
oauth_ext () {
   # $1 key name
   # $2 string to find
   egrep -o "$1=[a-zA-Z0-9-]*" <<< "$2" | cut -d\= -f 2
}

# Form OAuth header for token request
oauth_auth()
{
   local AUTH_HEADER="$(_OAuth_authorization_header 'Authorization' "$DROPBOX_API" "$DROPBOX_APP_KEY" "$DROPBOX_APP_SECRET" '' '' \
         "$OAUTH_METHOD" "$OAUTH_VER" "$(OAuth_nonce)" "$(OAuth_timestamp)" 'POST' "${DROPBOX_API}/oauth/request_token" \
         "$(OAuth_param 'oauth_callback' 'oob')"), $(OAuth_param_quote 'oauth_callback' 'oob')"

   echo "$AUTH_HEADER"
}

# Form OAuth header for token access
oauth_token()
{
   [[ "$OAUTH_TOKEN" ]]  || _dropbox_error "OAUTH_TOKEN  == EMPTY"
   [[ "$OAUTH_SECRET" ]] || _dropbox_error "OAUTH_SECRET == EMPTY"

   local AUTH_HEADER="$(_OAuth_authorization_header 'Authorization' "$DROPBOX_API" "$DROPBOX_APP_KEY" "$DROPBOX_APP_SECRET" \
         "$OAUTH_TOKEN" "$OAUTH_SECRET" "$OAUTH_METHOD" "$OAUTH_VER" "$(OAuth_nonce)" "$(OAuth_timestamp)" \
         'POST' "${DROPBOX_API}/oauth/access_token")"

   echo "$AUTH_HEADER"
}

# Dropbox API header
dropbox_header()
{
   [[ "$1" ]] || _dropbox_error "Specify API command."

   local cmd="$2"
   local method="$1"
   shift 2

   local oauth_consumer_key="$DROPBOX_APP_KEY"
   local oauth_consumer_secret="$DROPBOX_APP_SECRET"
   local oauth_token="$OAUTH_TOKEN"
   local oauth_token_secret="$OAUTH_SECRET"
   local oauth_signature_method="$OAUTH_METHOD"
   local oauth_version="$OAUTH_VER"

   local params=()
   while (( $# > 0 )); do
      params[${#params[@]}]="$1"
      shift 1
   done

   local AUTH_HEADER="$(OAuth_authorization_header 'Authorization' "$DROPBOX_API" '' '' "$method" "${DROPBOX_API}${cmd}" ${params[@]})"
   echo "$AUTH_HEADER"
}

# Dropbox content API header
dropbox_content_header()
{
   [[ "$1" ]] || _dropbox_error "Specify Method"
   [[ "$2" ]] || _dropbox_error "Specify API Command"

   local cmd="$2"
   local method="$1"
   shift 2

   local oauth_consumer_key="$DROPBOX_APP_KEY"
   local oauth_consumer_secret="$DROPBOX_APP_SECRET"
   local oauth_token="$OAUTH_TOKEN"
   local oauth_token_secret="$OAUTH_SECRET"
   local oauth_signature_method="$OAUTH_METHOD"
   local oauth_version="$OAUTH_VER"

   local params=()
   while (( $# > 0 )); do
      params[${#params[@]}]="$1"
      shift 1
   done

   local AUTH_HEADER="$(OAuth_authorization_header 'Authorization' "$DROPBOX_CONTENT_API" '' '' "$method" "${DROPBOX_CONTENT_API}${cmd}" ${params[@]})"
   echo "$AUTH_HEADER"
}

#
# DROPBOX BASH API ==========>
#

# Initialize
# Initialize the Dropbox BASH API
dropbox_init()
{
   [[ "$1" ]] || _dropbox_error "No application key was given."
   [[ "$2" ]] || _dropbox_error "No secret key was given."
   _dropbox_check_deps

   DROPBOX_APP_KEY="$1"
   DROPBOX_APP_SECRET="$2"
   DROPBOX_AUTOAUTH="$3"
}

# Authentication
# Auths you to the dropbox services. This should be ran after dropbox_init.
dropbox_auth()
{
   [[ "$DROPBOX_APP_KEY" ]]    || _dropbox_error "No application key, forgot dropbox_init?"
   [[ "$DROPBOX_APP_SECRET" ]] || _dropbox_error "No secret key, forgot dropbox_init?"

   local RET=""
   RET="$(curl -s -d '' -H "$(oauth_auth)" "${DROPBOX_API}/oauth/request_token")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_error "$RET"

   OAUTH_TOKEN="$(oauth_ext 'oauth_token' "$RET")"
   OAUTH_SECRET="$(oauth_ext 'oauth_token_secret' "$RET")"

   if [[ "$DROPBOX_AUTOAUTH" == "1" ]]; then
      _dropbox_auto_auth "https://www.dropbox.com/1/oauth/authorize?$RET"

      # curl -sL "http://www.dropbox.com/1/oauth/authorize?$RET"
      # [[ $? == 0 ]] || _dropbox_error "Automatic authentication failed"
   else
      echo "Go to following url and authorize the application." 1>&2
      echo "https://www.dropbox.com/1/oauth/authorize?$RET" 1>&2
      echo ""
      read -p "Press a key when ready. "
   fi

   RET="$(curl -s -d '' -H "$(oauth_token)" "${DROPBOX_API}/oauth/access_token")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_error "$RET"

   OAUTH_TOKEN="$(oauth_ext 'oauth_token' "$RET")"
   OAUTH_SECRET="$(oauth_ext 'oauth_token_secret' "$RET")"
   OAUTH_UID="$(oauth_ext 'uid' "$RET")"
}

# Get account information
# Account information is stored in DROPBOX_ACCOUNT array.
dropbox_get_account_info()
{
   _dropbox_check_auth

   local RET="$(curl -s -d '' -H "$(dropbox_header 'POST' '/account/info')" "${DROPBOX_API}/account/info")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_warning "$RET"

   DROPBOX_ACCOUNT=(
      "$(echo "$RET" | jsawk 'return this.referral_link')"
      "$(echo "$RET" | jsawk 'return this.display_name')"
      "$(echo "$RET" | jsawk 'return this.uid')"
      "$(echo "$RET" | jsawk 'return this.coutnry')"
      "$(echo "$RET" | jsawk 'return this.email')"
      "$(echo "$RET" | jsawk 'return this.quota_info.shared')"
      "$(echo "$RET" | jsawk 'return this.quota_info.quota')"
      "$(echo "$RET" | jsawk 'return this.quota_info_normal')"
   )
}

# Get metadata
# Returns file/directory information
#
# $1 = Path to file/directory. NOTE: All dropbox paths start with / (eg. /folder)
# Due to limitations in bash, you need some parsing in contents. The files are seperated by colon (,)
dropbox_get_metadata()
{
   _dropbox_check_auth

   local HASH=""
   local ENCODED="$(OAuth_PE "$1" | sed -e 's/%2F/\//g')"

   [[ ! "$2" ]] || HASH="hash=$2"
   local RET="$(curl -s -d "" -H "$(dropbox_header 'POST' "/metadata/dropbox$ENCODED" "$HASH")" "${DROPBOX_API}/metadata/dropbox$ENCODED")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_warning "$RET"

   DROPBOX_METADATA=(
         "$(echo "$RET" | jsawk 'return this.hash')"
         "$(echo "$RET" | jsawk 'return this.bytes')"
         "$(echo "$RET" | jsawk 'return this.path')"
         "$(echo "$RET" | jsawk 'return this.is_dir')"
         "$(echo "$RET" | jsawk 'return this.size')"
         "$(echo "$RET" | jsawk 'return this.root')"
         "$(echo "$RET" | jsawk 'return this.revision')"
   )

   DROPBOX_CONTENTS=($(echo "$RET" | jsawk 'return this.contents' | jsawk 'return this.path' | sed -e 's/\[\"/"/' -e 's/\"\]/"/' -e 's/","/" "/g'))
   [[ "${DROPBOX_CONTENTS[@]}" != "[]" ]] || DROPBOX_CONTENTS=""
   # DROPBOX_CONTENTS=("${_DROPBOX_SPLIT[@]}")

   DROPBOX_ISDIR=($(echo "$RET" | jsawk 'return this.contents' | jsawk 'return this.is_dir' | sed -e 's/\[//' -e 's/\]//' -e 's/,/ /g'))
   # DROPBOX_ISDIR=("${_DROPBOX_SPLIT[@]}")

   DROPBOX_BYTES=($(echo "$RET" | jsawk 'return this.contents' | jsawk 'return this.bytes' | sed -e 's/\[//' -e 's/\]//' -e 's/,/ /g'))

   DROPBOX_REVISION=($(echo "$RET" | jsawk 'return this.contents' | jsawk 'return this.revision' | sed -e 's/\[//' -e 's/\]//' -e 's/,/ /g'))
}

# Download file
# $1 = Remote path
# $2 = Local path
# $3 = Bytes, optional, used to check that the download was correct
dropbox_download()
{
   _dropbox_check_auth

   local ENCODED="$(OAuth_PE "$1")"
   echo "${DROPBOX_CONTENT_API}/files/dropbox$ENCODED"
   [[ ! -f "$2" ]] || rm "$2"

   curl -s -H "$(dropbox_content_header 'POST' "/files/dropbox$ENCODED")" "${DROPBOX_CONTENT_API}/files/dropbox$ENCODED" -o "$2"
   [[ "$3" ]] || return

   local SIZE="$(stat -c "%s" "$2")"
   [[ "$3" != "$SIZE" ]] || return

   rm "$2"
   _dropbox_warning "Failed to download: $2"
}

# Upload file
# $1 = Remote path
# $2 = Local path
dropbox_upload()
{
   _dropbox_check_auth

   local ENCODED="$(OAuth_PE "$1" | sed -e 's/%2F/\//g' -e 's/~/%7E/g')"
   echo "${DROPBOX_CONTENT_API}/files_put/dropbox$ENCODED"

   local RET="$(curl -s -d '' -H "$(dropbox_content_header 'PUT' "/files_put/dropbox$ENCODED")" -T "$2" "${DROPBOX_CONTENT_API}/files_put/dropbox$ENCODED")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_warning "$RET"
}

# Delete file
# $1 = Remote path
dropbox_delete()
{
   _dropbox_check_auth

   local ENCODED="$(OAuth_PE "$1")"
   local PARAM=(
                $(OAuth_param 'root' 'dropbox')
                $(OAuth_param 'path' "$1")
                )

   local RET="$(curl -s -d '' -H "$(dropbox_header 'POST' "/fileops/delete" ${PARAM[@]})" "${DROPBOX_API}/fileops/delete?root=dropbox&path=$ENCODED")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_warning "$RET"
}

# Create folder
# $1 = Remote path
dropbox_mkdir()
{
   _dropbox_check_auth

   local ENCODED="$(OAuth_PE "$1")"
   local PARAM=(
                $(OAuth_param 'root' 'dropbox')
                $(OAuth_param 'path' "$1")
                )

   local RET="$(curl -s -d '' -H "$(dropbox_header 'POST' "/fileops/create_folder" ${PARAM[@]})" "${DROPBOX_API}/fileops/create_folder?root=dropbox&path=$ENCODED")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_warning "$RET"
}

# Move file
# $1 = From remote path
# $2 = To remote path
dropbox_move()
{
   _dropbox_check_auth

   local ENCODED1="$(OAuth_PE "$1")"
   local ENCODED2="$(OAuth_PE "$2")"
   local PARAM=(
                $(OAuth_param 'root'      'dropbox')
                $(OAuth_param 'from_path' "$1")
                $(OAuth_param 'to_path'   "$2")
                )

   local RET="$(curl -s -d '' -H "$(dropbox_header 'POST' "/fileops/move" ${PARAM[@]})" "${DROPBOX_API}/fileops/move?root=dropbox&from_path=$ENCODED1&to_path=$ENCODED2")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_warning "$RET"
}

# Copy file
# $1 = From remote path
# $2 = To remote path
dropbox_copy()
{
   _dropbox_check_auth

   local ENCODED1="$(OAuth_PE "$1")"
   local ENCODED2="$(OAuth_PE "$2")"
   local PARAM=(
                $(OAuth_param 'root'      'dropbox')
                $(OAuth_param 'from_path' "$1")
                $(OAuth_param 'to_path'   "$2")
                )

   local RET="$(curl -s -d '' -H "$(dropbox_header 'POST' "/fileops/move" ${PARAM[@]})" "${DROPBOX_API}/fileops/move?root=dropbox&from_path=$ENCODED1&to_path=$ENCODED2")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_warning "$RET"
}

# Get shareable link
# $1 = Remote path
dropbox_share()
{
   _dropbox_check_auth

   local ENCODED="$(OAuth_PE "$1")"
   local RET="$(curl -s -d '' -H "$(dropbox_header 'POST' "/shares/dropbox$ENCODED")" "${DROPBOX_API}/shares/dropbox$ENCODED")"
   [[ "$RET" != *\"error\":* ]]  || _dropbox_warning "$RET"

   echo "$RET" | jsawk 'return this.url'
}
