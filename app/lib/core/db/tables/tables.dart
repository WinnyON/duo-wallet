import '../../money/currency.dart';
import '../../money/fx_service.dart';

enum Scope {
  individual('individual'),
  together('together');

  final String value;
  const Scope(this.value);
  static Scope fromString(String? v) =>
      v == 'together' ? Scope.together : Scope.individual;
}

enum VisibilityLevel {
  private('private'),
  shared('shared');

  final String value;
  const VisibilityLevel(this.value);
  static VisibilityLevel fromString(String? v) =>
      v == 'shared' ? VisibilityLevel.shared : VisibilityLevel.private;
}

enum TxnKind {
  expense('expense'),
  income('income'),
  transfer('transfer');

  final String value;
  const TxnKind(this.value);
  static TxnKind fromString(String? v) => switch (v) {
    'income' => TxnKind.income,
    'transfer' => TxnKind.transfer,
    _ => TxnKind.expense,
  };
}

enum AccountType {
  cash('cash'),
  bank('bank'),
  savings('savings'),
  investment('investment'),
  deposit('deposit');

  final String value;
  const AccountType(this.value);
  static AccountType fromString(String? v) => switch (v) {
    'bank' => AccountType.bank,
    'savings' => AccountType.savings,
    'investment' => AccountType.investment,
    'deposit' => AccountType.deposit,
    _ => AccountType.cash,
  };
}

enum AccountOwnership {
  common('common'),
  personal('personal');

  final String value;
  const AccountOwnership(this.value);
  static AccountOwnership fromString(String? v) =>
      v == 'common' ? AccountOwnership.common : AccountOwnership.personal;
}

enum Compounding {
  daily('daily', 365),
  monthly('monthly', 12),
  quarterly('quarterly', 4),
  yearly('yearly', 1);

  final String value;
  final int periodsPerYear;
  const Compounding(this.value, this.periodsPerYear);

  static Compounding fromString(String? v) => switch (v) {
    'daily' => Compounding.daily,
    'quarterly' => Compounding.quarterly,
    'yearly' => Compounding.yearly,
    _ => Compounding.monthly,
  };
}

class Household {
  final String id;
  final String name;
  final CurrencyCode baseCurrency;
  final int defaultSplitPct;
  final String? inviteCode;
  final int emergencyFundMonths;
  final DateTime createdAt;

