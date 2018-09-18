#!/bin/bash

function log()
{
#
# -t is a bash builtin test that checks if a file descriptor is opened and refers to a terminal (man bash for more info).
# When run in a terminal, the logs are issued with echo, they appear in the console only. It means that when I work on the script, I won’t pollute the logs.
# When run without terminal, logs are issued with logger, they go to the system log.
#
 [[ -t 1 ]] &&  echo "$@" || logger -t $(basename $0) "$@"; 
}

log "updating all packages"
zypper update -y

log "installing packages"
zypper install -t pattern -y ha_sles sap_server

# sap-suse-cluster-connector it needs to be version3
zypper install -y sap-suse-cluster-connector
zypper install -y saptune
zypper install -y unrar

# make sure wrong conflicting packages are gone
#
