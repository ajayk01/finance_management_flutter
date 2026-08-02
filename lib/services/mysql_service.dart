import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/mysql_insert_utils.dart';

class MySqlConfig {
  const MySqlConfig({
    required this.host,
    required this.port,
    required this.secure,
    required this.userName,
    required this.password,
    required this.databaseName,
  });

  final String host;
  final int port;
  final bool secure;
  final String userName;
  final String password;
  final String databaseName;

  static MySqlConfig fromDotEnv() {
    final env = dotenv.env;
    return MySqlConfig(
      host: env['MYSQL_HOST'] ?? '',
      port: int.tryParse(env['MYSQL_PORT'] ?? '3306') ?? 3306,
      secure: (env['MYSQL_SECURE'] ?? 'true').toLowerCase() == 'true',
      userName: env['MYSQL_USER'] ?? '',
      password: env['MYSQL_PASSWORD'] ?? '',
      databaseName: env['MYSQL_DATABASE'] ?? '',
    );
  }

  List<String> missingKeys() {
    final missing = <String>[];
    if (host.trim().isEmpty) missing.add('MYSQL_HOST');
    if (userName.trim().isEmpty) missing.add('MYSQL_USER');
    if (password.trim().isEmpty) missing.add('MYSQL_PASSWORD');
    if (databaseName.trim().isEmpty) missing.add('MYSQL_DATABASE');
    return missing;
  }
}

class MySqlService {
  MySQLConnection? _conn;

  String _escapeIdentifier(String value) => value.replaceAll('`', '``');

