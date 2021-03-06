#!/usr/bin/env bash
# Author: Arem Chekunov
# Author email: scorp.dev.null@gmail.com
# repo: https://github.com/sc0rp1us/cehf-useful-scripts
# env and func's
set -x

_BACKUP_NAME="chef-backup_$(date +%Y-%m-%d)"
_BACKUP_USER="root"
_BACKUP_DIR="/var/backups"
_SYS_TMP="/tmp"
_TMP="${_SYS_TMP}/chef-backup/${_BACKUP_NAME}"

_pg_dump(){
su - opscode-pgsql -c "/opt/opscode/embedded/bin/pg_dumpall -c"
}

pg_running(){
  while [ `chef-server-ctl status postgresql | cut -d ':' -f 1` == 'down' ]; do
    echo "pg is down, sleeping 1"
    sleep 1
  done
}

syntax(){
        echo ""
        echo -e "\t$0 --backup                  # for backup"
        echo -e "\t$0 --restore </from>.tar.bz2 # for restore"
        echo ""
}

_chefBackup(){

echo "Backup function"

id ${_BACKUP_USER} &> /dev/null
    _BACKUP_USER_EXIST=$?
    if [[ ${_BACKUP_USER_EXIST} -ne 0 ]]; then
        echo "You should have a backup user"
    fi


set -e
set -x
# Create folders
mkdir -p ${_TMP}
mkdir -p ${_TMP}/postgresql
mkdir -p ${_BACKUP_DIR}/chef-backup

chef-server-ctl org-list >> ${_TMP}/orglist.txt
chef-server-ctl stop


# Backup database
chef-server-ctl start postgresql
pg_running
_pg_dump > ${_TMP}/postgresql/pg_opscode_chef.sql
chef-server-ctl stop postgresql

cd ${_SYS_TMP}
    if [[ -e ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2 ]]; then
        mv ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2{,.previous}
    fi

    tar cvjpf ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2 ${_TMP}/postgresql /etc/opscode /var/opt/opscode ${_TMP}/orglist.txt
    chown -R ${_BACKUP_USER}:${_BACKUP_USER} ${_BACKUP_DIR}/chef-backup/
    chmod -R g-rwx,o-rwx ${_BACKUP_DIR}/chef-backup/


    rm -Rf ${_TMP}
chef-server-ctl start
pg_running
}


_chefRestore(){
echo "Restore function"
    if [[ ! -f ${source} ]]; then
        echo "ERROR: file ${source} do not exist"
        exit 1
    fi

    set -e
    set -x
    chef-server-ctl stop
    tar xvjpf ${source} --exclude='var/opt/opscode/drbd/data/postgresql_9.2' -C /
    chef-server-ctl start postgresql
    pg_running
    _pg_dump > /var/opt/opscode/pg_opscode_chef.sql.$(date +%Y-%m-%d_%H:%M:%S).bak
    ADIR=`ls /tmp/chef-backup/`
    _TMP_RESTORE="${_SYS_TMP}/chef-backup/$ADIR"
    cd ${_TMP_RESTORE}
    su - opscode-pgsql -c "/opt/opscode/embedded/bin/psql opscode_chef  < ${_TMP_RESTORE}/postgresql/pg_opscode_chef.sql"

    chef-server-ctl start
    sleep 30
    chef-server-ctl reconfigure
    sleep 30
    opscode-manage-ctl reconfigure
    cd ~
    rm -Rf ${_TMP_RESTORE}
}

# tests
if [[ ! -x /opt/opscode/embedded/bin/pg_dump ]];then
    echo "Use it script only on chef-server V11"
    exit 1
fi

if [[ $(id -u) -ne 0 ]]; then
    echo "You should to be root"
    exit 1
fi

# body
while [ "$#" -gt 0 ] ; do
    case "$1" in
        -h|--help)
            syntax
            exit 0
            ;;
        --backup)
            action="backup"
            shift 1
            ;;
        --restore)
            action="restore"
            source="${2}"
            break
            ;;
        *)
            syntax
            exit 1
            ;;

    esac
done


if [[ ${action} == "backup" ]];then
        _chefBackup
elif [[ ${action} == "restore" ]];then
        _chefRestore
else
        syntax
        exit 1
fi
