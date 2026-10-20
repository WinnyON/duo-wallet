enum CurrencyCode {
  huf('HUF', 'Ft', 0),
  ron('RON', 'lei', 2),
  eur('EUR', '€', 2);

  final String code;
  final String symbol;
  final int displayDecimals;

  const CurrencyCode(this.code, this.symbol, this.displayDecimals);

  /// All currencies are stored in ISO minor units (2 decimal places = * 100).
  int get minorFactor => 100;

  static CurrencyCode fromCode(String raw) => switch (raw.toUpperCase().trim()) {
    'RON' => CurrencyCode.ron,
    'EUR' => CurrencyCode.eur,
    _ => CurrencyCode.huf,
  };
}
