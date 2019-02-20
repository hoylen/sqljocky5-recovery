// Usage: disconnect_transaction.dart [--continue] [seconds]
//
// Opens a connection, starts a transaction, and runs a query. Between obtaining
// the transaction and running the query, an opportunity is provided for the
// database (or network connection to it) to be stopped, to simulate a fault
// that programs should be able to recover from.
//
// If seconds is provided, the program will wait for that amount of time before
// automatically continuing. Otherwise, it will prompt the user for input before
// continuing.
//
// If the "-c" or "--continue" option is specified, the program will run in
// a continuous loop. Otherwise, it will run once and exit.

import 'dart:async';
import 'dart:io';
import 'package:sqljocky5/sqljocky.dart';

Future main(List<String> arguments) async {
  var s = ConnectionSettings(
    host: "test.example.com",
    port: 3306,
    user: "test",
    password: "p@ssw0rd",
    db: "testdb",
  );

  // Parse command line arguments

  final args = new List<String>.from(arguments);

  if (args.remove('-h') || args.remove('--help')) {
    print('Usage: disconnect_transaction [--continue|-c] [numSeconds]');
    exit(0);
  }
  final continueMode = (args.remove('-c') || args.remove('--continue'));

  int delay; // null means interactive mode

  if (1 < args.length) {
    stderr.write('Usage error: too many arguments\n');
    exit(2);
  } else if (args.length == 1) {
    try {
      delay = int.parse(args[0]); // automatic mode
      if (delay < 1) {
        stderr.write('Error: number of seconds must be greater than zero\n');
        exit(2);
      }
    } on FormatException {
      stderr.write('Error: number of seconds is not an integer: ${args[0]}\n');
      exit(2);
    }
  } else {
    delay = null; // interactive mode
  }

  print('Database: ${s.host}:${s.port}: ${s.db}');

  do {
    final runTime = new DateTime.now();

    try {
      // Open a connection and get a transaction

      final conn = await MySqlConnection.connect(s);
      final tx = await conn.begin();

      // Provide an opportunity for a network fault or database outage

      if (delay == null) {
        // Interactive mode
        stdout.write("Stop the database and press enter to continue... ");
        var line = stdin.readLineSync().trim().toLowerCase();
        if (line == 'q') {
          exit(0);
        }
      } else {
        // Automatic mode
        await Future.delayed(Duration(seconds: delay));
      }

      // Try using the transaction that was obtained before the fault/outage

      try {
        final r = await tx
            .execute("SELECT TIMEDIFF(NOW(),UTC_TIMESTAMP) AS 'tz_offset'");
        Results result = await r.deStream();

        //print(result.map((r) => r.byName('tz_offset')));
        print('$runTime: query succeeded');

        await tx.commit();
      } catch (e) {
        print("$runTime: query exception (${e.runtimeType}): $e");
      }

      await conn.close();
    } catch (e) {
      print('$runTime: no connection/transaction: $e');
    }

    if (continueMode) {
      // Continuous mode: give a chance for the database to come back
      // before starting the next run.

      if (delay == null) {
        // Interactive mode
        stdout.write("Start the database and press enter to continue... ");
        var line = stdin.readLineSync().trim().toLowerCase();
        if (line == 'q') {
          exit(0);
        }
      } else {
        // Automatic mode
        await Future.delayed(Duration(seconds: delay));
      }
    }
  } while (continueMode);
}
