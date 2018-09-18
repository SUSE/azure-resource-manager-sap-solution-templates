#!/bin/bash
#
# -t is a bash builtin test that checks if a file descriptor is opened and refers to a terminal (man bash for more info).
# When run in a terminal, the logs are issued with echo, they appear in the console only. It means that when I work on the script, I won’t pollute the logs.
# When run without terminal, logs are issued with logger, they go to the system log.
#

function log()
{
 [[ -t 1 ]] &&  echo "$@" || logger -t $(basename $0) "$@"; 
}

log $@