  String _escapeSqlString(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  String _toSqlLiteral(dynamic value) {
    if (value == null) {
      return 'NULL';
    }
    if (value is num) {
      return value.toString();
    }
    if (value is bool) {
      return value ? '1' : '0';
    }
    if (value is List<int>) {
      final hex = value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      return '0x$hex';
    }

    return "'${_escapeSqlString(value.toString())}'";
  }

  Map<String, dynamic> _rowToMap(
    IResultSet result,
    dynamic row,
  ) {
    final map = <String, dynamic>{};
    for (final col in result.cols) {
      map[col.name] = row.typedColByName<dynamic>(col.name);
    }
    return map;
  }

  Future<void> connect(MySqlConfig config) async {
    if (_conn != null) {
      return;
    }

    final missing = config.missingKeys();
    if (missing.isNotEmpty) {
      throw ArgumentError('Missing MySQL config keys: ${missing.join(', ')}');
    }

    final connection = await MySQLConnection.createConnection(
      host: config.host,
      port: config.port,
      userName: config.userName,
      password: config.password,
      databaseName: config.databaseName,
      secure: config.secure,
    );

    _conn = connection;
    await connection.connect();
  }

  Future<void> disconnect() async {
    final conn = _conn;
    _conn = null;
    if (conn != null) {
      await conn.close();
    }
  }

  Future<void> insertSampleRow({String tableName = 'transactions'}) async {
    final params = MySqlInsertUtils.sampleTransactionRow();
    await insertTransactionRow(
      tableName: tableName,
      title: params['title'] as String,
      amount: (params['amount'] as num).toDouble(),
      category: params['category'] as String,
    );
  }

  Future<void> insertTransactionRow({
    required String tableName,
    required String title,
    required double amount,
    required String category,
  }) async {
    final conn = _conn;
    if (conn == null) {
      throw StateError(
          'MySQL connection is not initialized. Call connect() first.');
    }

    final query = MySqlInsertUtils.buildTransactionInsertQuery(tableName);
    final params = MySqlInsertUtils.buildTransactionParams(
      title: title,
      amount: amount,
      category: category,
    );

    await conn.execute(query, params);
  }

  Future<Map<String, dynamic>>executeReadQuery(String query) async 
  {
    final conn = _conn;
    if(conn == null) 
    {
      throw StateError(
          'MySQL connection is not initialized. Call connect() first.');
    }

    final result = await conn.execute(query);

    final rows = result.rows.map((row) {
      final map = <String, dynamic>{};
      for (final col in result.cols) {
        map[col.name] = row.typedColByName<dynamic>(col.name);
      }
      return map;
    }).toList();

    return {
      'rows': rows
    };
  }

  Future<void> executeWriteQuery(
    String query, [
    Map<String, dynamic>? params,
  ]) async {
    final conn = _conn;
    if (conn == null) {
      throw StateError(
          'MySQL connection is not initialized. Call connect() first.');
    }

    await conn.execute(query, params);
  }

  Future<List<String>> _loadTriggerDefinitions(MySQLConnection conn) async {
    final result = await conn.execute('SHOW TRIGGERS');
    final definitions = <String>[];

    String asString(dynamic value) => value?.toString().trim() ?? '';

    for (final row in result.rows) {
      final triggerMeta = _rowToMap(result, row);
      final triggerName = asString(triggerMeta['Trigger']);
      if (triggerName.isEmpty) {
        continue;
      }

      var timing = asString(triggerMeta['Timing']);
      var event = asString(triggerMeta['Event']);
      var table = asString(triggerMeta['Table']);
      var sql = asString(triggerMeta['Statement']);
      var definer = asString(triggerMeta['Definer']);

      final escapedTriggerName = _escapeIdentifier(triggerName);
      try {
        final createResult =
            await conn.execute('SHOW CREATE TRIGGER `$escapedTriggerName`');
        if (createResult.rows.isNotEmpty) {
          final createMeta = _rowToMap(createResult, createResult.rows.first);

          final createSql = asString(createMeta['SQL Original Statement']).isNotEmpty
              ? asString(createMeta['SQL Original Statement'])
              : asString(createMeta['Statement']).isNotEmpty
                  ? asString(createMeta['Statement'])
                  : asString(createMeta['Create Trigger']);

          if (createSql.isNotEmpty) {
            sql = createSql;
          }
          if (timing.isEmpty) {
            timing = asString(createMeta['Timing']);
          }
          if (event.isEmpty) {
            event = asString(createMeta['Event']);
          }
          if (table.isEmpty) {
            table = asString(createMeta['Table']);
          }
          if (definer.isEmpty) {
            definer = asString(createMeta['Definer']);
          }
        }
      } catch (_) {
        // Fallback to SHOW TRIGGERS metadata when SHOW CREATE TRIGGER varies by server.
      }

      if (sql.isEmpty || timing.isEmpty || event.isEmpty || table.isEmpty) {
        continue;
      }

      final definerClause = definer.isEmpty ? '' : 'DEFINER=$definer ';

      definitions.add(
        'CREATE ${definerClause}TRIGGER `${_escapeIdentifier(triggerName)}` '
        '${timing.toUpperCase()} ${event.toUpperCase()} '
        'ON `${_escapeIdentifier(table)}` FOR EACH ROW $sql;',
      );
    }

    return definitions;
  }

  Future<List<String>> _loadRoutineDefinitions(MySQLConnection conn) async {
    final result = await conn.execute(
      'SELECT ROUTINE_NAME, ROUTINE_TYPE FROM INFORMATION_SCHEMA.ROUTINES '
      'WHERE ROUTINE_SCHEMA = DATABASE() ORDER BY ROUTINE_TYPE, ROUTINE_NAME',
    );
    final definitions = <String>[];

    for (final row in result.rows) {
      final routineName = row.typedColByName<String>('ROUTINE_NAME')?.trim() ?? '';
      final routineType = row.typedColByName<String>('ROUTINE_TYPE')?.trim() ?? '';
      if (routineName.isEmpty || routineType.isEmpty) {
        continue;
      }

      final safeType = routineType.toUpperCase();
      final escapedRoutineName = _escapeIdentifier(routineName);
      final createResult = await conn.execute(
        'SHOW CREATE $safeType `$escapedRoutineName`',
      );
      if (createResult.rows.isEmpty) {
        continue;
      }

      final createRow = createResult.rows.first;
      final createColumnName = safeType == 'PROCEDURE'
          ? 'Create Procedure'
          : 'Create Function';
      final sql = createRow.typedColByName<String>(createColumnName) ?? '';
      if (sql.isNotEmpty) {
        definitions.add('$sql;');
      }
    }

    return definitions;
  }

  Future<List<String>> _loadEventDefinitions(MySQLConnection conn) async {
    final result = await conn.execute(
      'SELECT EVENT_NAME FROM INFORMATION_SCHEMA.EVENTS '
      'WHERE EVENT_SCHEMA = DATABASE() ORDER BY EVENT_NAME',
    );
    final definitions = <String>[];

    for (final row in result.rows) {
      final eventName = row.typedColByName<String>('EVENT_NAME')?.trim() ?? '';
      if (eventName.isEmpty) {
        continue;
      }

      final escapedEventName = _escapeIdentifier(eventName);
      final createResult =
          await conn.execute('SHOW CREATE EVENT `$escapedEventName`');
      if (createResult.rows.isEmpty) {
        continue;
      }

      final createRow = createResult.rows.first;
      final sql = createRow.typedColByName<String>('Create Event') ?? '';
      if (sql.isNotEmpty) {
        definitions.add('$sql;');
      }
    }

    return definitions;
  }

  Future<String> backupAllTablesToTxt({
    MySqlConfig? config,
    String? outputDirectoryPath,
    String fileNamePrefix = 'mysql_backup',
  }) async {
    var openedHere = false;

    if (_conn == null) {
      await connect(config ?? MySqlConfig.fromDotEnv());
      openedHere = true;
    }

    final conn = _conn;
    if (conn == null) {
      throw StateError(
        'MySQL connection is not initialized. Call connect() first.',
      );
    }

    try {
      final tablesResult = await conn.execute('SHOW TABLES');
      if (tablesResult.cols.isEmpty) {
        throw StateError('Could not read table names from the database.');
      }

      final tableNameColumn = tablesResult.cols.first.name;
      final encoder = const JsonEncoder.withIndent('  ');
      final buffer = StringBuffer()
        ..writeln('Database: ${config?.databaseName ?? MySqlConfig.fromDotEnv().databaseName}')
        ..writeln('Generated at: ${DateTime.now().toIso8601String()}')
        ..writeln();

      for (final tableRow in tablesResult.rows) {
        final tableName =
            tableRow.typedColByName<String>(tableNameColumn)?.trim() ?? '';
        if (tableName.isEmpty) {
          continue;
        }

        final escapedTableName = _escapeIdentifier(tableName);
        buffer
          ..writeln('===== TABLE: $tableName =====')
          ..writeln();

        final createTableResult =
            await conn.execute('SHOW CREATE TABLE `$escapedTableName`');

        if (createTableResult.rows.isNotEmpty) {
          final createTableRow = createTableResult.rows.first;
          final createSqlColumn = createTableResult.cols.length > 1
              ? createTableResult.cols.elementAt(1).name
              : createTableResult.cols.first.name;
          final createSql =
              createTableRow.typedColByName<String>(createSqlColumn) ?? '';

          buffer
            ..writeln('SCHEMA:')
            ..writeln(createSql)
            ..writeln();
        }

        final rowsResult =
            await conn.execute('SELECT * FROM `$escapedTableName`');

        buffer.writeln('ROWS:');
        if (rowsResult.rows.isEmpty) {
          buffer.writeln('(no rows)');
        } else {
          for (final row in rowsResult.rows) {
            buffer.writeln(encoder.convert(_rowToMap(rowsResult, row)));
          }
        }

        buffer.writeln();
      }

      final targetDirectory = outputDirectoryPath ??
          (await getApplicationDocumentsDirectory()).path;
      final directory = Directory(targetDirectory);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final filePath =
          '${directory.path}/$fileNamePrefix-$timestamp.txt';
      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file.path;
    } finally {
      if (openedHere) {
        await disconnect();
      }
    }
  }

  Future<String> backupDatabaseWithMysqldump({
    MySqlConfig? config,
    String? outputDirectoryPath,
    String fileNamePrefix = 'mysql_dump',
    bool includeRoutines = true,
    bool includeTriggers = true,
    bool includeEvents = true,
  }) async {
    final resolvedConfig = config ?? MySqlConfig.fromDotEnv();
    final missing = resolvedConfig.missingKeys();
    if (missing.isNotEmpty) {
      throw ArgumentError('Missing MySQL config keys: ${missing.join(', ')}');
    }

    var openedHere = false;
    if (_conn == null) {
      await connect(resolvedConfig);
      openedHere = true;
    }

    final conn = _conn;
    if (conn == null) {
      throw StateError(
        'MySQL connection is not initialized. Call connect() first.',
      );
    }

    try {
      final targetDirectory = outputDirectoryPath ??
          (await getApplicationDocumentsDirectory()).path;
      final directory = Directory(targetDirectory);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final filePath = '${directory.path}/$fileNamePrefix-$timestamp.sql';

      final tablesResult = await conn.execute('SHOW FULL TABLES WHERE Table_type = \'BASE TABLE\'');
      if (tablesResult.cols.isEmpty) {
        throw StateError('Could not read table names from the database.');
      }

      final tableNameColumn = tablesResult.cols.first.name;
      final buffer = StringBuffer()
        ..writeln('-- Database: ${resolvedConfig.databaseName}')
        ..writeln('-- Generated at: ${DateTime.now().toIso8601String()}')
        ..writeln('SET FOREIGN_KEY_CHECKS=0;')
        ..writeln();

      for (final tableRow in tablesResult.rows) {
        final tableName =
            tableRow.typedColByName<String>(tableNameColumn)?.trim() ?? '';
        if (tableName.isEmpty) {
          continue;
        }

        final escapedTableName = _escapeIdentifier(tableName);
        final createTableResult =
            await conn.execute('SHOW CREATE TABLE `$escapedTableName`');
        if (createTableResult.rows.isEmpty) {
          continue;
        }

        final createTableRow = createTableResult.rows.first;
        final createSqlColumn = createTableResult.cols.length > 1
            ? createTableResult.cols.elementAt(1).name
            : createTableResult.cols.first.name;
        final createSql =
            createTableRow.typedColByName<String>(createSqlColumn) ?? '';

        buffer
          ..writeln('-- ----------------------------')
          ..writeln('-- Table structure for `$tableName`')
          ..writeln('-- ----------------------------')
          ..writeln('DROP TABLE IF EXISTS `$escapedTableName`;')
          ..writeln('$createSql;')
          ..writeln();

        final rowsResult =
            await conn.execute('SELECT * FROM `$escapedTableName`');
        if (rowsResult.rows.isEmpty) {
          continue;
        }

        final columnNames = rowsResult.cols
            .map((col) => '`${_escapeIdentifier(col.name)}`')
            .join(', ');

        buffer
          ..writeln('-- Dumping data for table `$tableName`')
          ..writeln('INSERT INTO `$escapedTableName` ($columnNames) VALUES');

        final rowLines = <String>[];
        for (final row in rowsResult.rows) {
          final rowMap = _rowToMap(rowsResult, row);
          final values = rowsResult.cols
              .map((col) => _toSqlLiteral(rowMap[col.name]))
              .join(', ');
          rowLines.add('($values)');
        }

        buffer
          ..writeln('${rowLines.join(',\n')};')
          ..writeln();
      }

      if (includeTriggers) {
        final triggerDefinitions = await _loadTriggerDefinitions(conn);
        if (triggerDefinitions.isNotEmpty) {
          buffer
            ..writeln('-- Triggers')
            ..writeln('DELIMITER \$\$');
          for (final sql in triggerDefinitions) {
            buffer
              ..writeln('$sql \$\$')
              ..writeln();
          }
          buffer
            ..writeln('DELIMITER ;')
            ..writeln();
        }
      }

      if (includeRoutines) {
        final routineDefinitions = await _loadRoutineDefinitions(conn);
        if (routineDefinitions.isNotEmpty) {
          buffer
            ..writeln('-- Routines')
            ..writeln('DELIMITER \$\$');
          for (final sql in routineDefinitions) {
            buffer
              ..writeln('$sql \$\$')
              ..writeln();
          }
          buffer
            ..writeln('DELIMITER ;')
            ..writeln();
        }
      }

      if (includeEvents) {
        final eventDefinitions = await _loadEventDefinitions(conn);
        if (eventDefinitions.isNotEmpty) {
          buffer
            ..writeln('-- Events')
            ..writeln('DELIMITER \$\$');
          for (final sql in eventDefinitions) {
            buffer
              ..writeln('$sql \$\$')
              ..writeln();
          }
          buffer
            ..writeln('DELIMITER ;')
            ..writeln();
        }
      }

      buffer.writeln('SET FOREIGN_KEY_CHECKS=1;');

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file.path;
    } finally {
      if (openedHere) {
        await disconnect();
      }
    }
  }
}
