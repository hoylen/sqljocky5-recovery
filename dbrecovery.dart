/// Test program for using sqljocky5 in programs that need to run contineuously.
///
/// See README.md for details.

import 'dart:async';
import 'dart:io';

import 'package:sqljocky5/sqljocky.dart';
import 'package:sqljocky5/connection/connection.dart'; // for Transaction class

//================================================================
// Connection settings

// TODO: edit to match the database used for testing

final dbSettings = new ConnectionSettings(
    host: 'test.example.com',
    port: 3306,
    useSSL: false,
    user: 'tester',
    password: 'p@ssw0rd',
    db: 'testdb');

//================================================================
// Where the pause occurs.
//
// In a real program, there are no pauses. These are just used for testing: to
// give the user time to stop/kill/start the database (to simulate failures at
// different times).

enum PauseLocation {
  beforeNextCycle,
  beforeGetTransaction,
  beforeQuery,
  beforeCommit,
  beforeRollback,
}

/// Location for pause (can be changed via command line arguments)

var pauseLocation = PauseLocation.beforeQuery;

/// Duration of the pause when running in non-interactive mode.

const int pauseSeconds = 10;

//----------------------------------------------------------------
/// Get the name of a [PauseLocation] value without the enum name.

String nameOf(PauseLocation value) {
  return value.toString().substring((value.runtimeType.toString().length + 1));
}

//================================================================
/// An exception the application throws.
///
/// The transaction should be rolled back if this exception is thrown.

class ApplicationException implements Exception {}

/// Exception to indicate the user wants to cleanly exit the program.

class QuitException implements Exception {}

//================================================================
// Mode

/// Mode: interactive or non-interactive.
///
/// If true, at each pause the user is prompted for input. Otherwise, each
/// pause simply delays for [pauseSeconds] seconds before continuing (without
/// needing any user input).

bool interactiveMode = true;

/// Tracks if a pause has occurred during a cycle.
///
/// This is to ensure that no cycle runs without a pause, otherwise (in
/// non-interactive mode) a cycle could run immediately after the previous
/// cycle when there was a failure of some kind that prevents the desired
/// pause from happening (e.g. if the location was before the commit, but the
/// transaction could not be obtained).

bool pauseDone;

//----------------------------------------------------------------
/// Interaction or delay in the test program.

void doPause({String name, bool allowException = false}) {
  name ??= nameOf(pauseLocation);

  stdout.write('$name: ');

  if (!interactiveMode) {
    // Non-interactive mode

    if (pauseLocation == PauseLocation.beforeCommit) {
      throw new ApplicationException();
    }

    for (int x = 0; x < pauseSeconds; x++) {
      stdout.write('.');
      sleep(const Duration(seconds: 1));
    }
    stdout.write(' ');
  } else {
    // Interactive mode
    var inputOk = true;
    do {
      stdout.write((allowException)
          ? 'Action ([S]ingle-step, [c]ontinue, [e]xception, [q]uit)? '
          : 'Action ([S]ingle-step, [c]ontinue, [q]uit)? ');
      var line = stdin.readLineSync().trim().toLowerCase();

      if (line == 'single-step' || line == 's' || line == '') {
        // single step
      } else if (line == 'continue' || line == 'c') {
        interactiveMode = false;
      } else if (allowException && (line == 'exception' || line == 'e')) {
        throw new ApplicationException();
      } else if (line == 'quit' || line == 'q') {
        throw new QuitException();
      } else {
        stderr.write('invalid input\n');
        inputOk = false;
      }
    } while (!inputOk);
  }

  pauseDone = true;
}

//================================================================
// Helper code for robust handling of database connections

//----------------------------------------------------------------
/// Connection that gets reused between cycles (if possible).

MySqlConnection connection;

//----------------------------------------------------------------