  const Household({
    required this.id,
    required this.name,
    this.baseCurrency = CurrencyCode.huf,
    this.defaultSplitPct = 50,
    this.inviteCode,
    this.emergencyFundMonths = 6,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'base_currency': baseCurrency.code,
    'default_split_pct': defaultSplitPct,
    'invite_code': inviteCode,
    'emergency_fund_months': emergencyFundMonths,
    'created_at': createdAt.toIso8601String(),
  };

  factory Household.fromJson(Map<String, dynamic> j) => Household(
    id: j['id'] as String,
    name: j['name'] as String,
    baseCurrency: CurrencyCode.fromCode(j['base_currency'] as String? ?? 'HUF'),
    defaultSplitPct: (j['default_split_pct'] as num?)?.toInt() ?? 50,
    inviteCode: j['invite_code'] as String?,
    emergencyFundMonths: (j['emergency_fund_months'] as num?)?.toInt() ?? 6,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

class Profile {
  final String id;
  final String? householdId;
  final String displayName;
  final String color;
  final String locale;
  final int? monthlyCommonContributionMinor;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    this.householdId,
    required this.displayName,
    this.color = '#4F46E5',
    this.locale = 'hu',
    this.monthlyCommonContributionMinor,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'display_name': displayName,
    'color': color,
    'locale': locale,
    'monthly_common_contribution_minor': monthlyCommonContributionMinor,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    householdId: j['household_id'] as String?,
    displayName: j['display_name'] as String? ?? '',
    color: j['color'] as String? ?? '#4F46E5',
    locale: j['locale'] as String? ?? 'hu',
    monthlyCommonContributionMinor: (j['monthly_common_contribution_minor'] as num?)?.toInt(),
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
  );
}

class Account {
  final String id;
  final String householdId;
  final String name;
  final AccountType type;
  final AccountOwnership ownership;
  final String? ownerId;
  final CurrencyCode currency;
  final int openingBalanceMinor;
  final DateTime openingDate;
  final double? interestRatePct;
  final Compounding? compounding;
  final double interestTaxPct;
  final DateTime? maturityDate;
  final bool autoPostInterest;
  final bool includeInNetWorth;
  final String? icon;
  final String? color;
  final bool archived;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Account({
    required this.id,
    required this.householdId,
    required this.name,
    required this.type,
    required this.ownership,
    this.ownerId,
    this.currency = CurrencyCode.huf,
    this.openingBalanceMinor = 0,
    required this.openingDate,
    this.interestRatePct,
    this.compounding,
    this.interestTaxPct = 0,
    this.maturityDate,
    this.autoPostInterest = false,
    this.includeInNetWorth = true,
    this.icon,
    this.color,
    this.archived = false,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isCommon => ownership == AccountOwnership.common;

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'name': name,
    'type': type.value,
    'ownership': ownership.value,
    'owner_id': ownerId,
    'currency': currency.code,
    'opening_balance_minor': openingBalanceMinor,
    'opening_date': openingDate.toIso8601String().split('T').first,
    'interest_rate_pct': interestRatePct,
    'compounding': compounding?.value,
    'interest_tax_pct': interestTaxPct,
    'maturity_date': maturityDate?.toIso8601String().split('T').first,
    'auto_post_interest': autoPostInterest,
    'include_in_net_worth': includeInNetWorth,
    'icon': icon,
    'color': color,
    'archived': archived,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    name: j['name'] as String,
    type: AccountType.fromString(j['type'] as String?),
    ownership: AccountOwnership.fromString(j['ownership'] as String?),
    ownerId: j['owner_id'] as String?,
    currency: CurrencyCode.fromCode(j['currency'] as String? ?? 'HUF'),
    openingBalanceMinor: (j['opening_balance_minor'] as num?)?.toInt() ?? 0,
    openingDate: DateTime.tryParse(j['opening_date'] as String? ?? '') ?? DateTime.now(),
    interestRatePct: (j['interest_rate_pct'] as num?)?.toDouble(),
    compounding: j['compounding'] != null ? Compounding.fromString(j['compounding'] as String?) : null,
    interestTaxPct: (j['interest_tax_pct'] as num?)?.toDouble() ?? 0,
    maturityDate: j['maturity_date'] != null ? DateTime.tryParse(j['maturity_date'] as String) : null,
    autoPostInterest: j['auto_post_interest'] as bool? ?? false,
    includeInNetWorth: j['include_in_net_worth'] as bool? ?? true,
    icon: j['icon'] as String?,
    color: j['color'] as String?,
    archived: j['archived'] as bool? ?? false,
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: j['deleted_at'] != null ? DateTime.tryParse(j['deleted_at'] as String) : null,
  );
}

class Txn {
  final String id;
  final String householdId;
  final TxnKind kind;
  final Scope scope;
  final VisibilityLevel visibility;
  final DateTime occurredOn;
  final int amountMinor;
  final CurrencyCode currency;
  final double fxRateToBase;
  final FxSource fxSource;
  final int baseAmountMinor;
  final String paidBy;
  final bool paidFromCommon;
  /// Note: No FK constraint locally; may point to partner's private account.
  final String accountId;
  final int accountAmountMinor;
  final String? toAccountId;
  final int? toAccountAmountMinor;
  final bool isContribution;
  final String? categoryId;
  final String? merchant;
  final String? note;
  final String? recurringRuleId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final Map<String, int> baseShares; // userId -> share_base_minor
  final Map<String, int> shares; // userId -> share_minor
  final List<String> tags;

  const Txn({
    required this.id,
    required this.householdId,
    required this.kind,
    required this.scope,
    required this.visibility,
    required this.occurredOn,
    required this.amountMinor,
    this.currency = CurrencyCode.huf,
    this.fxRateToBase = 1.0,
    this.fxSource = FxSource.ecb,
    required this.baseAmountMinor,
    required this.paidBy,
    required this.paidFromCommon,
    required this.accountId,
    required this.accountAmountMinor,
    this.toAccountId,
    this.toAccountAmountMinor,
    this.isContribution = false,
    this.categoryId,
    this.merchant,
    this.note,
    this.recurringRuleId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.baseShares = const {},
    this.shares = const {},
    this.tags = const [],
  });

  int get baseAmount => baseAmountMinor;

  Txn copyWith({
    String? id,
    Scope? scope,
    VisibilityLevel? visibility,
    DateTime? occurredOn,
    int? amountMinor,
    CurrencyCode? currency,
    double? fxRateToBase,
    int? baseAmountMinor,
    String? paidBy,
    bool? paidFromCommon,
    String? accountId,
    int? accountAmountMinor,
    String? categoryId,
    String? merchant,
    String? note,
    DateTime? updatedAt,
    DateTime? deletedAt,
    Map<String, int>? baseShares,
    Map<String, int>? shares,
    List<String>? tags,
  }) => Txn(
    id: id ?? this.id,
    householdId: householdId,
    kind: kind,
    scope: scope ?? this.scope,
    visibility: visibility ?? this.visibility,
    occurredOn: occurredOn ?? this.occurredOn,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    fxRateToBase: fxRateToBase ?? this.fxRateToBase,
    fxSource: fxSource,
    baseAmountMinor: baseAmountMinor ?? this.baseAmountMinor,
    paidBy: paidBy ?? this.paidBy,
    paidFromCommon: paidFromCommon ?? this.paidFromCommon,
    accountId: accountId ?? this.accountId,
    accountAmountMinor: accountAmountMinor ?? this.accountAmountMinor,
    toAccountId: toAccountId,
    toAccountAmountMinor: toAccountAmountMinor,
    isContribution: isContribution,
    categoryId: categoryId ?? this.categoryId,
    merchant: merchant ?? this.merchant,
    note: note ?? this.note,
    recurringRuleId: recurringRuleId,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    baseShares: baseShares ?? this.baseShares,
    shares: shares ?? this.shares,
    tags: tags ?? this.tags,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'kind': kind.value,
    'scope': scope.value,
    'visibility': visibility.value,
    'occurred_on': occurredOn.toIso8601String().split('T').first,
    'amount_minor': amountMinor,
    'currency': currency.code,
    'fx_rate_to_base': fxRateToBase,
    'fx_source': fxSource.value,
    'base_amount_minor': baseAmountMinor,
    'paid_by': paidBy,
    'paid_from_common': paidFromCommon,
    'account_id': accountId,
    'account_amount_minor': accountAmountMinor,
    'to_account_id': toAccountId,
    'to_account_amount_minor': toAccountAmountMinor,
    'is_contribution': isContribution,
    'category_id': categoryId,
    'merchant': merchant,
    'note': note,
    'recurring_rule_id': recurringRuleId,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
    'base_shares': baseShares,
    'shares': shares,
    'tags': tags,
  };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    kind: TxnKind.fromString(j['kind'] as String?),
    scope: Scope.fromString(j['scope'] as String?),
    visibility: VisibilityLevel.fromString(j['visibility'] as String?),
    occurredOn: DateTime.tryParse(j['occurred_on'] as String? ?? '') ?? DateTime.now(),
    amountMinor: (j['amount_minor'] as num).toInt(),
    currency: CurrencyCode.fromCode(j['currency'] as String? ?? 'HUF'),
    fxRateToBase: (j['fx_rate_to_base'] as num?)?.toDouble() ?? 1.0,
    fxSource: FxSource.fromString(j['fx_source'] as String?),
    baseAmountMinor: (j['base_amount_minor'] as num).toInt(),
    paidBy: j['paid_by'] as String,
    paidFromCommon: j['paid_from_common'] as bool? ?? false,
    accountId: j['account_id'] as String,
    accountAmountMinor: (j['account_amount_minor'] as num).toInt(),
    toAccountId: j['to_account_id'] as String?,
    toAccountAmountMinor: (j['to_account_amount_minor'] as num?)?.toInt(),
    isContribution: j['is_contribution'] as bool? ?? false,
    categoryId: j['category_id'] as String?,
    merchant: j['merchant'] as String?,
    note: j['note'] as String?,
    recurringRuleId: j['recurring_rule_id'] as String?,
    createdBy: j['created_by'] as String,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: j['deleted_at'] != null ? DateTime.tryParse(j['deleted_at'] as String) : null,
    baseShares: (j['base_shares'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? const {},
    shares: (j['shares'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? const {},
    tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );
}

class Category {
  final String id;
  final String householdId;
  final String nameEn;
  final String nameHu;
  final String kind; // 'expense' | 'income'
  final String icon;
  final String color;
  final bool isEssential;
  final String? parentId;
  final int sortOrder;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Category({
    required this.id,
    required this.householdId,
    required this.nameEn,
    required this.nameHu,
    this.kind = 'expense',
    this.icon = 'category',
    this.color = '#6366F1',
    this.isEssential = false,
    this.parentId,
    this.sortOrder = 0,
    required this.updatedAt,
    this.deletedAt,
  });

  String localizedName(String locale) => locale.startsWith('hu') ? nameHu : nameEn;

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'name_en': nameEn,
    'name_hu': nameHu,
    'kind': kind,
    'icon': icon,
    'color': color,
    'is_essential': isEssential,
    'parent_id': parentId,
    'sort_order': sortOrder,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    nameEn: j['name_en'] as String? ?? '',
    nameHu: j['name_hu'] as String? ?? '',
    kind: j['kind'] as String? ?? 'expense',
    icon: j['icon'] as String? ?? 'category',
    color: j['color'] as String? ?? '#6366F1',
    isEssential: j['is_essential'] as bool? ?? false,
    parentId: j['parent_id'] as String?,
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: j['deleted_at'] != null ? DateTime.tryParse(j['deleted_at'] as String) : null,
  );
}

class Budget {
  final String id;
  final String householdId;
  final Scope scope; // together = shared; individual = personal ("My" budget -> My Total)
  final String? ownerId;
  final String? categoryId; // null = total monthly budget
  final int amountMinor;
  final bool rollover;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Budget({
    required this.id,
    required this.householdId,
    required this.scope,
    this.ownerId,
    this.categoryId,
    required this.amountMinor,
    this.rollover = false,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'scope': scope.value,
    'owner_id': ownerId,
    'category_id': categoryId,
    'amount_minor': amountMinor,
    'rollover': rollover,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    scope: Scope.fromString(j['scope'] as String?),
    ownerId: j['owner_id'] as String?,
    categoryId: j['category_id'] as String?,
    amountMinor: (j['amount_minor'] as num).toInt(),
    rollover: j['rollover'] as bool? ?? false,
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: j['deleted_at'] != null ? DateTime.tryParse(j['deleted_at'] as String) : null,
  );
}

class Settlement {
  final String id;
  final String householdId;
  final String fromUser;
  final String toUser;
  final int amountMinor;
  final CurrencyCode currency;
  final int baseAmountMinor;
  final bool fromConfirmed;
  final bool toConfirmed;
  final String? rejectedBy;
  final String? note;
  final String createdBy;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Settlement({
    required this.id,
    required this.householdId,
    required this.fromUser,
    required this.toUser,
    required this.amountMinor,
    this.currency = CurrencyCode.huf,
    required this.baseAmountMinor,
    this.fromConfirmed = false,
    this.toConfirmed = false,
    this.rejectedBy,
    this.note,
    required this.createdBy,
    required this.updatedAt,
    this.deletedAt,
  });

  String get status {
    if (rejectedBy != null) return 'rejected';
    return (fromConfirmed && toConfirmed) ? 'confirmed' : 'pending';
  }

  bool get isConfirmed => fromConfirmed && toConfirmed && rejectedBy == null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'from_user': fromUser,
    'to_user': toUser,
    'amount_minor': amountMinor,
    'currency': currency.code,
    'base_amount_minor': baseAmountMinor,
    'from_confirmed': fromConfirmed,
    'to_confirmed': toConfirmed,
    'rejected_by': rejectedBy,
    'note': note,
    'created_by': createdBy,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Settlement.fromJson(Map<String, dynamic> j) => Settlement(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    fromUser: j['from_user'] as String,
    toUser: j['to_user'] as String,
    amountMinor: (j['amount_minor'] as num).toInt(),
    currency: CurrencyCode.fromCode(j['currency'] as String? ?? 'HUF'),
    baseAmountMinor: (j['base_amount_minor'] as num).toInt(),
    fromConfirmed: j['from_confirmed'] as bool? ?? false,
    toConfirmed: j['to_confirmed'] as bool? ?? false,
    rejectedBy: j['rejected_by'] as String?,
    note: j['note'] as String?,
    createdBy: j['created_by'] as String,
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: j['deleted_at'] != null ? DateTime.tryParse(j['deleted_at'] as String) : null,
  );
}

class SettlementPosting {
  final String settlementId;
  final String userId;
  final String accountId;
  final int amountMinor; // negative = money out, positive = money in

  const SettlementPosting({
    required this.settlementId,
    required this.userId,
    required this.accountId,
    required this.amountMinor,
  });

  Map<String, dynamic> toJson() => {
    'settlement_id': settlementId,
    'user_id': userId,
    'account_id': accountId,
    'amount_minor': amountMinor,
  };

  factory SettlementPosting.fromJson(Map<String, dynamic> j) => SettlementPosting(
    settlementId: j['settlement_id'] as String,
    userId: j['user_id'] as String,
    accountId: j['account_id'] as String,
    amountMinor: (j['amount_minor'] as num).toInt(),
  );
}

class RecurringRule {
  final String id;
  final String householdId;
  final String title;
  final TxnKind kind;
  final Scope scope;
  final VisibilityLevel visibility;
  final int amountMinor;
  final CurrencyCode currency;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String frequency; // 'weekly' | 'monthly' | 'yearly'
  final DateTime nextDueOn;
  final bool autoCreate;
  final bool isSubscription;
  final int splitPctCreator;
  final String createdBy;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const RecurringRule({
    required this.id,
    required this.householdId,
    required this.title,
    this.kind = TxnKind.expense,
    this.scope = Scope.together,
    this.visibility = VisibilityLevel.shared,
    required this.amountMinor,
    this.currency = CurrencyCode.huf,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.frequency = 'monthly',
    required this.nextDueOn,
    this.autoCreate = true,
    this.isSubscription = true,
    this.splitPctCreator = 50,
    required this.createdBy,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'title': title,
    'kind': kind.value,
    'scope': scope.value,
    'visibility': visibility.value,
    'amount_minor': amountMinor,
    'currency': currency.code,
    'account_id': accountId,
    'to_account_id': toAccountId,
    'category_id': categoryId,
    'frequency': frequency,
    'next_due_on': nextDueOn.toIso8601String().split('T').first,
    'auto_create': autoCreate,
    'is_subscription': isSubscription,
    'split_pct_creator': splitPctCreator,
    'created_by': createdBy,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory RecurringRule.fromJson(Map<String, dynamic> j) => RecurringRule(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    title: j['title'] as String,
    kind: TxnKind.fromString(j['kind'] as String?),
    scope: Scope.fromString(j['scope'] as String?),
    visibility: VisibilityLevel.fromString(j['visibility'] as String?),
    amountMinor: (j['amount_minor'] as num).toInt(),
    currency: CurrencyCode.fromCode(j['currency'] as String? ?? 'HUF'),
    accountId: j['account_id'] as String,
    toAccountId: j['to_account_id'] as String?,
    categoryId: j['category_id'] as String?,
    frequency: j['frequency'] as String? ?? 'monthly',
    nextDueOn: DateTime.tryParse(j['next_due_on'] as String? ?? '') ?? DateTime.now(),
    autoCreate: j['auto_create'] as bool? ?? true,
    isSubscription: j['is_subscription'] as bool? ?? true,
    splitPctCreator: (j['split_pct_creator'] as num?)?.toInt() ?? 50,
    createdBy: j['created_by'] as String,
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: j['deleted_at'] != null ? DateTime.tryParse(j['deleted_at'] as String) : null,
  );
}

class AccountValuation {
  final String id;
  final String accountId;
  final DateTime valuedOn;
  final int valueMinor;
  final String? note;
  final DateTime createdAt;

  const AccountValuation({
    required this.id,
    required this.accountId,
    required this.valuedOn,
    required this.valueMinor,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'account_id': accountId,
    'valued_on': valuedOn.toIso8601String().split('T').first,
    'value_minor': valueMinor,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };

  factory AccountValuation.fromJson(Map<String, dynamic> j) => AccountValuation(
    id: j['id'] as String,
    accountId: j['account_id'] as String,
    valuedOn: DateTime.tryParse(j['valued_on'] as String? ?? '') ?? DateTime.now(),
    valueMinor: (j['value_minor'] as num).toInt(),
    note: j['note'] as String?,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

class Goal {
  final String id;
  final String householdId;
  final String name;
  final String type; // 'savings' | 'emergency_fund'
  final String scope; // 'shared' | 'personal'
  final String? ownerId;
  final int targetAmountMinor;
  final CurrencyCode currency;
  final DateTime? deadline;
  final int savedAmountMinor;
  final double annualInterestRatePct;
  final List<String> linkedAccountIds;
  final Map<String, int> contributionsByUser;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Goal({
    required this.id,
    required this.householdId,
    required this.name,
    this.type = 'savings',
    this.scope = 'shared',
    this.ownerId,
    required this.targetAmountMinor,
    this.currency = CurrencyCode.huf,
    this.deadline,
    this.savedAmountMinor = 0,
    this.annualInterestRatePct = 0.0,
    this.linkedAccountIds = const [],
    this.contributionsByUser = const {},
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isShared => scope == 'shared';
  bool get isEmergencyFund => type == 'emergency_fund';

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'name': name,
    'type': type,
    'scope': scope,
    'owner_id': ownerId,
    'target_amount_minor': targetAmountMinor,
    'currency': currency.code,
    'deadline': deadline?.toIso8601String().split('T').first,
    'saved_amount_minor': savedAmountMinor,
    'annual_interest_rate_pct': annualInterestRatePct,
    'linked_account_ids': linkedAccountIds,
    'contributions_by_user': contributionsByUser,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    name: j['name'] as String,
    type: j['type'] as String? ?? 'savings',
    scope: j['scope'] as String? ?? 'shared',
    ownerId: j['owner_id'] as String?,
    targetAmountMinor: (j['target_amount_minor'] as num).toInt(),
    currency: CurrencyCode.fromCode(j['currency'] as String? ?? 'HUF'),
    deadline: j['deadline'] != null ? DateTime.tryParse(j['deadline'] as String) : null,
    savedAmountMinor: (j['saved_amount_minor'] as num?)?.toInt() ?? 0,
    annualInterestRatePct: (j['annual_interest_rate_pct'] as num?)?.toDouble() ?? 0.0,
    linkedAccountIds: (j['linked_account_ids'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    contributionsByUser: (j['contributions_by_user'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
        const {},
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: j['deleted_at'] != null ? DateTime.tryParse(j['deleted_at'] as String) : null,
  );
}

class ActivityEvent {
  final String id;
  final String householdId;
  final String actorId;
  final String eventType; // 'expense_added', 'settlement_proposed', 'settlement_confirmed', 'goal_milestone', 'contribution_added'
  final String summaryEn;
  final String summaryHu;
  final int? amountMinor;
  final CurrencyCode currency;
  final DateTime createdAt;

  const ActivityEvent({
    required this.id,
    required this.householdId,
    required this.actorId,
    required this.eventType,
    required this.summaryEn,
    required this.summaryHu,
    this.amountMinor,
    this.currency = CurrencyCode.huf,
    required this.createdAt,
  });

  String localizedSummary(String locale) =>
      locale.startsWith('hu') ? summaryHu : summaryEn;

  Map<String, dynamic> toJson() => {
    'id': id,
    'household_id': householdId,
    'actor_id': actorId,
    'event_type': eventType,
    'summary_en': summaryEn,
    'summary_hu': summaryHu,
    'amount_minor': amountMinor,
    'currency': currency.code,
    'created_at': createdAt.toIso8601String(),
  };

  factory ActivityEvent.fromJson(Map<String, dynamic> j) => ActivityEvent(
    id: j['id'] as String,
    householdId: j['household_id'] as String,
    actorId: j['actor_id'] as String,
    eventType: j['event_type'] as String,
    summaryEn: j['summary_en'] as String? ?? '',
    summaryHu: j['summary_hu'] as String? ?? '',
    amountMinor: (j['amount_minor'] as num?)?.toInt(),
    currency: CurrencyCode.fromCode(j['currency'] as String? ?? 'HUF'),
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

class OutboxEntry {
  final String id;
  final String tableName;
  final String recordId;
  final String operation; // 'upsert' | 'soft_delete'
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const OutboxEntry({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.operation,
    required this.payload,
    required this.createdAt,
  });
}
