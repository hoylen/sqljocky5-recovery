#!/bin/bash
#
# Run disconnect_transaction.dart in a loop, stopping the database in
# an attempt to trigger issues.

PROG=`basename "$0"`

if [ `id -u` -ne 0 ]; then
  echo "$PROG: error: root privileges required" >&2
  exit 1
fi

while true; do
  # Start database
  systemctl start mysqld.service

  # Stop database after a few seconds
  ./db-delayed-stop.sh 4 &

  # Before it stops, run the test program (which expects the database
  # to be available when it starts, but not available 10s after it starts).

  dart disconnect_transaction.dart 8
done

#EOF
