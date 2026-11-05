import 'package:intl/intl.dart';
import 'currency.dart';

class Money {
  /// Stored in minor units (100 minor units = 1 major unit for HUF, RON, EUR).
  final int amountMinor;
  final CurrencyCode currency;

  const Money(this.amountMinor, [this.currency = CurrencyCode.huf]);

  const Money.zero([this.currency = CurrencyCode.huf]) : amountMinor = 0;

  factory Money.fromMajor(num major,
          [CurrencyCode currency = CurrencyCode.huf]) =>
      Money((major * currency.minorFactor).round(), currency);

  double get majorAmount => amountMinor / currency.minorFactor;

  Money operator +(Money other) {
    assert(
        currency == other.currency, 'Cannot add different currencies directly');
    return Money(amountMinor + other.amountMinor, currency);
  }

  Money operator -(Money other) {
    assert(currency == other.currency,
        'Cannot subtract different currencies directly');
    return Money(amountMinor - other.amountMinor, currency);
  }

  String formatNumber({String locale = 'hu', bool compact = false}) {
    if (compact && majorAmount.abs() >= 100000) {
      return NumberFormat.compact(locale: locale).format(majorAmount);
    }
    final decimals = currency.displayDecimals;
    return NumberFormat.decimalPatternDigits(
            locale: locale, decimalDigits: decimals)
        .format(decimals == 0 ? majorAmount.round() : majorAmount);
  }

  String format({String locale = 'hu', bool hideAmounts = false}) {
    if (hideAmounts) return '•••• ${currency.symbol}';
    return _withCurrency(formatNumber(locale: locale), locale);
  }

  String _withCurrency(String number, String locale) =>
      locale.startsWith('hu') ||
              currency == CurrencyCode.huf ||
              currency == CurrencyCode.ron
          ? '$number ${currency.symbol}'
          : '${currency.symbol}$number';

  String formatCompact({String locale = 'hu', bool hideAmounts = false}) =>
      hideAmounts
          ? '•••• ${currency.symbol}'
          : _withCurrency(formatNumber(locale: locale, compact: true), locale);

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  @override
  String toString() => format();
}
