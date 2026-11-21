#!/usr/bin/env bash
set -Eeuo pipefail
user=${1:?Username required}

extensions=(
    npm:pi-web-access
    npm:pi-lens
)
IFS=: read -r _ _ user_uid _ _ user_home _ < <(getent passwd "$user")
[[ $user_uid != 0 && $user_home == /* && $user_home != / ]]

launcher=()
if ((EUID != user_uid)); then
    launcher=(runuser -u "$user" --)
fi

# Pi adds user packages to its existing settings and owns their installation.
cd -- "$user_home"
for package in "${extensions[@]}"; do
    "${launcher[@]}" env HOME="$user_home" \
        XDG_CONFIG_HOME="$user_home/.config" XDG_DATA_HOME="$user_home/.local/share" \
        XDG_STATE_HOME="$user_home/.local/state" XDG_CACHE_HOME="$user_home/.cache" \
        PI_CODING_AGENT_DIR="$user_home/.local/share/pi" \
        bash -lc 'exec "$@"' bash pi install --no-approve "$package"
done
