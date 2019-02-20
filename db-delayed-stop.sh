#!/bin/bash
#
# Usage: db-stop-after-delay.sh [seconds]

PROG=`basename "$0"`

DEFAULT_DELAY=5

if [ `id -u` -ne 0 ]; then
  echo "$PROG: error: root privileges required" >&2
  exit 1
fi

if [ $# -gt 0 ]; then
  DELAY="$1"
else
  DELAY=$DEFAULT_DELAY
fi

sleep "$DELAY"
systemctl stop mysqld.service

