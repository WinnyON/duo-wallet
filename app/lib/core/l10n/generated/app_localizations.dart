import 'package:flutter/widgets.dart';

class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('en'), Locale('hu')];

  bool get isHu => locale.languageCode.startsWith('hu');

  String t(String en, String hu) => isHu ? hu : en;

  String get appName => 'Duo Wallet';
  String get dashboard => t('Dashboard', 'Áttekintés');
  String get transactions => t('Transactions', 'Tranzakciók');
  String get accounts => t('Accounts', 'Számlák');
  String get budgets => t('Budgets', 'Költségkeretek');
  String get stats => t('Statistics', 'Statisztikák');
  String get history => t('History', 'Előzmények');
  String get settleUp => t('Settle Up', 'Elszámolás');
  String get recurring => t('Recurring & Subscriptions', 'Ismétlődő és előfizetések');
  String get savings => t('Savings & Net Worth', 'Megtakarítás és vagyon');
  String get goals => t('Goals & Emergency Fund', 'Célok és vésztartalék');
  String get activity => t('Shared Activity', 'Közös aktivitás');
  String get exportBackup => t('Export & Backup', 'Exportálás és mentés');
  String get settings => t('Settings', 'Beállítások');
  String get viewTogether => t('Shared', 'Közös');
  String get viewIndividual => t('Personal', 'Saját');
  String get viewMyTotal => t('All Mine', 'Összes saját');
  String get quickAdd => t('Quick Add', 'Gyors rögzítés');
  String get expense => t('Expense', 'Kiadás');
  String get income => t('Income', 'Bevétel');
  String get transfer => t('Transfer', 'Átvezetés');
  String get commonAccount => t('Common Account', 'Közös számla');
  String get personalAccount => t('Personal Account', 'Saját számla');
  String get partnerPersonalAccount =>
      t("Partner's personal account", 'Partner saját számlája');
  String get privateBadge => t('Private', 'Privát');
  String get sharedBadge => t('Shared', 'Közös');
  String get netWorthMine => t('My Net Worth (Private)', 'Saját vagyon (Privát)');
  String get netWorthCommon => t('Common Net Worth', 'Közös vagyon');
  String get emergencyFund => t('Emergency Fund', 'Vésztartalék');
  String get interestCalculator => t('Interest Calculator', 'Kamatkalkulátor');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'hu'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