Future<Transaction> reliableGetTransaction() async {
  // Get a connection

  final reusingConnection = (connection != null);

  if (connection == null) {
    // Cannot reuse any previously obtained connection

    try {
      connection = await MySqlConnection.connect(dbSettings);
    } catch (e) {
      var recognisedIssue = false;

      if (e is SocketException) {
        if (e.osError != null &&
            e.osError.errorCode == 60 &&
            e.osError.message == 'Operation timed out' &&
            e.message == '') {
          // Host is not running
          recognisedIssue = true;
        }
        if (e.osError != null &&
            e.osError.errorCode == 61 &&
            e.osError.message == 'Connection refused' &&
            e.message == '') {
          // Not listing on port (when connected directly)
          recognisedIssue = true;
        }
        if (e.osError == null &&
            e.address == null &&
            e.port == null &&
            e.message == 'Socket has been closed') {
          // Not listening on port (when connected via an SSH tunnel)
          recognisedIssue = true;
        }
      }

      if (recognisedIssue) {
        // Could not open a connection: this method will return null at the end
        assert(connection == null);
      } else {
        // Unrecognised exception
        print('Error: unexpected exception (connection): ${e.runtimeType}: $e');
        // Note: this can occur if the network connection is broken so
        // DNS lookup fails (so we want it to recover when the network
        // returns). But it can also occur if the hostname is wrongly configured
        // and will never resolve.
      }
    }
  }

  Transaction result;

  if (connection != null) {
    // Start a new transaction on the connection

    if (pauseLocation == PauseLocation.beforeGetTransaction) {
      doPause();
    }

    try {
      result = await connection.begin();
    } catch (e) {
      // Getting a transaction failed

      if (isDatabaseException(e)) {
        // Expected exception: database connection had gone away

        connection = null; // discard old connection

        if (reusingConnection) {
          // Connection might have been stale. Try again with a new connection.

          try {
            // Attempt to open a new connection and use it
            connection = await MySqlConnection.connect(dbSettings);
            result = await connection.begin();
          } catch (e) {
            // Attempt failed. Give up: can't get a transaction
            assert(connection == null);
            assert(result == null);
          }
        } else {
          // The connection was newly opened by this method, so no point in
          // trying to open another connection: give up.
          assert(result == null);
        }
      } else {
        // Unrecognised exception
        print('Error: unexpected exception (get tx): ${e.runtimeType}: $e');
        connection = null; // try new connection next time. What else can we do?
      }
    }
  }

  return result; // could be null
}

//----------------------------------------------------------------
/// Determine if an exception could be caused by database connection failures.

bool isDatabaseException(Object e) {
  var knownIssue = false;

  if (e is SocketException) {
    if (e.osError == null &&
        e.address == null &&
        e.port == null &&
        e.message == 'Socket has been closed') {
      knownIssue = true;
    }

    if (e.osError != null &&
        e.osError.errorCode == 60 &&
        e.osError.message == 'Operation timed out' &&
        e.message == '') {
      // Host is not running
      knownIssue = true;
    }
  }
  if (e is MySqlException) {
    if (e.errorNumber == 1927 &&
        e.sqlState == '70100' &&
        e.message == 'Connection was killed') {
      // mysqld stopped cleanly
      knownIssue = true;
    }
  }
  // TODO: are there other exceptions to match?

  return knownIssue;
}

/*

Some exceptions might need to be handled differently, since they are more
likely to be caused by misconfiguration of the client.

Wrong host name:

SocketException:
        if (e.osError.errorCode == 8 &&
            e.osError.message ==
                'nodename nor servname provided, or not known' &&
            e.address == null &&
            e.port == null &&
            e.message.startsWith('Failed host lookup: ')) {
          // When the hostname does not resolve (config error or DNS broken)
          recognisedIssue = true;
        }
*/

//================================================================
// Simple example of robustly using transactions

//----------------------------------------------------------------
/// Use the transaction [tx] to perform a SQL query.
///
/// For the purposes of this test, the query used doesn't really matter.
/// This query checks the timezone, so it does not depend on any tables in
/// the database.

Future simpleQuery(Transaction tx) async {
  final localTzOffset = new DateTime.now().timeZoneOffset;

  // For testing commit, use a query that modifies the database.

  final results =
      await tx.prepared('SELECT TIMEDIFF(NOW(),UTC_TIMESTAMP)', <Object>[]);
  final rows = <Row>[];
  await for (var r in results) {
    rows.add(r);
  }

  assert(rows.length == 1);
  assert(rows[0].length == 1);
  final Object databaseTzOffset = rows[0][0];

  if (databaseTzOffset is Duration) {
    if (localTzOffset != databaseTzOffset) {
      // Bad things happen if the client's timezone does not match the timezone
      // used by the database. Values of the SQL DATETIME datatype are
      // processed incorrectly.
      throw StateError('database does not match local timezone of Dart client');
    }
  } else {
    throw const FormatException('query did not return a Duration');
  }
}

