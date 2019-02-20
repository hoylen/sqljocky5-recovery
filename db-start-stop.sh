#!/bin/bash
#
# Randomly start and stop the MySQL/MariaDB database engine.

while true; do
  systemctl start mysqld.service
  R=$((2 + $RANDOM % 10))
  echo "`date '+%F %T'`: started (will stop it after ${R}s)"
  sleep "$R"

  systemctl stop mysqld.service
  R=$((2 + $RANDOM % 10))
  echo "`date '+%F %T'`: stopped (will start it after ${R})"
  sleep "$R"
done
