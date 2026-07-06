class MySqlInsertUtils {
  const MySqlInsertUtils._();

  static String safeIdentifier(String raw) {
    final trimmed = raw.trim();
    final valid = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    if (!valid.hasMatch(trimmed)) {
      throw ArgumentError(
        'Invalid SQL identifier: "$raw". Use only letters, numbers, and underscores.',
      );
    }
    return trimmed;
  }

  static String buildTransactionInsertQuery(String tableName) {
    final safeTable = safeIdentifier(tableName);
    return '''
INSERT INTO $safeTable (title, amount, category, created_at)
VALUES (:title, :amount, :category, NOW())
''';
  }

  static Map<String, dynamic> sampleTransactionRow() {
    return {
      'title': 'Sample Grocery Purchase',
      'amount': 249.75,
      'category': 'Food',
    };
  }

  static Map<String, dynamic> buildTransactionParams({
    required String title,
    required double amount,
    required String category,
  }) {
    return {
      'title': title.trim(),
      'amount': amount,
      'category': category.trim(),
    };
  }

  static double parseAmount(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed == null) {
      throw ArgumentError('Amount must be a valid number.');
    }
    return parsed;
  }
}
