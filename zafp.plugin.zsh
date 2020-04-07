# shellcheck shell=ksh        # Unfortunately, shellcheck does not support zsh.
# shellcheck disable=SC2086
# shellcheck disable=SC2128

_ZAFP_CONFIG_FILE=$HOME/.zafp.zsh
_ZAFP_CONFIG_VARIABLES=('_ZAFP_HOST' '_ZAFP_PATH' '_ZAFP_USER' '_ZAFP_DEFAULT_ACCOUNT' '_ZAFP_DEFAULT_ROLE')

_ZAFP_CREDENTIAL_SYNC_FILE=$(mktemp)
_ZAFP_CREDENTIAL_SYNC_VARIABLES=('_zafp_account' '_zafp_expiration' '_zafp_credential_sync_pid' '_zafp_role')

_ZAFP_DEPENDENCIES=('curl' 'date' 'jq' 'mktemp')

# shellcheck disable=SC2016
_ZAFP_PROMPT_PREFIX='[$_zafp_account/$_zafp_role $_zafp_expiration] '

_zafp_check_dependencies() {
  emulate -L zsh
  for command in $_ZAFP_DEPENDENCIES; do
    if ! type $command >/dev/null; then
      printf "The command %s is not installed. Please install.\n" $command >&2
    fi
  done
}

_zafp_credentials_sync() {
  emulate -L zsh
  local account=$1
  local role=$2
  local password=$3

  local curl_exit_status tmp_output_file url
  curl_exit_status=0
  tmp_output_file=$(mktemp)
  url=https://$_ZAFP_HOST/$_ZAFP_PATH/$account/$role

  while true; do
    curl \
      --fail \
      --output $tmp_output_file \
      --silent \
      --user $_ZAFP_USER:$password \
      $url
    curl_exit_status=$?

    if ((curl_exit_status != 0)); then
      printf "\nCredentials sync: Could not get credentials: curl failed with exit status %s.\n" $curl_exit_status
      break
    fi

    mv $tmp_output_file $_ZAFP_CREDENTIAL_SYNC_FILE

    sleep 60
  done

  printf "Credentials sync: Stopping ...\n"
  if [[ -w $tmp_output_file ]]; then
    rm $tmp_output_file
  fi
  _zafp_reset_credential_sync_state
  printf "Credentials sync: Stopped.\n"
  return $curl_exit_status
}

_zafp_credentials_sync_is_running() {
  emulate -L zsh
  if [[ -v _zafp_credential_sync_pid ]]; then
    kill -0 $_zafp_credential_sync_pid 2>/dev/null
    return $?
  fi
  return 1
}

_zafp_get_credentials_value() {
  emulate -L zsh
  local key=$1
  jq --raw-output .$key $_ZAFP_CREDENTIAL_SYNC_FILE
}

_zafp_init_config_variables() {
  emulate -L zsh

  if [[ -r $_ZAFP_CONFIG_FILE ]]; then
    # shellcheck source=.zafp.zsh.template
    source $_ZAFP_CONFIG_FILE
  else
    printf "Cannot read configuration file %s. Please create and grant read permissions.\n" $_ZAFP_CONFIG_FILE >&2
  fi

  for config_var in $_ZAFP_CONFIG_VARIABLES; do
    if [[ ! -v "$config_var" ]]; then
      printf "The configuration variable %s is not set. Please add to %s.\n" $config_var $_ZAFP_CONFIG_FILE >&2
    fi
  done
}

_zafp_precmd() {
  emulate -L zsh
  _zafp_update_aws_variables
  _zafp_update_expiration
  _zafp_update_prompt
}

_zafp_reset_credential_sync_state() {
  emulate -L zsh
  _zafp_unset_variables $_ZAFP_CREDENTIAL_SYNC_VARIABLES
  _zafp_reset_file $_ZAFP_CREDENTIAL_SYNC_FILE
}

_zafp_reset_file() {
  emulate -L zsh
  local file=$1
  printf "" >$file
}