//----------------------------------------------------------------
/// Run a cycle.
///
/// When the database is available, this cycle should run successfully. If it
/// is not available, it will run unsuccessfully but subsequent cycles should
/// run successfully when the database becomes available again.
///
/// The program should be robust, no matter what happens to the database or
/// network connections to it: not crash nor need restarting.

Future runCycle(int n) async {
  // Run a cycle.

  n += 1;
  pauseDone = false;

  // General pattern:
  //
  // tx = get transaction();
  // if (tx successful) {
  //   try {
  //     perform queries using it;
  //     commit changes
  //   } catch (exceptions) {
  //     rollback changes
  //   }
  // }

  // Get a transaction to use

  final tx = await reliableGetTransaction();

  if (tx != null) {
    // Use the transaction for queries

    try {
      if (pauseLocation == PauseLocation.beforeQuery) {
        doPause(allowException: true);
      }

      await simpleQuery(tx);
      // other queries can be performed here

      if (pauseLocation == PauseLocation.beforeCommit) {
        doPause(allowException: true);
      }
      if (pauseLocation == PauseLocation.beforeRollback) {
        throw new ApplicationException(); // otherwise rollback won't occur
      }

      await tx.commit();

      print('$n: ok');
    } catch (e) {
      final okIfRollbackFails = isDatabaseException(e);

      if (!okIfRollbackFails && e is! ApplicationException) {
        print('\nWarning: unexpected exception: ${e.runtimeType}: $e');
      }

      try {
        if (pauseLocation == PauseLocation.beforeRollback) {
          doPause(allowException: false);
        }

        await tx.rollback();
        print('$n: rollback done');
      } catch (e2) {
        if (!okIfRollbackFails) {
          print(
              '\nWarning: unexpected exception (rollback): ${e2.runtimeType}: $e2');
        }
      }
      connection = null; // use a new connection for the next cycle

      print('$n: failed');
    }
  } else {
    print('$n: cannot run');
  }

  if (pauseLocation == PauseLocation.beforeNextCycle) {
    doPause();
  }
  if (!pauseDone) {
    doPause(name: 'next cycle');
  }
}

//----------------------------------------------------------------

void main(List<String> arguments) async {
  // Crude command line parsing: sets the pauseLocation and interactiveMode

  if (arguments.isNotEmpty) {
    final args = new List<String>.from(arguments); // non fixed-length copy

    if (args.remove('-h') || args.remove('--help')) {
      print('Usage: dbrecovery [--continue|-c] [--help|-h] [pauseLocation]');
      exit(0);
    }

    if (args.remove('-c') || args.remove('--continue')) {
      interactiveMode = false;
    }

    if (1 < args.length) {
      stderr.write('Usage error: too many arguments\n');
      exit(2);
    } else if (args.length == 1) {
      final arg = args[0].toLowerCase();

      pauseLocation = null;
      for (var value in PauseLocation.values) {
        if (arg == nameOf(value).toLowerCase()) {
          pauseLocation = value;
        }
      }
      if (pauseLocation == null) {
        final v = PauseLocation.values.map((d) => nameOf(d)).join(', ');
        stderr.write(
            'Usage error: unknown pause location (expecting: $v): $arg\n');
        exit(2);
      }
    }
  }

  print('Database: ${dbSettings.host}:${dbSettings.port}: ${dbSettings.db}');

  // Run the cycles

  try {
    var n = 0;
    while (true) {
      await runCycle(n++);
    }
  } catch (e, st) {
    if (e is QuitException) {
      // Clean exit
      if (connection != null) {
        await connection.close();
      }
    } else {
      // Unexpected exception: this should never happen.
      stderr.write('Error: uncaught exception: $e\nStack trace: $st\n');
    }
  }
}
