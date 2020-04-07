# shellcheck shell=ksh        # Unfortunately, shellcheck does not support zsh.
# shellcheck disable=SC2086
# shellcheck disable=SC2128

_ZAFP_CONFIG_FILE=$HOME/.zafp.zsh
_ZAFP_CONFIG_VARIABLES=('_ZAFP_HOST' '_ZAFP_PATH' '_ZAFP_USER' '_ZAFP_DEFAULT_ACCOUNT' '_ZAFP_DEFAULT_ROLE')

_ZAFP_CREDENTIALS_FILE=$(mktemp)

_ZAFP_DEPENDENCIES=('curl' 'date' 'jq' 'mktemp')

# shellcheck disable=SC2016
_ZAFP_PROMPT_PREFIX='[$_zafp_account/$_zafp_role $_zafp_credentials_expire_in] '

# Global variables used by zafp and _zafp_*:
_zafp_account=unknown_account
_zafp_credentials_expire_in=unknown_time_interval
_zafp_credentials_sync_pid=-1
_zafp_role=unknown_role

_zafp_check_dependencies() {
  for command in $_ZAFP_DEPENDENCIES; do
    if ! type $command >/dev/null; then
      printf "The command %s is not installed. Please install.\n" $command >&2
    fi
  done
}

_zafp_credentials_sync() {
  local password=$1

  local curl_exit_status=0
  local tmp_output_file
  tmp_output_file=$(mktemp)
  local url=https://$_ZAFP_HOST/$_ZAFP_PATH/$_zafp_account/$_zafp_role

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

    mv $tmp_output_file $_ZAFP_CREDENTIALS_FILE

    sleep 60
  done

  printf "Credentials sync: Stopping ...\n"
  if [[ -w $tmp_output_file ]]; then
    rm $tmp_output_file
  fi
  _zafp_reset_file $_ZAFP_CREDENTIALS_FILE
  printf "Credentials sync: Stopped.\n"
  return $curl_exit_status
}

_zafp_credentials_sync_is_running() {
  if ((_zafp_credentials_sync_pid < 0)); then
    return 1
  fi

  kill -0 $_zafp_credentials_sync_pid 2>/dev/null
  return $?
}

_zafp_get_credentials_value() {
  local key=$1
  jq --raw-output .$key $_ZAFP_CREDENTIALS_FILE
}

_zafp_init_config_variables() {
  if [[ -e $_ZAFP_CONFIG_FILE ]]; then
    # shellcheck source=.zafp.zsh.template
    source $_ZAFP_CONFIG_FILE
  else
    printf "The configuration file %s does not exist. Please create.\n" $_ZAFP_CONFIG_FILE >&2
  fi

  for config_var in $_ZAFP_CONFIG_VARIABLES; do
    if [[ ! -v "$config_var" ]]; then
      printf "The configuration variable %s is not set. Please add to %s.\n" $config_var $_ZAFP_CONFIG_FILE >&2
    fi
  done
}

_zafp_precmd() {
  _zafp_update_shell_variables
  _zafp_update_prompt
}

_zafp_reset_file() {
  local file=$1
  printf "" >$file
}

_zafp_reset_sync() {
  _zafp_credentials_sync_pid=-1
  _zafp_reset_file $_ZAFP_CREDENTIALS_FILE
}

_zafp_update_prompt() {
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

_zafp_update_shell_variables() {
  if _zafp_credentials_sync_is_running; then
    AWS_ACCESS_KEY_ID=$(_zafp_get_credentials_value AccessKeyId)
    export AWS_ACCESS_KEY_ID

    AWS_SECRET_ACCESS_KEY=$(_zafp_get_credentials_value SecretAccessKey)
    export AWS_SECRET_ACCESS_KEY

    AWS_SESSION_TOKEN=$(_zafp_get_credentials_value Token)
    export AWS_SESSION_TOKEN

    AWS_SECURITY_TOKEN=$(_zafp_get_credentials_value Token)
    export AWS_SECURITY_TOKEN

    _zafp_update_shell_variable_zafp_credentials_expire_in
  else
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
    # shellcheck disable=SC2034
    _zafp_credentials_expire_in=unknown_time_interval
  fi
}

_zafp_update_shell_variable_zafp_credentials_expire_in() {
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
  _zafp_credentials_expire_in=$expire_in_statement
}

_zapf_zshexit() {
  rm $_ZAFP_CREDENTIALS_FILE
}

unzafp() {
  emulate -L zsh

  if ! _zafp_credentials_sync_is_running; then
    printf "zafp is not running. Use zafp to start it.\n"
    return 1
  fi

  kill $_zafp_credentials_sync_pid
  wait $_zafp_credentials_sync_pid

  _zafp_reset_sync
}

zafp() {
  emulate -L zsh

  if _zafp_credentials_sync_is_running; then
    printf "zafp is already running. Use unzafp to stop it.\n"
    return 1
  fi

  _zafp_account=${1-$_ZAFP_DEFAULT_ACCOUNT}
  _zafp_role=${2-$_ZAFP_DEFAULT_ROLE}

  printf "Starting credentials sync for %s/%s using %s ...\n" $_zafp_account $_zafp_role $_ZAFP_HOST

  local password
  read -rs "password?Password:"
  printf "\n"

  _zafp_reset_sync

  _zafp_credentials_sync $password &
  _zafp_credentials_sync_pid=$!

  while [ ! -s $_ZAFP_CREDENTIALS_FILE ]; do
    if ! _zafp_credentials_sync_is_running; then
      break
    fi

    printf "."
    sleep 1
  done

  if ! _zafp_credentials_sync_is_running; then
    _zafp_reset_sync
    printf "Failed to start credentials sync.\n"
    return 1
  fi

  printf "\nCredentials sync for %s/%s using %s is running.\n" $_zafp_account $_zafp_role $_ZAFP_HOST
}

_zafp_check_dependencies
_zafp_init_config_variables

autoload -U add-zsh-hook
add-zsh-hook precmd _zafp_precmd
add-zsh-hook zshexit _zapf_zshexit