_zafp_unset_variables() {
  emulate -L zsh
  local vars=$1
  for var in $vars; do
    unset $var
  done
}

_zafp_update_prompt() {
  emulate -L zsh
  if _zafp_credentials_sync_is_running; then
    if [[ $PROMPT != *$_ZAFP_PROMPT_PREFIX* ]]; then
      PROMPT=$_ZAFP_PROMPT_PREFIX$PROMPT
    fi
  else
    if [[ $PROMPT == *$_ZAFP_PROMPT_PREFIX* ]]; then
      PROMPT=${PROMPT//$_ZAFP_PROMPT_PREFIX/}
    fi
  fi
}

_zafp_update_aws_variables() {
  emulate -L zsh
  if _zafp_credentials_sync_is_running; then
    AWS_ACCESS_KEY_ID=$(_zafp_get_credentials_value AccessKeyId)
    export AWS_ACCESS_KEY_ID

    AWS_SECRET_ACCESS_KEY=$(_zafp_get_credentials_value SecretAccessKey)
    export AWS_SECRET_ACCESS_KEY

    AWS_SESSION_TOKEN=$(_zafp_get_credentials_value Token)
    export AWS_SESSION_TOKEN

    AWS_SECURITY_TOKEN=$(_zafp_get_credentials_value Token)
    export AWS_SECURITY_TOKEN
  else
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
  fi
}

_zafp_update_expiration() {
  emulate -L zsh
  if _zafp_credentials_sync_is_running; then
    local date_ expire_at expire_at_iso expire_in_mins expire_in_secs expire_in_statement now

    if type gdate >/dev/null; then
      date_=gdate
    else
      date_="date"
    fi

    now=$($date_ +%s)
    expire_at_iso=$(_zafp_get_credentials_value Expiration)
    expire_at=$($date_ +%s -d $expire_at_iso)
    ((expire_in_secs = expire_at - now))
    ((expire_in_mins = expire_in_secs / 60))
    expire_in_statement=${expire_in_mins}min

    # shellcheck disable=SC2034
    _zafp_expiration=$expire_in_statement
  else
    unset _zafp_expiration
  fi
}

_zapf_zshexit() {
  emulate -L zsh
  rm $_ZAFP_CREDENTIAL_SYNC_FILE
}

unzafp() {
  emulate -L zsh

  if ! _zafp_credentials_sync_is_running; then
    printf "zafp is not running. Use zafp to start it.\n"
    return 1
  fi

  kill $_zafp_credential_sync_pid
  wait $_zafp_credential_sync_pid

  _zafp_reset_credential_sync_state
}

zafp() {
  emulate -L zsh
  local account password role

  if _zafp_credentials_sync_is_running; then
    printf "zafp is already running. Use unzafp to stop it.\n"
    return 1
  fi

  account=${1-$_ZAFP_DEFAULT_ACCOUNT}
  role=${2-$_ZAFP_DEFAULT_ROLE}

  printf "Starting credentials sync for %s/%s using %s ...\n" $account $role $_ZAFP_HOST

  _zafp_reset_credential_sync_state

  read -rs "password?Password:"
  printf "\n"

  _zafp_credentials_sync $account $role $password &
  _zafp_credential_sync_pid=$!

  while [ ! -s $_ZAFP_CREDENTIAL_SYNC_FILE ]; do
    if ! _zafp_credentials_sync_is_running; then
      break
    fi

    printf "."
    sleep 1
  done

  if ! _zafp_credentials_sync_is_running; then
    _zafp_reset_credential_sync_state
    printf "Failed to start credentials sync.\n"
    return 1
  fi

  _zafp_account=$account
  _zafp_role=$role
  printf "\nCredentials sync for %s/%s using %s is running.\n" $_zafp_account $_zafp_role $_ZAFP_HOST
}

_zafp_check_dependencies
_zafp_init_config_variables
_zafp_reset_credential_sync_state

autoload -U add-zsh-hook
add-zsh-hook precmd _zafp_precmd
add-zsh-hook zshexit _zapf_zshexit
