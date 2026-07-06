import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mysql_client/mysql_client.dart';

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
}
