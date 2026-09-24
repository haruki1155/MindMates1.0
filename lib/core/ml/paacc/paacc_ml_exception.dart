class PaaccMlException implements Exception {
  final String message;

  const PaaccMlException(this.message);

  @override
  String toString() => 'PaaccMlException: $message';
}
