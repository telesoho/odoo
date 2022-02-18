#!/bin/bash
#
# This script is designed to be run inside the container

log_src='['${0##*/}']'

RED='\033[0;31m'
NC='\033[0m' # No Color

function help {
    echo "SDL"
}

function infine_loop {
    while true; do sleep 12 ; done
}

function _ensure_odoo_user_owns_volume {
    # Make sure the folder exists
    if [ -d "$1" ]; then
        # Check if the volume has been mounted read-only
        mount_type=$( cat /proc/mounts | grep "\s$1\s" | \
            awk '{print tolower(substr($4,0,3))}' )

        if [ "$mount_type" != 'ro' ]; then
            # Set target user as owner
            chown "$odoo_user":"$odoo_user" -fR "$1"
        else
            echo $log_src[`date +%F.%H:%M:%S`]' Read-only volume:' "$1"
        fi
    fi
}

function _ensure_odoo_user_owns_volumes {
    _ensure_odoo_user_owns_volume /opt/odoo/etc
    _ensure_odoo_user_owns_volume /opt/odoo/custom
    _ensure_odoo_user_owns_volume /opt/odoo/data
    _ensure_odoo_user_owns_volume /opt/odoo/ssh
}

function _host_user_mapping {
    # Name of the target Odoo user
    TARGET_USER_NAME='target-odoo-user'

    # Check whether target user exists or not
    exists=$( getent passwd "$TARGET_UID" | wc -l )

    # Create target user
    if [ "$exists" == "0" ]; then
        # Odoo user is now the target Odoo user
        odoo_user="$TARGET_USER_NAME"

        echo $log_src[`date +%F.%H:%M:%S`]' Creating target Odoo user...'
        adduser --uid "$TARGET_UID" --disabled-login --gecos "" --quiet \
            "$odoo_user"

        # Add target user to odoo group so that he can read/write the content
        # of /opt/odoo
        usermod -a -G odoo "$odoo_user"
    else
        # Check whether trying to map with the same UID as `odoo` user
        odoo_user_id=$( id -u "$odoo_user" )

        if [ "$TARGET_UID" -ne "$odoo_user_id" ]; then

            # Check whether trying to map with an existing user other than the
            # target user
            target_uid_name=$( getent passwd "$TARGET_UID" | cut -d: -f1 )

            if [ "$TARGET_USER_NAME" != "$target_uid_name" ]; then
                echo $log_src[`date +%F.%H:%M:%S`]' ERROR: Cannot create' \
                    'target user as target UID already exists.'
            else
                # Target user has already been created (e.g. container has
                # been restarted)
                odoo_user="$TARGET_USER_NAME"
            fi
        fi
    fi
}

function start {
   # Host user mapping
   odoo_user='odoo'
   if [ "$TARGET_UID" ]; then
      _host_user_mapping
   fi

   python_bin="/opt/odoo/venv/bin/python"
   if [ "$PYTHON_BIN" ]; then
      python_bin="$PYTHON_BIN"
   fi

   service_bin="odoo-bin"
   if [ "$SERVICE_BIN" ]; then
      service_bin="$SERVICE_BIN"
   fi

   odoo_conf_file="/opt/odoo/etc/odoo.conf"
   if [ "$CONF_FILE" ]; then
      odoo_conf_file="$CONF_FILE"
   fi

   # If the folders mapped to the volumes didn't exist, Docker has created
   # them with root instead of the target user. Making sure to give back the
   # ownership to the corresponding host user.
   _ensure_odoo_user_owns_volumes

   echo $log_src[`date +%F.%H:%M:%S`]' Updating Odoo conf...'
   save_environ -c $odoo_conf_file -s '{"ODOO_":"options"}' --delete-env=True

   if [ -f /opt/scripts/startup.sh ]; then
      echo $log_src[`date +%F.%H:%M:%S`]' Running startup...'
      source /opt/scripts/startup.sh
   fi

   echo $log_src[`date +%F.%H:%M:%S`]' Running odoo...'
   if [ ! -e $1 ]; then
      echo $log_src[`date +%F.%H:%M:%S`]' ...with additional args:' $*
   fi
   sudo -i -u "$odoo_user" "$python_bin" \
      "/opt/odoo/src/odoo/$service_bin" -c "$odoo_conf_file" $*
}

# Run command
$*
