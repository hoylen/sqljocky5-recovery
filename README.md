Recovery testing of sqljocky5
=============================

Program for testing different failure and recovery scenarios for
sqljocky5.

## Background

The use case where recoverability is required is for a Web server
written in Dart, which uses sqljocky5 to communicate with a backend
MySQL/MariaDB database.

The Web server is started and is expected to serve requests
continueously without needing manual intervention. It must continue to
do so even if (intermittent) communication problems are encountered
with the database host or something happens to the database. For
example, temprary network problems or the database being restarted.
When the database becomes available again, the Web server should
continue to server requests.

## Usage

    dart dbrecovery.dart [--continue|-c] [--help|-h]  [pauseLocation]

The `--continue` option starts the program in non-interactive mode.
By default, it starts in interactive mode.

The _pauseLocation_ indicates when the pause occurs:

- beforeNextCycle (the default)
- beforeGetTransaction
- beforeQuery
- beforeCommit
- beforeRollback

In interactive mode, at the pause location the user is prompted. Type
"s" and the return key to continue a single cycle, or simply press the
return key.

Type "c" to enter the non-interactive mode, where each pause will no
longer require user interaction. In non-interactive mode, during the
10 second pause, full stops (".") are printed out every second.

The following scenarios (except for the application exception
scenario) can all be run using the non-interactive mode.

## Scenarios

### Scenario 1: startup race condition

If the database and Web server are restarted (e.g. in an automatic
reboot situation), there is no guarantee the database will come up
before the Web server.

1. Stop the database.
2. Run `dart dbrecovery.dart`
3. Run a few cycles.
4. Start the database.
5. Run a few more cycles.

Expected behaviour: the cycles will initially fail, but will succeed
after the database has been started.  The first set of cycles should
print out "cannot run" and the second set of cycles shoud print out
"ok".

### Scenario 2: deliberate outage

The database is cleanly stopped and is restarted. For example, if the
database administrator restarts the database or reboots the database's
host.

1. Start the database and run `dart dbrecovery.dart`.
2. Run a few cycles.
3. Stop the database cleanly (e.g. with `systemctl stop mariadb.service`).
4. Run a few more cycles.
5. Start the database.
4. Run a few more cycles.

Expected behaviour: the cycles while the database is stopped will
fail, but all the other cycles will succeed.

Variation: restart the database (both stop and start it) during the
same pause. Expect all the cycles to succeed, as if nothing had ever
happened to the database.

### Scenario 3: unexpected outage

The database stops uncleanly. This is different to the previous
scenario, because MariaDB 10.x (but not MariaDB 5.5) sends something
to clients when it is cleanly shutdown. In sqljocky5 v1.x, this
scenario failed (because sqljocky5 did not properly handle the data
received) even though the clean shutdown scenario worked.

Same process as Scenario 2, except use `kill -9` to stop the _mysqld_
process.

Note: _systemd_ will probably automatically restart a new _mysqld_
process, but you should see it fail on one cycle and then start
working again when the _mysqld_ has restarted. This test is best run
in non-interactive mode and killing the process towards the end of the
pause (otherwise the _mysqld_ might be automatically restarted before
the pause finishes).

### Scenario 4: failures in mid-cycle

Repeat scenario 2 and 3, but with the pause occuring at different
stages in the cycle (instead of before the connection is obtained).

#### 4a. beforeGetTransaction

Run:

    dart dbrecovery.dart beforeGetTransaction

Stopping the database during the pause will simulate successfully
getting a connection, but then failure when trying to create a
transaction on it.

#### 4b. beforeQuery

Run:

    dart dbrecovery.dart beforeQuery

Stopping the database during the pause will simulate successfully
getting a connection and successfully creating a transaction on it,
but then running a query with that transaction fails.

Currently, with sqljocky 2.2.1, this scenario fails. The program
prints out the following and terminates (there is no ability for the
code to catch the exception):

```
Unhandled exception:
SocketException: Write failed (OS Error: Broken pipe, errno = 32), address = database.example.com, port = 62372
#0      _rootHandleUncaughtError.<anonymous closure> (dart:async/zone.dart:1112:29)
#1      _microtaskLoop (dart:async/schedule_microtask.dart:41:21)
#2      _startMicrotaskLoop (dart:async/schedule_microtask.dart:50:5)
#3      _runPendingImmediateCallback (dart:isolate/runtime/libisolate_patch.dart:115:13)
#4      _RawReceivePortImpl._handleMessage (dart:isolate/runtime/libisolate_patch.dart:172:5)
```

But sometimes it prints out the following and does not
terminate. Maybe a race condition of some form?

```
Error: unexpected exception (get tx): MySqlClientError: MySQL Client Error: Connection cannot process a request for QueryStreamHandler(start transaction) while a request is already in progress for QueryStreamHandler(rollback)
```

#### 4c. beforeCommit

Run:

    dart dbrecovery.dart beforeCommit

The pause occurs after successfully running a query, but before the
transaction is committed.

With the pause in this location (and also before the query), it is
possible to throw an exception (by typing "e" as the input). The
program should catch the exception and rollback any changes.

Note: currently, the query does not make any changes.  The code needs
to be changed for further testing.

#### 4d. beforeRollback

The code needs to be changed before this pause location is useful for
testing.


## Notes

Behaviour is different when connecting to the database directly and
via a SSH tunnel. Test both.
