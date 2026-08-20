// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _passwordHashMeta = const VerificationMeta(
    'passwordHash',
  );
  @override
  late final GeneratedColumn<String> passwordHash = GeneratedColumn<String>(
    'password_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<UserRole, String> role =
      GeneratedColumn<String>(
        'role',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('admin'),
      ).withConverter<UserRole>($UsersTable.$converterrole);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    email,
    passwordHash,
    role,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('password_hash')) {
      context.handle(
        _passwordHashMeta,
        passwordHash.isAcceptableOrUnknown(
          data['password_hash']!,
          _passwordHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_passwordHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      passwordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_hash'],
      )!,
      role: $UsersTable.$converterrole.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}role'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<UserRole, String, String> $converterrole =
      const EnumNameConverter<UserRole>(UserRole.values);
}

class User extends DataClass implements Insertable<User> {
  final int id;
  final String name;
  final String email;
  final String passwordHash;
  final UserRole role;
  final DateTime createdAt;
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.role,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['email'] = Variable<String>(email);
    map['password_hash'] = Variable<String>(passwordHash);
    {
      map['role'] = Variable<String>($UsersTable.$converterrole.toSql(role));
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      name: Value(name),
      email: Value(email),
      passwordHash: Value(passwordHash),
      role: Value(role),
      createdAt: Value(createdAt),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      email: serializer.fromJson<String>(json['email']),
      passwordHash: serializer.fromJson<String>(json['passwordHash']),
      role: $UsersTable.$converterrole.fromJson(
        serializer.fromJson<String>(json['role']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'email': serializer.toJson<String>(email),
      'passwordHash': serializer.toJson<String>(passwordHash),
      'role': serializer.toJson<String>(
        $UsersTable.$converterrole.toJson(role),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  User copyWith({
    int? id,
    String? name,
    String? email,
    String? passwordHash,
    UserRole? role,
    DateTime? createdAt,
  }) => User(
    id: id ?? this.id,
    name: name ?? this.name,
    email: email ?? this.email,
    passwordHash: passwordHash ?? this.passwordHash,
    role: role ?? this.role,
    createdAt: createdAt ?? this.createdAt,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      email: data.email.present ? data.email.value : this.email,
      passwordHash: data.passwordHash.present
          ? data.passwordHash.value
          : this.passwordHash,
      role: data.role.present ? data.role.value : this.role,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('email: $email, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('role: $role, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, email, passwordHash, role, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.id == this.id &&
          other.name == this.name &&
          other.email == this.email &&
          other.passwordHash == this.passwordHash &&
          other.role == this.role &&
          other.createdAt == this.createdAt);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> email;
  final Value<String> passwordHash;
  final Value<UserRole> role;
  final Value<DateTime> createdAt;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.email = const Value.absent(),
    this.passwordHash = const Value.absent(),
    this.role = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  UsersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String email,
    required String passwordHash,
    this.role = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name),
       email = Value(email),
       passwordHash = Value(passwordHash);
  static Insertable<User> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? email,
    Expression<String>? passwordHash,
    Expression<String>? role,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (passwordHash != null) 'password_hash': passwordHash,
      if (role != null) 'role': role,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  UsersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? email,
    Value<String>? passwordHash,
    Value<UserRole>? role,
    Value<DateTime>? createdAt,
  }) {
    return UsersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (passwordHash.present) {
      map['password_hash'] = Variable<String>(passwordHash.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(
        $UsersTable.$converterrole.toSql(role.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('email: $email, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('role: $role, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AppSessionsTable extends AppSessions
    with TableInfo<$AppSessionsTable, AppSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<int> userId = GeneratedColumn<int>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _signedInAtMeta = const VerificationMeta(
    'signedInAt',
  );
  @override
  late final GeneratedColumn<DateTime> signedInAt = GeneratedColumn<DateTime>(
    'signed_in_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, userId, signedInAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('signed_in_at')) {
      context.handle(
        _signedInAtMeta,
        signedInAt.isAcceptableOrUnknown(
          data['signed_in_at']!,
          _signedInAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_id'],
      ),
      signedInAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}signed_in_at'],
      ),
    );
  }

  @override
  $AppSessionsTable createAlias(String alias) {
    return $AppSessionsTable(attachedDatabase, alias);
  }
}

class AppSession extends DataClass implements Insertable<AppSession> {
  final int id;

  /// Null when signed out. Cascades so deleting the account ends the session
  /// rather than leaving a row pointing at a user who no longer exists.
  final int? userId;
  final DateTime? signedInAt;
  const AppSession({required this.id, this.userId, this.signedInAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<int>(userId);
    }
    if (!nullToAbsent || signedInAt != null) {
      map['signed_in_at'] = Variable<DateTime>(signedInAt);
    }
    return map;
  }

  AppSessionsCompanion toCompanion(bool nullToAbsent) {
    return AppSessionsCompanion(
      id: Value(id),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      signedInAt: signedInAt == null && nullToAbsent
          ? const Value.absent()
          : Value(signedInAt),
    );
  }

  factory AppSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSession(
      id: serializer.fromJson<int>(json['id']),
      userId: serializer.fromJson<int?>(json['userId']),
      signedInAt: serializer.fromJson<DateTime?>(json['signedInAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'userId': serializer.toJson<int?>(userId),
      'signedInAt': serializer.toJson<DateTime?>(signedInAt),
    };
  }

  AppSession copyWith({
    int? id,
    Value<int?> userId = const Value.absent(),
    Value<DateTime?> signedInAt = const Value.absent(),
  }) => AppSession(
    id: id ?? this.id,
    userId: userId.present ? userId.value : this.userId,
    signedInAt: signedInAt.present ? signedInAt.value : this.signedInAt,
  );
  AppSession copyWithCompanion(AppSessionsCompanion data) {
    return AppSession(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      signedInAt: data.signedInAt.present
          ? data.signedInAt.value
          : this.signedInAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSession(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('signedInAt: $signedInAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, userId, signedInAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSession &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.signedInAt == this.signedInAt);
}

class AppSessionsCompanion extends UpdateCompanion<AppSession> {
  final Value<int> id;
  final Value<int?> userId;
  final Value<DateTime?> signedInAt;
  const AppSessionsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.signedInAt = const Value.absent(),
  });
  AppSessionsCompanion.insert({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.signedInAt = const Value.absent(),
  });
  static Insertable<AppSession> custom({
    Expression<int>? id,
    Expression<int>? userId,
    Expression<DateTime>? signedInAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (signedInAt != null) 'signed_in_at': signedInAt,
    });
  }

  AppSessionsCompanion copyWith({
    Value<int>? id,
    Value<int?>? userId,
    Value<DateTime?>? signedInAt,
  }) {
    return AppSessionsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      signedInAt: signedInAt ?? this.signedInAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<int>(userId.value);
    }
    if (signedInAt.present) {
      map['signed_in_at'] = Variable<DateTime>(signedInAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSessionsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('signedInAt: $signedInAt')
          ..write(')'))
        .toString();
  }
}

class $GymSettingsTable extends GymSettings
    with TableInfo<$GymSettingsTable, GymSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GymSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _gymNameMeta = const VerificationMeta(
    'gymName',
  );
  @override
  late final GeneratedColumn<String> gymName = GeneratedColumn<String>(
    'gym_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Rich Man Fitness'),
  );
  static const VerificationMeta _logoPathMeta = const VerificationMeta(
    'logoPath',
  );
  @override
  late final GeneratedColumn<String> logoPath = GeneratedColumn<String>(
    'logo_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _whatsappPhoneMeta = const VerificationMeta(
    'whatsappPhone',
  );
  @override
  late final GeneratedColumn<String> whatsappPhone = GeneratedColumn<String>(
    'whatsapp_phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _openingHoursMeta = const VerificationMeta(
    'openingHours',
  );
  @override
  late final GeneratedColumn<String> openingHours = GeneratedColumn<String>(
    'opening_hours',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('PKR'),
  );
  static const VerificationMeta _receiptPrefixMeta = const VerificationMeta(
    'receiptPrefix',
  );
  @override
  late final GeneratedColumn<String> receiptPrefix = GeneratedColumn<String>(
    'receipt_prefix',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('RMF'),
  );
  static const VerificationMeta _receiptFooterMessageMeta =
      const VerificationMeta('receiptFooterMessage');
  @override
  late final GeneratedColumn<String> receiptFooterMessage =
      GeneratedColumn<String>(
        'receipt_footer_message',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(
          'Thank you for choosing Rich Man Fitness.',
        ),
      );
  @override
  late final GeneratedColumnWithTypeConverter<WhatsAppProviderKind, String>
  whatsappProvider =
      GeneratedColumn<String>(
        'whatsapp_provider',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('mock'),
      ).withConverter<WhatsAppProviderKind>(
        $GymSettingsTable.$converterwhatsappProvider,
      );
  static const VerificationMeta _whatsappPhoneNumberIdMeta =
      const VerificationMeta('whatsappPhoneNumberId');
  @override
  late final GeneratedColumn<String> whatsappPhoneNumberId =
      GeneratedColumn<String>(
        'whatsapp_phone_number_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _whatsappAccessTokenMeta =
      const VerificationMeta('whatsappAccessToken');
  @override
  late final GeneratedColumn<String> whatsappAccessToken =
      GeneratedColumn<String>(
        'whatsapp_access_token',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _whatsappBusinessAccountIdMeta =
      const VerificationMeta('whatsappBusinessAccountId');
  @override
  late final GeneratedColumn<String> whatsappBusinessAccountId =
      GeneratedColumn<String>(
        'whatsapp_business_account_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _whatsappBusinessNumberMeta =
      const VerificationMeta('whatsappBusinessNumber');
  @override
  late final GeneratedColumn<String> whatsappBusinessNumber =
      GeneratedColumn<String>(
        'whatsapp_business_number',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _whatsappMockFailsMeta = const VerificationMeta(
    'whatsappMockFails',
  );
  @override
  late final GeneratedColumn<bool> whatsappMockFails = GeneratedColumn<bool>(
    'whatsapp_mock_fails',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("whatsapp_mock_fails" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _themeModeMeta = const VerificationMeta(
    'themeMode',
  );
  @override
  late final GeneratedColumn<String> themeMode = GeneratedColumn<String>(
    'theme_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('dark'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    gymName,
    logoPath,
    phone,
    whatsappPhone,
    email,
    address,
    openingHours,
    currency,
    receiptPrefix,
    receiptFooterMessage,
    whatsappProvider,
    whatsappPhoneNumberId,
    whatsappAccessToken,
    whatsappBusinessAccountId,
    whatsappBusinessNumber,
    whatsappMockFails,
    themeMode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gym_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<GymSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('gym_name')) {
      context.handle(
        _gymNameMeta,
        gymName.isAcceptableOrUnknown(data['gym_name']!, _gymNameMeta),
      );
    }
    if (data.containsKey('logo_path')) {
      context.handle(
        _logoPathMeta,
        logoPath.isAcceptableOrUnknown(data['logo_path']!, _logoPathMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('whatsapp_phone')) {
      context.handle(
        _whatsappPhoneMeta,
        whatsappPhone.isAcceptableOrUnknown(
          data['whatsapp_phone']!,
          _whatsappPhoneMeta,
        ),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('opening_hours')) {
      context.handle(
        _openingHoursMeta,
        openingHours.isAcceptableOrUnknown(
          data['opening_hours']!,
          _openingHoursMeta,
        ),
      );
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    }
    if (data.containsKey('receipt_prefix')) {
      context.handle(
        _receiptPrefixMeta,
        receiptPrefix.isAcceptableOrUnknown(
          data['receipt_prefix']!,
          _receiptPrefixMeta,
        ),
      );
    }
    if (data.containsKey('receipt_footer_message')) {
      context.handle(
        _receiptFooterMessageMeta,
        receiptFooterMessage.isAcceptableOrUnknown(
          data['receipt_footer_message']!,
          _receiptFooterMessageMeta,
        ),
      );
    }
    if (data.containsKey('whatsapp_phone_number_id')) {
      context.handle(
        _whatsappPhoneNumberIdMeta,
        whatsappPhoneNumberId.isAcceptableOrUnknown(
          data['whatsapp_phone_number_id']!,
          _whatsappPhoneNumberIdMeta,
        ),
      );
    }
    if (data.containsKey('whatsapp_access_token')) {
      context.handle(
        _whatsappAccessTokenMeta,
        whatsappAccessToken.isAcceptableOrUnknown(
          data['whatsapp_access_token']!,
          _whatsappAccessTokenMeta,
        ),
      );
    }
    if (data.containsKey('whatsapp_business_account_id')) {
      context.handle(
        _whatsappBusinessAccountIdMeta,
        whatsappBusinessAccountId.isAcceptableOrUnknown(
          data['whatsapp_business_account_id']!,
          _whatsappBusinessAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('whatsapp_business_number')) {
      context.handle(
        _whatsappBusinessNumberMeta,
        whatsappBusinessNumber.isAcceptableOrUnknown(
          data['whatsapp_business_number']!,
          _whatsappBusinessNumberMeta,
        ),
      );
    }
    if (data.containsKey('whatsapp_mock_fails')) {
      context.handle(
        _whatsappMockFailsMeta,
        whatsappMockFails.isAcceptableOrUnknown(
          data['whatsapp_mock_fails']!,
          _whatsappMockFailsMeta,
        ),
      );
    }
    if (data.containsKey('theme_mode')) {
      context.handle(
        _themeModeMeta,
        themeMode.isAcceptableOrUnknown(data['theme_mode']!, _themeModeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GymSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GymSetting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      gymName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gym_name'],
      )!,
      logoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logo_path'],
      ),
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      whatsappPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}whatsapp_phone'],
      ),
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      openingHours: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opening_hours'],
      ),
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      receiptPrefix: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_prefix'],
      )!,
      receiptFooterMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_footer_message'],
      )!,
      whatsappProvider: $GymSettingsTable.$converterwhatsappProvider.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}whatsapp_provider'],
        )!,
      ),
      whatsappPhoneNumberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}whatsapp_phone_number_id'],
      ),
      whatsappAccessToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}whatsapp_access_token'],
      ),
      whatsappBusinessAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}whatsapp_business_account_id'],
      ),
      whatsappBusinessNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}whatsapp_business_number'],
      ),
      whatsappMockFails: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}whatsapp_mock_fails'],
      )!,
      themeMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_mode'],
      )!,
    );
  }

  @override
  $GymSettingsTable createAlias(String alias) {
    return $GymSettingsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<WhatsAppProviderKind, String, String>
  $converterwhatsappProvider = const EnumNameConverter<WhatsAppProviderKind>(
    WhatsAppProviderKind.values,
  );
}

class GymSetting extends DataClass implements Insertable<GymSetting> {
  final int id;
  final String gymName;
  final String? logoPath;
  final String? phone;
  final String? whatsappPhone;
  final String? email;
  final String? address;
  final String? openingHours;
  final String currency;
  final String receiptPrefix;
  final String receiptFooterMessage;

  /// WhatsApp credentials live in the database, not a .env file: the gym owner
  /// installs a packaged app and has no terminal to edit config files in.
  final WhatsAppProviderKind whatsappProvider;
  final String? whatsappPhoneNumberId;
  final String? whatsappAccessToken;

  /// Not needed to send, but kept so the owner can see which business account
  /// the credentials belong to when several people share a Meta setup.
  final String? whatsappBusinessAccountId;

  /// The number members see messages arrive from. Display only.
  final String? whatsappBusinessNumber;

  /// Makes the mock provider fail on demand, so the "WhatsApp failed / Retry"
  /// path can be exercised without breaking anything real.
  final bool whatsappMockFails;

  /// 'dark' or 'light'. Text rather than a boolean so adding a 'system' option
  /// later needs no migration. Dark is the default the gym has been using.
  final String themeMode;
  const GymSetting({
    required this.id,
    required this.gymName,
    this.logoPath,
    this.phone,
    this.whatsappPhone,
    this.email,
    this.address,
    this.openingHours,
    required this.currency,
    required this.receiptPrefix,
    required this.receiptFooterMessage,
    required this.whatsappProvider,
    this.whatsappPhoneNumberId,
    this.whatsappAccessToken,
    this.whatsappBusinessAccountId,
    this.whatsappBusinessNumber,
    required this.whatsappMockFails,
    required this.themeMode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['gym_name'] = Variable<String>(gymName);
    if (!nullToAbsent || logoPath != null) {
      map['logo_path'] = Variable<String>(logoPath);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || whatsappPhone != null) {
      map['whatsapp_phone'] = Variable<String>(whatsappPhone);
    }
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || openingHours != null) {
      map['opening_hours'] = Variable<String>(openingHours);
    }
    map['currency'] = Variable<String>(currency);
    map['receipt_prefix'] = Variable<String>(receiptPrefix);
    map['receipt_footer_message'] = Variable<String>(receiptFooterMessage);
    {
      map['whatsapp_provider'] = Variable<String>(
        $GymSettingsTable.$converterwhatsappProvider.toSql(whatsappProvider),
      );
    }
    if (!nullToAbsent || whatsappPhoneNumberId != null) {
      map['whatsapp_phone_number_id'] = Variable<String>(whatsappPhoneNumberId);
    }
    if (!nullToAbsent || whatsappAccessToken != null) {
      map['whatsapp_access_token'] = Variable<String>(whatsappAccessToken);
    }
    if (!nullToAbsent || whatsappBusinessAccountId != null) {
      map['whatsapp_business_account_id'] = Variable<String>(
        whatsappBusinessAccountId,
      );
    }
    if (!nullToAbsent || whatsappBusinessNumber != null) {
      map['whatsapp_business_number'] = Variable<String>(
        whatsappBusinessNumber,
      );
    }
    map['whatsapp_mock_fails'] = Variable<bool>(whatsappMockFails);
    map['theme_mode'] = Variable<String>(themeMode);
    return map;
  }

  GymSettingsCompanion toCompanion(bool nullToAbsent) {
    return GymSettingsCompanion(
      id: Value(id),
      gymName: Value(gymName),
      logoPath: logoPath == null && nullToAbsent
          ? const Value.absent()
          : Value(logoPath),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      whatsappPhone: whatsappPhone == null && nullToAbsent
          ? const Value.absent()
          : Value(whatsappPhone),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      openingHours: openingHours == null && nullToAbsent
          ? const Value.absent()
          : Value(openingHours),
      currency: Value(currency),
      receiptPrefix: Value(receiptPrefix),
      receiptFooterMessage: Value(receiptFooterMessage),
      whatsappProvider: Value(whatsappProvider),
      whatsappPhoneNumberId: whatsappPhoneNumberId == null && nullToAbsent
          ? const Value.absent()
          : Value(whatsappPhoneNumberId),
      whatsappAccessToken: whatsappAccessToken == null && nullToAbsent
          ? const Value.absent()
          : Value(whatsappAccessToken),
      whatsappBusinessAccountId:
          whatsappBusinessAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(whatsappBusinessAccountId),
      whatsappBusinessNumber: whatsappBusinessNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(whatsappBusinessNumber),
      whatsappMockFails: Value(whatsappMockFails),
      themeMode: Value(themeMode),
    );
  }

  factory GymSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GymSetting(
      id: serializer.fromJson<int>(json['id']),
      gymName: serializer.fromJson<String>(json['gymName']),
      logoPath: serializer.fromJson<String?>(json['logoPath']),
      phone: serializer.fromJson<String?>(json['phone']),
      whatsappPhone: serializer.fromJson<String?>(json['whatsappPhone']),
      email: serializer.fromJson<String?>(json['email']),
      address: serializer.fromJson<String?>(json['address']),
      openingHours: serializer.fromJson<String?>(json['openingHours']),
      currency: serializer.fromJson<String>(json['currency']),
      receiptPrefix: serializer.fromJson<String>(json['receiptPrefix']),
      receiptFooterMessage: serializer.fromJson<String>(
        json['receiptFooterMessage'],
      ),
      whatsappProvider: $GymSettingsTable.$converterwhatsappProvider.fromJson(
        serializer.fromJson<String>(json['whatsappProvider']),
      ),
      whatsappPhoneNumberId: serializer.fromJson<String?>(
        json['whatsappPhoneNumberId'],
      ),
      whatsappAccessToken: serializer.fromJson<String?>(
        json['whatsappAccessToken'],
      ),
      whatsappBusinessAccountId: serializer.fromJson<String?>(
        json['whatsappBusinessAccountId'],
      ),
      whatsappBusinessNumber: serializer.fromJson<String?>(
        json['whatsappBusinessNumber'],
      ),
      whatsappMockFails: serializer.fromJson<bool>(json['whatsappMockFails']),
      themeMode: serializer.fromJson<String>(json['themeMode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'gymName': serializer.toJson<String>(gymName),
      'logoPath': serializer.toJson<String?>(logoPath),
      'phone': serializer.toJson<String?>(phone),
      'whatsappPhone': serializer.toJson<String?>(whatsappPhone),
      'email': serializer.toJson<String?>(email),
      'address': serializer.toJson<String?>(address),
      'openingHours': serializer.toJson<String?>(openingHours),
      'currency': serializer.toJson<String>(currency),
      'receiptPrefix': serializer.toJson<String>(receiptPrefix),
      'receiptFooterMessage': serializer.toJson<String>(receiptFooterMessage),
      'whatsappProvider': serializer.toJson<String>(
        $GymSettingsTable.$converterwhatsappProvider.toJson(whatsappProvider),
      ),
      'whatsappPhoneNumberId': serializer.toJson<String?>(
        whatsappPhoneNumberId,
      ),
      'whatsappAccessToken': serializer.toJson<String?>(whatsappAccessToken),
      'whatsappBusinessAccountId': serializer.toJson<String?>(
        whatsappBusinessAccountId,
      ),
      'whatsappBusinessNumber': serializer.toJson<String?>(
        whatsappBusinessNumber,
      ),
      'whatsappMockFails': serializer.toJson<bool>(whatsappMockFails),
      'themeMode': serializer.toJson<String>(themeMode),
    };
  }

  GymSetting copyWith({
    int? id,
    String? gymName,
    Value<String?> logoPath = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    Value<String?> whatsappPhone = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> openingHours = const Value.absent(),
    String? currency,
    String? receiptPrefix,
    String? receiptFooterMessage,
    WhatsAppProviderKind? whatsappProvider,
    Value<String?> whatsappPhoneNumberId = const Value.absent(),
    Value<String?> whatsappAccessToken = const Value.absent(),
    Value<String?> whatsappBusinessAccountId = const Value.absent(),
    Value<String?> whatsappBusinessNumber = const Value.absent(),
    bool? whatsappMockFails,
    String? themeMode,
  }) => GymSetting(
    id: id ?? this.id,
    gymName: gymName ?? this.gymName,
    logoPath: logoPath.present ? logoPath.value : this.logoPath,
    phone: phone.present ? phone.value : this.phone,
    whatsappPhone: whatsappPhone.present
        ? whatsappPhone.value
        : this.whatsappPhone,
    email: email.present ? email.value : this.email,
    address: address.present ? address.value : this.address,
    openingHours: openingHours.present ? openingHours.value : this.openingHours,
    currency: currency ?? this.currency,
    receiptPrefix: receiptPrefix ?? this.receiptPrefix,
    receiptFooterMessage: receiptFooterMessage ?? this.receiptFooterMessage,
    whatsappProvider: whatsappProvider ?? this.whatsappProvider,
    whatsappPhoneNumberId: whatsappPhoneNumberId.present
        ? whatsappPhoneNumberId.value
        : this.whatsappPhoneNumberId,
    whatsappAccessToken: whatsappAccessToken.present
        ? whatsappAccessToken.value
        : this.whatsappAccessToken,
    whatsappBusinessAccountId: whatsappBusinessAccountId.present
        ? whatsappBusinessAccountId.value
        : this.whatsappBusinessAccountId,
    whatsappBusinessNumber: whatsappBusinessNumber.present
        ? whatsappBusinessNumber.value
        : this.whatsappBusinessNumber,
    whatsappMockFails: whatsappMockFails ?? this.whatsappMockFails,
    themeMode: themeMode ?? this.themeMode,
  );
  GymSetting copyWithCompanion(GymSettingsCompanion data) {
    return GymSetting(
      id: data.id.present ? data.id.value : this.id,
      gymName: data.gymName.present ? data.gymName.value : this.gymName,
      logoPath: data.logoPath.present ? data.logoPath.value : this.logoPath,
      phone: data.phone.present ? data.phone.value : this.phone,
      whatsappPhone: data.whatsappPhone.present
          ? data.whatsappPhone.value
          : this.whatsappPhone,
      email: data.email.present ? data.email.value : this.email,
      address: data.address.present ? data.address.value : this.address,
      openingHours: data.openingHours.present
          ? data.openingHours.value
          : this.openingHours,
      currency: data.currency.present ? data.currency.value : this.currency,
      receiptPrefix: data.receiptPrefix.present
          ? data.receiptPrefix.value
          : this.receiptPrefix,
      receiptFooterMessage: data.receiptFooterMessage.present
          ? data.receiptFooterMessage.value
          : this.receiptFooterMessage,
      whatsappProvider: data.whatsappProvider.present
          ? data.whatsappProvider.value
          : this.whatsappProvider,
      whatsappPhoneNumberId: data.whatsappPhoneNumberId.present
          ? data.whatsappPhoneNumberId.value
          : this.whatsappPhoneNumberId,
      whatsappAccessToken: data.whatsappAccessToken.present
          ? data.whatsappAccessToken.value
          : this.whatsappAccessToken,
      whatsappBusinessAccountId: data.whatsappBusinessAccountId.present
          ? data.whatsappBusinessAccountId.value
          : this.whatsappBusinessAccountId,
      whatsappBusinessNumber: data.whatsappBusinessNumber.present
          ? data.whatsappBusinessNumber.value
          : this.whatsappBusinessNumber,
      whatsappMockFails: data.whatsappMockFails.present
          ? data.whatsappMockFails.value
          : this.whatsappMockFails,
      themeMode: data.themeMode.present ? data.themeMode.value : this.themeMode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GymSetting(')
          ..write('id: $id, ')
          ..write('gymName: $gymName, ')
          ..write('logoPath: $logoPath, ')
          ..write('phone: $phone, ')
          ..write('whatsappPhone: $whatsappPhone, ')
          ..write('email: $email, ')
          ..write('address: $address, ')
          ..write('openingHours: $openingHours, ')
          ..write('currency: $currency, ')
          ..write('receiptPrefix: $receiptPrefix, ')
          ..write('receiptFooterMessage: $receiptFooterMessage, ')
          ..write('whatsappProvider: $whatsappProvider, ')
          ..write('whatsappPhoneNumberId: $whatsappPhoneNumberId, ')
          ..write('whatsappAccessToken: $whatsappAccessToken, ')
          ..write('whatsappBusinessAccountId: $whatsappBusinessAccountId, ')
          ..write('whatsappBusinessNumber: $whatsappBusinessNumber, ')
          ..write('whatsappMockFails: $whatsappMockFails, ')
          ..write('themeMode: $themeMode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    gymName,
    logoPath,
    phone,
    whatsappPhone,
    email,
    address,
    openingHours,
    currency,
    receiptPrefix,
    receiptFooterMessage,
    whatsappProvider,
    whatsappPhoneNumberId,
    whatsappAccessToken,
    whatsappBusinessAccountId,
    whatsappBusinessNumber,
    whatsappMockFails,
    themeMode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GymSetting &&
          other.id == this.id &&
          other.gymName == this.gymName &&
          other.logoPath == this.logoPath &&
          other.phone == this.phone &&
          other.whatsappPhone == this.whatsappPhone &&
          other.email == this.email &&
          other.address == this.address &&
          other.openingHours == this.openingHours &&
          other.currency == this.currency &&
          other.receiptPrefix == this.receiptPrefix &&
          other.receiptFooterMessage == this.receiptFooterMessage &&
          other.whatsappProvider == this.whatsappProvider &&
          other.whatsappPhoneNumberId == this.whatsappPhoneNumberId &&
          other.whatsappAccessToken == this.whatsappAccessToken &&
          other.whatsappBusinessAccountId == this.whatsappBusinessAccountId &&
          other.whatsappBusinessNumber == this.whatsappBusinessNumber &&
          other.whatsappMockFails == this.whatsappMockFails &&
          other.themeMode == this.themeMode);
}

class GymSettingsCompanion extends UpdateCompanion<GymSetting> {
  final Value<int> id;
  final Value<String> gymName;
  final Value<String?> logoPath;
  final Value<String?> phone;
  final Value<String?> whatsappPhone;
  final Value<String?> email;
  final Value<String?> address;
  final Value<String?> openingHours;
  final Value<String> currency;
  final Value<String> receiptPrefix;
  final Value<String> receiptFooterMessage;
  final Value<WhatsAppProviderKind> whatsappProvider;
  final Value<String?> whatsappPhoneNumberId;
  final Value<String?> whatsappAccessToken;
  final Value<String?> whatsappBusinessAccountId;
  final Value<String?> whatsappBusinessNumber;
  final Value<bool> whatsappMockFails;
  final Value<String> themeMode;
  const GymSettingsCompanion({
    this.id = const Value.absent(),
    this.gymName = const Value.absent(),
    this.logoPath = const Value.absent(),
    this.phone = const Value.absent(),
    this.whatsappPhone = const Value.absent(),
    this.email = const Value.absent(),
    this.address = const Value.absent(),
    this.openingHours = const Value.absent(),
    this.currency = const Value.absent(),
    this.receiptPrefix = const Value.absent(),
    this.receiptFooterMessage = const Value.absent(),
    this.whatsappProvider = const Value.absent(),
    this.whatsappPhoneNumberId = const Value.absent(),
    this.whatsappAccessToken = const Value.absent(),
    this.whatsappBusinessAccountId = const Value.absent(),
    this.whatsappBusinessNumber = const Value.absent(),
    this.whatsappMockFails = const Value.absent(),
    this.themeMode = const Value.absent(),
  });
  GymSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.gymName = const Value.absent(),
    this.logoPath = const Value.absent(),
    this.phone = const Value.absent(),
    this.whatsappPhone = const Value.absent(),
    this.email = const Value.absent(),
    this.address = const Value.absent(),
    this.openingHours = const Value.absent(),
    this.currency = const Value.absent(),
    this.receiptPrefix = const Value.absent(),
    this.receiptFooterMessage = const Value.absent(),
    this.whatsappProvider = const Value.absent(),
    this.whatsappPhoneNumberId = const Value.absent(),
    this.whatsappAccessToken = const Value.absent(),
    this.whatsappBusinessAccountId = const Value.absent(),
    this.whatsappBusinessNumber = const Value.absent(),
    this.whatsappMockFails = const Value.absent(),
    this.themeMode = const Value.absent(),
  });
  static Insertable<GymSetting> custom({
    Expression<int>? id,
    Expression<String>? gymName,
    Expression<String>? logoPath,
    Expression<String>? phone,
    Expression<String>? whatsappPhone,
    Expression<String>? email,
    Expression<String>? address,
    Expression<String>? openingHours,
    Expression<String>? currency,
    Expression<String>? receiptPrefix,
    Expression<String>? receiptFooterMessage,
    Expression<String>? whatsappProvider,
    Expression<String>? whatsappPhoneNumberId,
    Expression<String>? whatsappAccessToken,
    Expression<String>? whatsappBusinessAccountId,
    Expression<String>? whatsappBusinessNumber,
    Expression<bool>? whatsappMockFails,
    Expression<String>? themeMode,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gymName != null) 'gym_name': gymName,
      if (logoPath != null) 'logo_path': logoPath,
      if (phone != null) 'phone': phone,
      if (whatsappPhone != null) 'whatsapp_phone': whatsappPhone,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
      if (openingHours != null) 'opening_hours': openingHours,
      if (currency != null) 'currency': currency,
      if (receiptPrefix != null) 'receipt_prefix': receiptPrefix,
      if (receiptFooterMessage != null)
        'receipt_footer_message': receiptFooterMessage,
      if (whatsappProvider != null) 'whatsapp_provider': whatsappProvider,
      if (whatsappPhoneNumberId != null)
        'whatsapp_phone_number_id': whatsappPhoneNumberId,
      if (whatsappAccessToken != null)
        'whatsapp_access_token': whatsappAccessToken,
      if (whatsappBusinessAccountId != null)
        'whatsapp_business_account_id': whatsappBusinessAccountId,
      if (whatsappBusinessNumber != null)
        'whatsapp_business_number': whatsappBusinessNumber,
      if (whatsappMockFails != null) 'whatsapp_mock_fails': whatsappMockFails,
      if (themeMode != null) 'theme_mode': themeMode,
    });
  }

  GymSettingsCompanion copyWith({
    Value<int>? id,
    Value<String>? gymName,
    Value<String?>? logoPath,
    Value<String?>? phone,
    Value<String?>? whatsappPhone,
    Value<String?>? email,
    Value<String?>? address,
    Value<String?>? openingHours,
    Value<String>? currency,
    Value<String>? receiptPrefix,
    Value<String>? receiptFooterMessage,
    Value<WhatsAppProviderKind>? whatsappProvider,
    Value<String?>? whatsappPhoneNumberId,
    Value<String?>? whatsappAccessToken,
    Value<String?>? whatsappBusinessAccountId,
    Value<String?>? whatsappBusinessNumber,
    Value<bool>? whatsappMockFails,
    Value<String>? themeMode,
  }) {
    return GymSettingsCompanion(
      id: id ?? this.id,
      gymName: gymName ?? this.gymName,
      logoPath: logoPath ?? this.logoPath,
      phone: phone ?? this.phone,
      whatsappPhone: whatsappPhone ?? this.whatsappPhone,
      email: email ?? this.email,
      address: address ?? this.address,
      openingHours: openingHours ?? this.openingHours,
      currency: currency ?? this.currency,
      receiptPrefix: receiptPrefix ?? this.receiptPrefix,
      receiptFooterMessage: receiptFooterMessage ?? this.receiptFooterMessage,
      whatsappProvider: whatsappProvider ?? this.whatsappProvider,
      whatsappPhoneNumberId:
          whatsappPhoneNumberId ?? this.whatsappPhoneNumberId,
      whatsappAccessToken: whatsappAccessToken ?? this.whatsappAccessToken,
      whatsappBusinessAccountId:
          whatsappBusinessAccountId ?? this.whatsappBusinessAccountId,
      whatsappBusinessNumber:
          whatsappBusinessNumber ?? this.whatsappBusinessNumber,
      whatsappMockFails: whatsappMockFails ?? this.whatsappMockFails,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (gymName.present) {
      map['gym_name'] = Variable<String>(gymName.value);
    }
    if (logoPath.present) {
      map['logo_path'] = Variable<String>(logoPath.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (whatsappPhone.present) {
      map['whatsapp_phone'] = Variable<String>(whatsappPhone.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (openingHours.present) {
      map['opening_hours'] = Variable<String>(openingHours.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (receiptPrefix.present) {
      map['receipt_prefix'] = Variable<String>(receiptPrefix.value);
    }
    if (receiptFooterMessage.present) {
      map['receipt_footer_message'] = Variable<String>(
        receiptFooterMessage.value,
      );
    }
    if (whatsappProvider.present) {
      map['whatsapp_provider'] = Variable<String>(
        $GymSettingsTable.$converterwhatsappProvider.toSql(
          whatsappProvider.value,
        ),
      );
    }
    if (whatsappPhoneNumberId.present) {
      map['whatsapp_phone_number_id'] = Variable<String>(
        whatsappPhoneNumberId.value,
      );
    }
    if (whatsappAccessToken.present) {
      map['whatsapp_access_token'] = Variable<String>(
        whatsappAccessToken.value,
      );
    }
    if (whatsappBusinessAccountId.present) {
      map['whatsapp_business_account_id'] = Variable<String>(
        whatsappBusinessAccountId.value,
      );
    }
    if (whatsappBusinessNumber.present) {
      map['whatsapp_business_number'] = Variable<String>(
        whatsappBusinessNumber.value,
      );
    }
    if (whatsappMockFails.present) {
      map['whatsapp_mock_fails'] = Variable<bool>(whatsappMockFails.value);
    }
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(themeMode.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GymSettingsCompanion(')
          ..write('id: $id, ')
          ..write('gymName: $gymName, ')
          ..write('logoPath: $logoPath, ')
          ..write('phone: $phone, ')
          ..write('whatsappPhone: $whatsappPhone, ')
          ..write('email: $email, ')
          ..write('address: $address, ')
          ..write('openingHours: $openingHours, ')
          ..write('currency: $currency, ')
          ..write('receiptPrefix: $receiptPrefix, ')
          ..write('receiptFooterMessage: $receiptFooterMessage, ')
          ..write('whatsappProvider: $whatsappProvider, ')
          ..write('whatsappPhoneNumberId: $whatsappPhoneNumberId, ')
          ..write('whatsappAccessToken: $whatsappAccessToken, ')
          ..write('whatsappBusinessAccountId: $whatsappBusinessAccountId, ')
          ..write('whatsappBusinessNumber: $whatsappBusinessNumber, ')
          ..write('whatsappMockFails: $whatsappMockFails, ')
          ..write('themeMode: $themeMode')
          ..write(')'))
        .toString();
  }
}

class $MembershipPlansTable extends MembershipPlans
    with TableInfo<$MembershipPlansTable, MembershipPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembershipPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMonthsMeta = const VerificationMeta(
    'durationMonths',
  );
  @override
  late final GeneratedColumn<int> durationMonths = GeneratedColumn<int>(
    'duration_months',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMinorMeta = const VerificationMeta(
    'priceMinor',
  );
  @override
  late final GeneratedColumn<int> priceMinor = GeneratedColumn<int>(
    'price_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    durationMonths,
    priceMinor,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'membership_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<MembershipPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('duration_months')) {
      context.handle(
        _durationMonthsMeta,
        durationMonths.isAcceptableOrUnknown(
          data['duration_months']!,
          _durationMonthsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationMonthsMeta);
    }
    if (data.containsKey('price_minor')) {
      context.handle(
        _priceMinorMeta,
        priceMinor.isAcceptableOrUnknown(data['price_minor']!, _priceMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMinorMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MembershipPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MembershipPlan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      durationMonths: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_months'],
      )!,
      priceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_minor'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $MembershipPlansTable createAlias(String alias) {
    return $MembershipPlansTable(attachedDatabase, alias);
  }
}

class MembershipPlan extends DataClass implements Insertable<MembershipPlan> {
  final int id;
  final String name;
  final String? description;
  final int durationMonths;
  final int priceMinor;
  final bool isActive;
  const MembershipPlan({
    required this.id,
    required this.name,
    this.description,
    required this.durationMonths,
    required this.priceMinor,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['duration_months'] = Variable<int>(durationMonths);
    map['price_minor'] = Variable<int>(priceMinor);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  MembershipPlansCompanion toCompanion(bool nullToAbsent) {
    return MembershipPlansCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      durationMonths: Value(durationMonths),
      priceMinor: Value(priceMinor),
      isActive: Value(isActive),
    );
  }

  factory MembershipPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MembershipPlan(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      durationMonths: serializer.fromJson<int>(json['durationMonths']),
      priceMinor: serializer.fromJson<int>(json['priceMinor']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'durationMonths': serializer.toJson<int>(durationMonths),
      'priceMinor': serializer.toJson<int>(priceMinor),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  MembershipPlan copyWith({
    int? id,
    String? name,
    Value<String?> description = const Value.absent(),
    int? durationMonths,
    int? priceMinor,
    bool? isActive,
  }) => MembershipPlan(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    durationMonths: durationMonths ?? this.durationMonths,
    priceMinor: priceMinor ?? this.priceMinor,
    isActive: isActive ?? this.isActive,
  );
  MembershipPlan copyWithCompanion(MembershipPlansCompanion data) {
    return MembershipPlan(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      durationMonths: data.durationMonths.present
          ? data.durationMonths.value
          : this.durationMonths,
      priceMinor: data.priceMinor.present
          ? data.priceMinor.value
          : this.priceMinor,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MembershipPlan(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('durationMonths: $durationMonths, ')
          ..write('priceMinor: $priceMinor, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, description, durationMonths, priceMinor, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MembershipPlan &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.durationMonths == this.durationMonths &&
          other.priceMinor == this.priceMinor &&
          other.isActive == this.isActive);
}

class MembershipPlansCompanion extends UpdateCompanion<MembershipPlan> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<int> durationMonths;
  final Value<int> priceMinor;
  final Value<bool> isActive;
  const MembershipPlansCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.durationMonths = const Value.absent(),
    this.priceMinor = const Value.absent(),
    this.isActive = const Value.absent(),
  });
  MembershipPlansCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    required int durationMonths,
    required int priceMinor,
    this.isActive = const Value.absent(),
  }) : name = Value(name),
       durationMonths = Value(durationMonths),
       priceMinor = Value(priceMinor);
  static Insertable<MembershipPlan> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<int>? durationMonths,
    Expression<int>? priceMinor,
    Expression<bool>? isActive,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (durationMonths != null) 'duration_months': durationMonths,
      if (priceMinor != null) 'price_minor': priceMinor,
      if (isActive != null) 'is_active': isActive,
    });
  }

  MembershipPlansCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<int>? durationMonths,
    Value<int>? priceMinor,
    Value<bool>? isActive,
  }) {
    return MembershipPlansCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      durationMonths: durationMonths ?? this.durationMonths,
      priceMinor: priceMinor ?? this.priceMinor,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (durationMonths.present) {
      map['duration_months'] = Variable<int>(durationMonths.value);
    }
    if (priceMinor.present) {
      map['price_minor'] = Variable<int>(priceMinor.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembershipPlansCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('durationMonths: $durationMonths, ')
          ..write('priceMinor: $priceMinor, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }
}

class $MembersTable extends Members with TableInfo<$MembersTable, Member> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _memberCodeMeta = const VerificationMeta(
    'memberCode',
  );
  @override
  late final GeneratedColumn<int> memberCode = GeneratedColumn<int>(
    'member_code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _fullNameMeta = const VerificationMeta(
    'fullName',
  );
  @override
  late final GeneratedColumn<String> fullName = GeneratedColumn<String>(
    'full_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneRawMeta = const VerificationMeta(
    'phoneRaw',
  );
  @override
  late final GeneratedColumn<String> phoneRaw = GeneratedColumn<String>(
    'phone_raw',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateOfBirthMeta = const VerificationMeta(
    'dateOfBirth',
  );
  @override
  late final GeneratedColumn<DateTime> dateOfBirth = GeneratedColumn<DateTime>(
    'date_of_birth',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emergencyContactMeta = const VerificationMeta(
    'emergencyContact',
  );
  @override
  late final GeneratedColumn<String> emergencyContact = GeneratedColumn<String>(
    'emergency_contact',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _joiningDateMeta = const VerificationMeta(
    'joiningDate',
  );
  @override
  late final GeneratedColumn<DateTime> joiningDate = GeneratedColumn<DateTime>(
    'joining_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deactivatedAtMeta = const VerificationMeta(
    'deactivatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deactivatedAt =
      GeneratedColumn<DateTime>(
        'deactivated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    memberCode,
    fullName,
    phone,
    phoneRaw,
    email,
    gender,
    dateOfBirth,
    address,
    emergencyContact,
    joiningDate,
    deactivatedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'members';
  @override
  VerificationContext validateIntegrity(
    Insertable<Member> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('member_code')) {
      context.handle(
        _memberCodeMeta,
        memberCode.isAcceptableOrUnknown(data['member_code']!, _memberCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_memberCodeMeta);
    }
    if (data.containsKey('full_name')) {
      context.handle(
        _fullNameMeta,
        fullName.isAcceptableOrUnknown(data['full_name']!, _fullNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fullNameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('phone_raw')) {
      context.handle(
        _phoneRawMeta,
        phoneRaw.isAcceptableOrUnknown(data['phone_raw']!, _phoneRawMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    }
    if (data.containsKey('date_of_birth')) {
      context.handle(
        _dateOfBirthMeta,
        dateOfBirth.isAcceptableOrUnknown(
          data['date_of_birth']!,
          _dateOfBirthMeta,
        ),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('emergency_contact')) {
      context.handle(
        _emergencyContactMeta,
        emergencyContact.isAcceptableOrUnknown(
          data['emergency_contact']!,
          _emergencyContactMeta,
        ),
      );
    }
    if (data.containsKey('joining_date')) {
      context.handle(
        _joiningDateMeta,
        joiningDate.isAcceptableOrUnknown(
          data['joining_date']!,
          _joiningDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_joiningDateMeta);
    }
    if (data.containsKey('deactivated_at')) {
      context.handle(
        _deactivatedAtMeta,
        deactivatedAt.isAcceptableOrUnknown(
          data['deactivated_at']!,
          _deactivatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Member map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Member(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      memberCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_code'],
      )!,
      fullName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}full_name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      phoneRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_raw'],
      ),
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      ),
      dateOfBirth: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_of_birth'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      emergencyContact: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emergency_contact'],
      ),
      joiningDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}joining_date'],
      )!,
      deactivatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deactivated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MembersTable createAlias(String alias) {
    return $MembersTable(attachedDatabase, alias);
  }
}

class Member extends DataClass implements Insertable<Member> {
  final int id;

  /// Human-friendly member ID, sourced from the ledger's "Enroll." column.
  final int memberCode;
  final String fullName;

  /// Normalized E.164, e.g. +923000000022.
  final String phone;

  /// The number exactly as originally entered or imported.
  final String? phoneRaw;
  final String? email;

  /// "Male" or "Female". The gym separates members by gender, not by any
  /// notion of branches or shifts.
  final String? gender;
  final DateTime? dateOfBirth;
  final String? address;
  final String? emergencyContact;
  final DateTime joiningDate;

  /// Soft deactivation — members are never deleted, so financial history lives on.
  final DateTime? deactivatedAt;
  final DateTime createdAt;
  const Member({
    required this.id,
    required this.memberCode,
    required this.fullName,
    required this.phone,
    this.phoneRaw,
    this.email,
    this.gender,
    this.dateOfBirth,
    this.address,
    this.emergencyContact,
    required this.joiningDate,
    this.deactivatedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['member_code'] = Variable<int>(memberCode);
    map['full_name'] = Variable<String>(fullName);
    map['phone'] = Variable<String>(phone);
    if (!nullToAbsent || phoneRaw != null) {
      map['phone_raw'] = Variable<String>(phoneRaw);
    }
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || gender != null) {
      map['gender'] = Variable<String>(gender);
    }
    if (!nullToAbsent || dateOfBirth != null) {
      map['date_of_birth'] = Variable<DateTime>(dateOfBirth);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || emergencyContact != null) {
      map['emergency_contact'] = Variable<String>(emergencyContact);
    }
    map['joining_date'] = Variable<DateTime>(joiningDate);
    if (!nullToAbsent || deactivatedAt != null) {
      map['deactivated_at'] = Variable<DateTime>(deactivatedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MembersCompanion toCompanion(bool nullToAbsent) {
    return MembersCompanion(
      id: Value(id),
      memberCode: Value(memberCode),
      fullName: Value(fullName),
      phone: Value(phone),
      phoneRaw: phoneRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(phoneRaw),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      gender: gender == null && nullToAbsent
          ? const Value.absent()
          : Value(gender),
      dateOfBirth: dateOfBirth == null && nullToAbsent
          ? const Value.absent()
          : Value(dateOfBirth),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      emergencyContact: emergencyContact == null && nullToAbsent
          ? const Value.absent()
          : Value(emergencyContact),
      joiningDate: Value(joiningDate),
      deactivatedAt: deactivatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deactivatedAt),
      createdAt: Value(createdAt),
    );
  }

  factory Member.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Member(
      id: serializer.fromJson<int>(json['id']),
      memberCode: serializer.fromJson<int>(json['memberCode']),
      fullName: serializer.fromJson<String>(json['fullName']),
      phone: serializer.fromJson<String>(json['phone']),
      phoneRaw: serializer.fromJson<String?>(json['phoneRaw']),
      email: serializer.fromJson<String?>(json['email']),
      gender: serializer.fromJson<String?>(json['gender']),
      dateOfBirth: serializer.fromJson<DateTime?>(json['dateOfBirth']),
      address: serializer.fromJson<String?>(json['address']),
      emergencyContact: serializer.fromJson<String?>(json['emergencyContact']),
      joiningDate: serializer.fromJson<DateTime>(json['joiningDate']),
      deactivatedAt: serializer.fromJson<DateTime?>(json['deactivatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'memberCode': serializer.toJson<int>(memberCode),
      'fullName': serializer.toJson<String>(fullName),
      'phone': serializer.toJson<String>(phone),
      'phoneRaw': serializer.toJson<String?>(phoneRaw),
      'email': serializer.toJson<String?>(email),
      'gender': serializer.toJson<String?>(gender),
      'dateOfBirth': serializer.toJson<DateTime?>(dateOfBirth),
      'address': serializer.toJson<String?>(address),
      'emergencyContact': serializer.toJson<String?>(emergencyContact),
      'joiningDate': serializer.toJson<DateTime>(joiningDate),
      'deactivatedAt': serializer.toJson<DateTime?>(deactivatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Member copyWith({
    int? id,
    int? memberCode,
    String? fullName,
    String? phone,
    Value<String?> phoneRaw = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> gender = const Value.absent(),
    Value<DateTime?> dateOfBirth = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> emergencyContact = const Value.absent(),
    DateTime? joiningDate,
    Value<DateTime?> deactivatedAt = const Value.absent(),
    DateTime? createdAt,
  }) => Member(
    id: id ?? this.id,
    memberCode: memberCode ?? this.memberCode,
    fullName: fullName ?? this.fullName,
    phone: phone ?? this.phone,
    phoneRaw: phoneRaw.present ? phoneRaw.value : this.phoneRaw,
    email: email.present ? email.value : this.email,
    gender: gender.present ? gender.value : this.gender,
    dateOfBirth: dateOfBirth.present ? dateOfBirth.value : this.dateOfBirth,
    address: address.present ? address.value : this.address,
    emergencyContact: emergencyContact.present
        ? emergencyContact.value
        : this.emergencyContact,
    joiningDate: joiningDate ?? this.joiningDate,
    deactivatedAt: deactivatedAt.present
        ? deactivatedAt.value
        : this.deactivatedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  Member copyWithCompanion(MembersCompanion data) {
    return Member(
      id: data.id.present ? data.id.value : this.id,
      memberCode: data.memberCode.present
          ? data.memberCode.value
          : this.memberCode,
      fullName: data.fullName.present ? data.fullName.value : this.fullName,
      phone: data.phone.present ? data.phone.value : this.phone,
      phoneRaw: data.phoneRaw.present ? data.phoneRaw.value : this.phoneRaw,
      email: data.email.present ? data.email.value : this.email,
      gender: data.gender.present ? data.gender.value : this.gender,
      dateOfBirth: data.dateOfBirth.present
          ? data.dateOfBirth.value
          : this.dateOfBirth,
      address: data.address.present ? data.address.value : this.address,
      emergencyContact: data.emergencyContact.present
          ? data.emergencyContact.value
          : this.emergencyContact,
      joiningDate: data.joiningDate.present
          ? data.joiningDate.value
          : this.joiningDate,
      deactivatedAt: data.deactivatedAt.present
          ? data.deactivatedAt.value
          : this.deactivatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Member(')
          ..write('id: $id, ')
          ..write('memberCode: $memberCode, ')
          ..write('fullName: $fullName, ')
          ..write('phone: $phone, ')
          ..write('phoneRaw: $phoneRaw, ')
          ..write('email: $email, ')
          ..write('gender: $gender, ')
          ..write('dateOfBirth: $dateOfBirth, ')
          ..write('address: $address, ')
          ..write('emergencyContact: $emergencyContact, ')
          ..write('joiningDate: $joiningDate, ')
          ..write('deactivatedAt: $deactivatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    memberCode,
    fullName,
    phone,
    phoneRaw,
    email,
    gender,
    dateOfBirth,
    address,
    emergencyContact,
    joiningDate,
    deactivatedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Member &&
          other.id == this.id &&
          other.memberCode == this.memberCode &&
          other.fullName == this.fullName &&
          other.phone == this.phone &&
          other.phoneRaw == this.phoneRaw &&
          other.email == this.email &&
          other.gender == this.gender &&
          other.dateOfBirth == this.dateOfBirth &&
          other.address == this.address &&
          other.emergencyContact == this.emergencyContact &&
          other.joiningDate == this.joiningDate &&
          other.deactivatedAt == this.deactivatedAt &&
          other.createdAt == this.createdAt);
}

class MembersCompanion extends UpdateCompanion<Member> {
  final Value<int> id;
  final Value<int> memberCode;
  final Value<String> fullName;
  final Value<String> phone;
  final Value<String?> phoneRaw;
  final Value<String?> email;
  final Value<String?> gender;
  final Value<DateTime?> dateOfBirth;
  final Value<String?> address;
  final Value<String?> emergencyContact;
  final Value<DateTime> joiningDate;
  final Value<DateTime?> deactivatedAt;
  final Value<DateTime> createdAt;
  const MembersCompanion({
    this.id = const Value.absent(),
    this.memberCode = const Value.absent(),
    this.fullName = const Value.absent(),
    this.phone = const Value.absent(),
    this.phoneRaw = const Value.absent(),
    this.email = const Value.absent(),
    this.gender = const Value.absent(),
    this.dateOfBirth = const Value.absent(),
    this.address = const Value.absent(),
    this.emergencyContact = const Value.absent(),
    this.joiningDate = const Value.absent(),
    this.deactivatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MembersCompanion.insert({
    this.id = const Value.absent(),
    required int memberCode,
    required String fullName,
    required String phone,
    this.phoneRaw = const Value.absent(),
    this.email = const Value.absent(),
    this.gender = const Value.absent(),
    this.dateOfBirth = const Value.absent(),
    this.address = const Value.absent(),
    this.emergencyContact = const Value.absent(),
    required DateTime joiningDate,
    this.deactivatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : memberCode = Value(memberCode),
       fullName = Value(fullName),
       phone = Value(phone),
       joiningDate = Value(joiningDate);
  static Insertable<Member> custom({
    Expression<int>? id,
    Expression<int>? memberCode,
    Expression<String>? fullName,
    Expression<String>? phone,
    Expression<String>? phoneRaw,
    Expression<String>? email,
    Expression<String>? gender,
    Expression<DateTime>? dateOfBirth,
    Expression<String>? address,
    Expression<String>? emergencyContact,
    Expression<DateTime>? joiningDate,
    Expression<DateTime>? deactivatedAt,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (memberCode != null) 'member_code': memberCode,
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
      if (phoneRaw != null) 'phone_raw': phoneRaw,
      if (email != null) 'email': email,
      if (gender != null) 'gender': gender,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (address != null) 'address': address,
      if (emergencyContact != null) 'emergency_contact': emergencyContact,
      if (joiningDate != null) 'joining_date': joiningDate,
      if (deactivatedAt != null) 'deactivated_at': deactivatedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MembersCompanion copyWith({
    Value<int>? id,
    Value<int>? memberCode,
    Value<String>? fullName,
    Value<String>? phone,
    Value<String?>? phoneRaw,
    Value<String?>? email,
    Value<String?>? gender,
    Value<DateTime?>? dateOfBirth,
    Value<String?>? address,
    Value<String?>? emergencyContact,
    Value<DateTime>? joiningDate,
    Value<DateTime?>? deactivatedAt,
    Value<DateTime>? createdAt,
  }) {
    return MembersCompanion(
      id: id ?? this.id,
      memberCode: memberCode ?? this.memberCode,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      phoneRaw: phoneRaw ?? this.phoneRaw,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      address: address ?? this.address,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      joiningDate: joiningDate ?? this.joiningDate,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (memberCode.present) {
      map['member_code'] = Variable<int>(memberCode.value);
    }
    if (fullName.present) {
      map['full_name'] = Variable<String>(fullName.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (phoneRaw.present) {
      map['phone_raw'] = Variable<String>(phoneRaw.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (dateOfBirth.present) {
      map['date_of_birth'] = Variable<DateTime>(dateOfBirth.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (emergencyContact.present) {
      map['emergency_contact'] = Variable<String>(emergencyContact.value);
    }
    if (joiningDate.present) {
      map['joining_date'] = Variable<DateTime>(joiningDate.value);
    }
    if (deactivatedAt.present) {
      map['deactivated_at'] = Variable<DateTime>(deactivatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembersCompanion(')
          ..write('id: $id, ')
          ..write('memberCode: $memberCode, ')
          ..write('fullName: $fullName, ')
          ..write('phone: $phone, ')
          ..write('phoneRaw: $phoneRaw, ')
          ..write('email: $email, ')
          ..write('gender: $gender, ')
          ..write('dateOfBirth: $dateOfBirth, ')
          ..write('address: $address, ')
          ..write('emergencyContact: $emergencyContact, ')
          ..write('joiningDate: $joiningDate, ')
          ..write('deactivatedAt: $deactivatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $MembershipsTable extends Memberships
    with TableInfo<$MembershipsTable, Membership> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembershipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<int> memberId = GeneratedColumn<int>(
    'member_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<int> planId = GeneratedColumn<int>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES membership_plans (id)',
    ),
  );
  static const VerificationMeta _feeOverrideMinorMeta = const VerificationMeta(
    'feeOverrideMinor',
  );
  @override
  late final GeneratedColumn<int> feeOverrideMinor = GeneratedColumn<int>(
    'fee_override_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    memberId,
    planId,
    feeOverrideMinor,
    startDate,
    endDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memberships';
  @override
  VerificationContext validateIntegrity(
    Insertable<Membership> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('fee_override_minor')) {
      context.handle(
        _feeOverrideMinorMeta,
        feeOverrideMinor.isAcceptableOrUnknown(
          data['fee_override_minor']!,
          _feeOverrideMinorMeta,
        ),
      );
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Membership map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Membership(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}plan_id'],
      )!,
      feeOverrideMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fee_override_minor'],
      ),
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
    );
  }

  @override
  $MembershipsTable createAlias(String alias) {
    return $MembershipsTable(attachedDatabase, alias);
  }
}

class Membership extends DataClass implements Insertable<Membership> {
  final int id;
  final int memberId;
  final int planId;

  /// Custom per-member pricing; falls back to the plan price when null.
  final int? feeOverrideMinor;
  final DateTime startDate;

  /// Null means this is the member's currently active enrolment.
  final DateTime? endDate;
  const Membership({
    required this.id,
    required this.memberId,
    required this.planId,
    this.feeOverrideMinor,
    required this.startDate,
    this.endDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['member_id'] = Variable<int>(memberId);
    map['plan_id'] = Variable<int>(planId);
    if (!nullToAbsent || feeOverrideMinor != null) {
      map['fee_override_minor'] = Variable<int>(feeOverrideMinor);
    }
    map['start_date'] = Variable<DateTime>(startDate);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    return map;
  }

  MembershipsCompanion toCompanion(bool nullToAbsent) {
    return MembershipsCompanion(
      id: Value(id),
      memberId: Value(memberId),
      planId: Value(planId),
      feeOverrideMinor: feeOverrideMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(feeOverrideMinor),
      startDate: Value(startDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
    );
  }

  factory Membership.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Membership(
      id: serializer.fromJson<int>(json['id']),
      memberId: serializer.fromJson<int>(json['memberId']),
      planId: serializer.fromJson<int>(json['planId']),
      feeOverrideMinor: serializer.fromJson<int?>(json['feeOverrideMinor']),
      startDate: serializer.fromJson<DateTime>(json['startDate']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'memberId': serializer.toJson<int>(memberId),
      'planId': serializer.toJson<int>(planId),
      'feeOverrideMinor': serializer.toJson<int?>(feeOverrideMinor),
      'startDate': serializer.toJson<DateTime>(startDate),
      'endDate': serializer.toJson<DateTime?>(endDate),
    };
  }

  Membership copyWith({
    int? id,
    int? memberId,
    int? planId,
    Value<int?> feeOverrideMinor = const Value.absent(),
    DateTime? startDate,
    Value<DateTime?> endDate = const Value.absent(),
  }) => Membership(
    id: id ?? this.id,
    memberId: memberId ?? this.memberId,
    planId: planId ?? this.planId,
    feeOverrideMinor: feeOverrideMinor.present
        ? feeOverrideMinor.value
        : this.feeOverrideMinor,
    startDate: startDate ?? this.startDate,
    endDate: endDate.present ? endDate.value : this.endDate,
  );
  Membership copyWithCompanion(MembershipsCompanion data) {
    return Membership(
      id: data.id.present ? data.id.value : this.id,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      planId: data.planId.present ? data.planId.value : this.planId,
      feeOverrideMinor: data.feeOverrideMinor.present
          ? data.feeOverrideMinor.value
          : this.feeOverrideMinor,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Membership(')
          ..write('id: $id, ')
          ..write('memberId: $memberId, ')
          ..write('planId: $planId, ')
          ..write('feeOverrideMinor: $feeOverrideMinor, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, memberId, planId, feeOverrideMinor, startDate, endDate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Membership &&
          other.id == this.id &&
          other.memberId == this.memberId &&
          other.planId == this.planId &&
          other.feeOverrideMinor == this.feeOverrideMinor &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate);
}

class MembershipsCompanion extends UpdateCompanion<Membership> {
  final Value<int> id;
  final Value<int> memberId;
  final Value<int> planId;
  final Value<int?> feeOverrideMinor;
  final Value<DateTime> startDate;
  final Value<DateTime?> endDate;
  const MembershipsCompanion({
    this.id = const Value.absent(),
    this.memberId = const Value.absent(),
    this.planId = const Value.absent(),
    this.feeOverrideMinor = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
  });
  MembershipsCompanion.insert({
    this.id = const Value.absent(),
    required int memberId,
    required int planId,
    this.feeOverrideMinor = const Value.absent(),
    required DateTime startDate,
    this.endDate = const Value.absent(),
  }) : memberId = Value(memberId),
       planId = Value(planId),
       startDate = Value(startDate);
  static Insertable<Membership> custom({
    Expression<int>? id,
    Expression<int>? memberId,
    Expression<int>? planId,
    Expression<int>? feeOverrideMinor,
    Expression<DateTime>? startDate,
    Expression<DateTime>? endDate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (memberId != null) 'member_id': memberId,
      if (planId != null) 'plan_id': planId,
      if (feeOverrideMinor != null) 'fee_override_minor': feeOverrideMinor,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
    });
  }

  MembershipsCompanion copyWith({
    Value<int>? id,
    Value<int>? memberId,
    Value<int>? planId,
    Value<int?>? feeOverrideMinor,
    Value<DateTime>? startDate,
    Value<DateTime?>? endDate,
  }) {
    return MembershipsCompanion(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      planId: planId ?? this.planId,
      feeOverrideMinor: feeOverrideMinor ?? this.feeOverrideMinor,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<int>(memberId.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<int>(planId.value);
    }
    if (feeOverrideMinor.present) {
      map['fee_override_minor'] = Variable<int>(feeOverrideMinor.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembershipsCompanion(')
          ..write('id: $id, ')
          ..write('memberId: $memberId, ')
          ..write('planId: $planId, ')
          ..write('feeOverrideMinor: $feeOverrideMinor, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate')
          ..write(')'))
        .toString();
  }
}

class $MembershipPeriodsTable extends MembershipPeriods
    with TableInfo<$MembershipPeriodsTable, MembershipPeriod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembershipPeriodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _membershipIdMeta = const VerificationMeta(
    'membershipId',
  );
  @override
  late final GeneratedColumn<int> membershipId = GeneratedColumn<int>(
    'membership_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES memberships (id)',
    ),
  );
  static const VerificationMeta _periodStartMeta = const VerificationMeta(
    'periodStart',
  );
  @override
  late final GeneratedColumn<DateTime> periodStart = GeneratedColumn<DateTime>(
    'period_start',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodEndMeta = const VerificationMeta(
    'periodEnd',
  );
  @override
  late final GeneratedColumn<DateTime> periodEnd = GeneratedColumn<DateTime>(
    'period_end',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedAmountMinorMeta =
      const VerificationMeta('expectedAmountMinor');
  @override
  late final GeneratedColumn<int> expectedAmountMinor = GeneratedColumn<int>(
    'expected_amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    membershipId,
    periodStart,
    periodEnd,
    expectedAmountMinor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'membership_periods';
  @override
  VerificationContext validateIntegrity(
    Insertable<MembershipPeriod> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('membership_id')) {
      context.handle(
        _membershipIdMeta,
        membershipId.isAcceptableOrUnknown(
          data['membership_id']!,
          _membershipIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_membershipIdMeta);
    }
    if (data.containsKey('period_start')) {
      context.handle(
        _periodStartMeta,
        periodStart.isAcceptableOrUnknown(
          data['period_start']!,
          _periodStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodStartMeta);
    }
    if (data.containsKey('period_end')) {
      context.handle(
        _periodEndMeta,
        periodEnd.isAcceptableOrUnknown(data['period_end']!, _periodEndMeta),
      );
    } else if (isInserting) {
      context.missing(_periodEndMeta);
    }
    if (data.containsKey('expected_amount_minor')) {
      context.handle(
        _expectedAmountMinorMeta,
        expectedAmountMinor.isAcceptableOrUnknown(
          data['expected_amount_minor']!,
          _expectedAmountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedAmountMinorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {membershipId, periodStart},
  ];
  @override
  MembershipPeriod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MembershipPeriod(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      membershipId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}membership_id'],
      )!,
      periodStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}period_start'],
      )!,
      periodEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}period_end'],
      )!,
      expectedAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_amount_minor'],
      )!,
    );
  }

  @override
  $MembershipPeriodsTable createAlias(String alias) {
    return $MembershipPeriodsTable(attachedDatabase, alias);
  }
}

class MembershipPeriod extends DataClass
    implements Insertable<MembershipPeriod> {
  final int id;
  final int membershipId;
  final DateTime periodStart;

  /// Exclusive end of the cycle.
  final DateTime periodEnd;

  /// Fee snapshot at creation time, so later price changes don't rewrite history.
  final int expectedAmountMinor;
  const MembershipPeriod({
    required this.id,
    required this.membershipId,
    required this.periodStart,
    required this.periodEnd,
    required this.expectedAmountMinor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['membership_id'] = Variable<int>(membershipId);
    map['period_start'] = Variable<DateTime>(periodStart);
    map['period_end'] = Variable<DateTime>(periodEnd);
    map['expected_amount_minor'] = Variable<int>(expectedAmountMinor);
    return map;
  }

  MembershipPeriodsCompanion toCompanion(bool nullToAbsent) {
    return MembershipPeriodsCompanion(
      id: Value(id),
      membershipId: Value(membershipId),
      periodStart: Value(periodStart),
      periodEnd: Value(periodEnd),
      expectedAmountMinor: Value(expectedAmountMinor),
    );
  }

  factory MembershipPeriod.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MembershipPeriod(
      id: serializer.fromJson<int>(json['id']),
      membershipId: serializer.fromJson<int>(json['membershipId']),
      periodStart: serializer.fromJson<DateTime>(json['periodStart']),
      periodEnd: serializer.fromJson<DateTime>(json['periodEnd']),
      expectedAmountMinor: serializer.fromJson<int>(
        json['expectedAmountMinor'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'membershipId': serializer.toJson<int>(membershipId),
      'periodStart': serializer.toJson<DateTime>(periodStart),
      'periodEnd': serializer.toJson<DateTime>(periodEnd),
      'expectedAmountMinor': serializer.toJson<int>(expectedAmountMinor),
    };
  }

  MembershipPeriod copyWith({
    int? id,
    int? membershipId,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? expectedAmountMinor,
  }) => MembershipPeriod(
    id: id ?? this.id,
    membershipId: membershipId ?? this.membershipId,
    periodStart: periodStart ?? this.periodStart,
    periodEnd: periodEnd ?? this.periodEnd,
    expectedAmountMinor: expectedAmountMinor ?? this.expectedAmountMinor,
  );
  MembershipPeriod copyWithCompanion(MembershipPeriodsCompanion data) {
    return MembershipPeriod(
      id: data.id.present ? data.id.value : this.id,
      membershipId: data.membershipId.present
          ? data.membershipId.value
          : this.membershipId,
      periodStart: data.periodStart.present
          ? data.periodStart.value
          : this.periodStart,
      periodEnd: data.periodEnd.present ? data.periodEnd.value : this.periodEnd,
      expectedAmountMinor: data.expectedAmountMinor.present
          ? data.expectedAmountMinor.value
          : this.expectedAmountMinor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MembershipPeriod(')
          ..write('id: $id, ')
          ..write('membershipId: $membershipId, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('expectedAmountMinor: $expectedAmountMinor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    membershipId,
    periodStart,
    periodEnd,
    expectedAmountMinor,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MembershipPeriod &&
          other.id == this.id &&
          other.membershipId == this.membershipId &&
          other.periodStart == this.periodStart &&
          other.periodEnd == this.periodEnd &&
          other.expectedAmountMinor == this.expectedAmountMinor);
}

class MembershipPeriodsCompanion extends UpdateCompanion<MembershipPeriod> {
  final Value<int> id;
  final Value<int> membershipId;
  final Value<DateTime> periodStart;
  final Value<DateTime> periodEnd;
  final Value<int> expectedAmountMinor;
  const MembershipPeriodsCompanion({
    this.id = const Value.absent(),
    this.membershipId = const Value.absent(),
    this.periodStart = const Value.absent(),
    this.periodEnd = const Value.absent(),
    this.expectedAmountMinor = const Value.absent(),
  });
  MembershipPeriodsCompanion.insert({
    this.id = const Value.absent(),
    required int membershipId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int expectedAmountMinor,
  }) : membershipId = Value(membershipId),
       periodStart = Value(periodStart),
       periodEnd = Value(periodEnd),
       expectedAmountMinor = Value(expectedAmountMinor);
  static Insertable<MembershipPeriod> custom({
    Expression<int>? id,
    Expression<int>? membershipId,
    Expression<DateTime>? periodStart,
    Expression<DateTime>? periodEnd,
    Expression<int>? expectedAmountMinor,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (membershipId != null) 'membership_id': membershipId,
      if (periodStart != null) 'period_start': periodStart,
      if (periodEnd != null) 'period_end': periodEnd,
      if (expectedAmountMinor != null)
        'expected_amount_minor': expectedAmountMinor,
    });
  }

  MembershipPeriodsCompanion copyWith({
    Value<int>? id,
    Value<int>? membershipId,
    Value<DateTime>? periodStart,
    Value<DateTime>? periodEnd,
    Value<int>? expectedAmountMinor,
  }) {
    return MembershipPeriodsCompanion(
      id: id ?? this.id,
      membershipId: membershipId ?? this.membershipId,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      expectedAmountMinor: expectedAmountMinor ?? this.expectedAmountMinor,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (membershipId.present) {
      map['membership_id'] = Variable<int>(membershipId.value);
    }
    if (periodStart.present) {
      map['period_start'] = Variable<DateTime>(periodStart.value);
    }
    if (periodEnd.present) {
      map['period_end'] = Variable<DateTime>(periodEnd.value);
    }
    if (expectedAmountMinor.present) {
      map['expected_amount_minor'] = Variable<int>(expectedAmountMinor.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembershipPeriodsCompanion(')
          ..write('id: $id, ')
          ..write('membershipId: $membershipId, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('expectedAmountMinor: $expectedAmountMinor')
          ..write(')'))
        .toString();
  }
}

class $PaymentsTable extends Payments with TableInfo<$PaymentsTable, Payment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<int> memberId = GeneratedColumn<int>(
    'member_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  static const VerificationMeta _membershipPeriodIdMeta =
      const VerificationMeta('membershipPeriodId');
  @override
  late final GeneratedColumn<int> membershipPeriodId = GeneratedColumn<int>(
    'membership_period_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES membership_periods (id)',
    ),
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PaymentMethod, String> method =
      GeneratedColumn<String>(
        'method',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PaymentMethod>($PaymentsTable.$convertermethod);
  static const VerificationMeta _referenceNumberMeta = const VerificationMeta(
    'referenceNumber',
  );
  @override
  late final GeneratedColumn<String> referenceNumber = GeneratedColumn<String>(
    'reference_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentDateMeta = const VerificationMeta(
    'paymentDate',
  );
  @override
  late final GeneratedColumn<DateTime> paymentDate = GeneratedColumn<DateTime>(
    'payment_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PaymentSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('manual'),
      ).withConverter<PaymentSource>($PaymentsTable.$convertersource);
  static const VerificationMeta _recordedByIdMeta = const VerificationMeta(
    'recordedById',
  );
  @override
  late final GeneratedColumn<int> recordedById = GeneratedColumn<int>(
    'recorded_by_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedByIdMeta = const VerificationMeta(
    'updatedById',
  );
  @override
  late final GeneratedColumn<int> updatedById = GeneratedColumn<int>(
    'updated_by_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    memberId,
    membershipPeriodId,
    amountMinor,
    method,
    referenceNumber,
    paymentDate,
    notes,
    source,
    recordedById,
    updatedAt,
    updatedById,
    idempotencyKey,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Payment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('membership_period_id')) {
      context.handle(
        _membershipPeriodIdMeta,
        membershipPeriodId.isAcceptableOrUnknown(
          data['membership_period_id']!,
          _membershipPeriodIdMeta,
        ),
      );
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('reference_number')) {
      context.handle(
        _referenceNumberMeta,
        referenceNumber.isAcceptableOrUnknown(
          data['reference_number']!,
          _referenceNumberMeta,
        ),
      );
    }
    if (data.containsKey('payment_date')) {
      context.handle(
        _paymentDateMeta,
        paymentDate.isAcceptableOrUnknown(
          data['payment_date']!,
          _paymentDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentDateMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('recorded_by_id')) {
      context.handle(
        _recordedByIdMeta,
        recordedById.isAcceptableOrUnknown(
          data['recorded_by_id']!,
          _recordedByIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordedByIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('updated_by_id')) {
      context.handle(
        _updatedByIdMeta,
        updatedById.isAcceptableOrUnknown(
          data['updated_by_id']!,
          _updatedByIdMeta,
        ),
      );
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Payment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Payment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_id'],
      )!,
      membershipPeriodId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}membership_period_id'],
      ),
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      method: $PaymentsTable.$convertermethod.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}method'],
        )!,
      ),
      referenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_number'],
      ),
      paymentDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}payment_date'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      source: $PaymentsTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      recordedById: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_by_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      updatedById: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_by_id'],
      ),
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PaymentsTable createAlias(String alias) {
    return $PaymentsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PaymentMethod, String, String> $convertermethod =
      const EnumNameConverter<PaymentMethod>(PaymentMethod.values);
  static JsonTypeConverter2<PaymentSource, String, String> $convertersource =
      const EnumNameConverter<PaymentSource>(PaymentSource.values);
}

class Payment extends DataClass implements Insertable<Payment> {
  final int id;
  final int memberId;
  final int? membershipPeriodId;
  final int amountMinor;
  final PaymentMethod method;
  final String? referenceNumber;
  final DateTime paymentDate;
  final String? notes;
  final PaymentSource source;
  final int recordedById;

  /// Set when a recorded payment is corrected. The receipt is re-rendered in
  /// place under its original number, so without these two columns nothing on
  /// the row itself would show it had ever been touched. Null means never
  /// edited, which is what every row predating v7 reads as.
  final DateTime? updatedAt;
  final int? updatedById;

  /// Unique per submission — the accidental double-click guard.
  final String idempotencyKey;
  final DateTime createdAt;
  const Payment({
    required this.id,
    required this.memberId,
    this.membershipPeriodId,
    required this.amountMinor,
    required this.method,
    this.referenceNumber,
    required this.paymentDate,
    this.notes,
    required this.source,
    required this.recordedById,
    this.updatedAt,
    this.updatedById,
    required this.idempotencyKey,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['member_id'] = Variable<int>(memberId);
    if (!nullToAbsent || membershipPeriodId != null) {
      map['membership_period_id'] = Variable<int>(membershipPeriodId);
    }
    map['amount_minor'] = Variable<int>(amountMinor);
    {
      map['method'] = Variable<String>(
        $PaymentsTable.$convertermethod.toSql(method),
      );
    }
    if (!nullToAbsent || referenceNumber != null) {
      map['reference_number'] = Variable<String>(referenceNumber);
    }
    map['payment_date'] = Variable<DateTime>(paymentDate);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    {
      map['source'] = Variable<String>(
        $PaymentsTable.$convertersource.toSql(source),
      );
    }
    map['recorded_by_id'] = Variable<int>(recordedById);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    if (!nullToAbsent || updatedById != null) {
      map['updated_by_id'] = Variable<int>(updatedById);
    }
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PaymentsCompanion toCompanion(bool nullToAbsent) {
    return PaymentsCompanion(
      id: Value(id),
      memberId: Value(memberId),
      membershipPeriodId: membershipPeriodId == null && nullToAbsent
          ? const Value.absent()
          : Value(membershipPeriodId),
      amountMinor: Value(amountMinor),
      method: Value(method),
      referenceNumber: referenceNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceNumber),
      paymentDate: Value(paymentDate),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      source: Value(source),
      recordedById: Value(recordedById),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      updatedById: updatedById == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedById),
      idempotencyKey: Value(idempotencyKey),
      createdAt: Value(createdAt),
    );
  }

  factory Payment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Payment(
      id: serializer.fromJson<int>(json['id']),
      memberId: serializer.fromJson<int>(json['memberId']),
      membershipPeriodId: serializer.fromJson<int?>(json['membershipPeriodId']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      method: $PaymentsTable.$convertermethod.fromJson(
        serializer.fromJson<String>(json['method']),
      ),
      referenceNumber: serializer.fromJson<String?>(json['referenceNumber']),
      paymentDate: serializer.fromJson<DateTime>(json['paymentDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      source: $PaymentsTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
      recordedById: serializer.fromJson<int>(json['recordedById']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      updatedById: serializer.fromJson<int?>(json['updatedById']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'memberId': serializer.toJson<int>(memberId),
      'membershipPeriodId': serializer.toJson<int?>(membershipPeriodId),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'method': serializer.toJson<String>(
        $PaymentsTable.$convertermethod.toJson(method),
      ),
      'referenceNumber': serializer.toJson<String?>(referenceNumber),
      'paymentDate': serializer.toJson<DateTime>(paymentDate),
      'notes': serializer.toJson<String?>(notes),
      'source': serializer.toJson<String>(
        $PaymentsTable.$convertersource.toJson(source),
      ),
      'recordedById': serializer.toJson<int>(recordedById),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'updatedById': serializer.toJson<int?>(updatedById),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Payment copyWith({
    int? id,
    int? memberId,
    Value<int?> membershipPeriodId = const Value.absent(),
    int? amountMinor,
    PaymentMethod? method,
    Value<String?> referenceNumber = const Value.absent(),
    DateTime? paymentDate,
    Value<String?> notes = const Value.absent(),
    PaymentSource? source,
    int? recordedById,
    Value<DateTime?> updatedAt = const Value.absent(),
    Value<int?> updatedById = const Value.absent(),
    String? idempotencyKey,
    DateTime? createdAt,
  }) => Payment(
    id: id ?? this.id,
    memberId: memberId ?? this.memberId,
    membershipPeriodId: membershipPeriodId.present
        ? membershipPeriodId.value
        : this.membershipPeriodId,
    amountMinor: amountMinor ?? this.amountMinor,
    method: method ?? this.method,
    referenceNumber: referenceNumber.present
        ? referenceNumber.value
        : this.referenceNumber,
    paymentDate: paymentDate ?? this.paymentDate,
    notes: notes.present ? notes.value : this.notes,
    source: source ?? this.source,
    recordedById: recordedById ?? this.recordedById,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    updatedById: updatedById.present ? updatedById.value : this.updatedById,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    createdAt: createdAt ?? this.createdAt,
  );
  Payment copyWithCompanion(PaymentsCompanion data) {
    return Payment(
      id: data.id.present ? data.id.value : this.id,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      membershipPeriodId: data.membershipPeriodId.present
          ? data.membershipPeriodId.value
          : this.membershipPeriodId,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      method: data.method.present ? data.method.value : this.method,
      referenceNumber: data.referenceNumber.present
          ? data.referenceNumber.value
          : this.referenceNumber,
      paymentDate: data.paymentDate.present
          ? data.paymentDate.value
          : this.paymentDate,
      notes: data.notes.present ? data.notes.value : this.notes,
      source: data.source.present ? data.source.value : this.source,
      recordedById: data.recordedById.present
          ? data.recordedById.value
          : this.recordedById,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedById: data.updatedById.present
          ? data.updatedById.value
          : this.updatedById,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Payment(')
          ..write('id: $id, ')
          ..write('memberId: $memberId, ')
          ..write('membershipPeriodId: $membershipPeriodId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('method: $method, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('notes: $notes, ')
          ..write('source: $source, ')
          ..write('recordedById: $recordedById, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedById: $updatedById, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    memberId,
    membershipPeriodId,
    amountMinor,
    method,
    referenceNumber,
    paymentDate,
    notes,
    source,
    recordedById,
    updatedAt,
    updatedById,
    idempotencyKey,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Payment &&
          other.id == this.id &&
          other.memberId == this.memberId &&
          other.membershipPeriodId == this.membershipPeriodId &&
          other.amountMinor == this.amountMinor &&
          other.method == this.method &&
          other.referenceNumber == this.referenceNumber &&
          other.paymentDate == this.paymentDate &&
          other.notes == this.notes &&
          other.source == this.source &&
          other.recordedById == this.recordedById &&
          other.updatedAt == this.updatedAt &&
          other.updatedById == this.updatedById &&
          other.idempotencyKey == this.idempotencyKey &&
          other.createdAt == this.createdAt);
}

class PaymentsCompanion extends UpdateCompanion<Payment> {
  final Value<int> id;
  final Value<int> memberId;
  final Value<int?> membershipPeriodId;
  final Value<int> amountMinor;
  final Value<PaymentMethod> method;
  final Value<String?> referenceNumber;
  final Value<DateTime> paymentDate;
  final Value<String?> notes;
  final Value<PaymentSource> source;
  final Value<int> recordedById;
  final Value<DateTime?> updatedAt;
  final Value<int?> updatedById;
  final Value<String> idempotencyKey;
  final Value<DateTime> createdAt;
  const PaymentsCompanion({
    this.id = const Value.absent(),
    this.memberId = const Value.absent(),
    this.membershipPeriodId = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.method = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.paymentDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.source = const Value.absent(),
    this.recordedById = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedById = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PaymentsCompanion.insert({
    this.id = const Value.absent(),
    required int memberId,
    this.membershipPeriodId = const Value.absent(),
    required int amountMinor,
    required PaymentMethod method,
    this.referenceNumber = const Value.absent(),
    required DateTime paymentDate,
    this.notes = const Value.absent(),
    this.source = const Value.absent(),
    required int recordedById,
    this.updatedAt = const Value.absent(),
    this.updatedById = const Value.absent(),
    required String idempotencyKey,
    this.createdAt = const Value.absent(),
  }) : memberId = Value(memberId),
       amountMinor = Value(amountMinor),
       method = Value(method),
       paymentDate = Value(paymentDate),
       recordedById = Value(recordedById),
       idempotencyKey = Value(idempotencyKey);
  static Insertable<Payment> custom({
    Expression<int>? id,
    Expression<int>? memberId,
    Expression<int>? membershipPeriodId,
    Expression<int>? amountMinor,
    Expression<String>? method,
    Expression<String>? referenceNumber,
    Expression<DateTime>? paymentDate,
    Expression<String>? notes,
    Expression<String>? source,
    Expression<int>? recordedById,
    Expression<DateTime>? updatedAt,
    Expression<int>? updatedById,
    Expression<String>? idempotencyKey,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (memberId != null) 'member_id': memberId,
      if (membershipPeriodId != null)
        'membership_period_id': membershipPeriodId,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (method != null) 'method': method,
      if (referenceNumber != null) 'reference_number': referenceNumber,
      if (paymentDate != null) 'payment_date': paymentDate,
      if (notes != null) 'notes': notes,
      if (source != null) 'source': source,
      if (recordedById != null) 'recorded_by_id': recordedById,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedById != null) 'updated_by_id': updatedById,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PaymentsCompanion copyWith({
    Value<int>? id,
    Value<int>? memberId,
    Value<int?>? membershipPeriodId,
    Value<int>? amountMinor,
    Value<PaymentMethod>? method,
    Value<String?>? referenceNumber,
    Value<DateTime>? paymentDate,
    Value<String?>? notes,
    Value<PaymentSource>? source,
    Value<int>? recordedById,
    Value<DateTime?>? updatedAt,
    Value<int?>? updatedById,
    Value<String>? idempotencyKey,
    Value<DateTime>? createdAt,
  }) {
    return PaymentsCompanion(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      membershipPeriodId: membershipPeriodId ?? this.membershipPeriodId,
      amountMinor: amountMinor ?? this.amountMinor,
      method: method ?? this.method,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      paymentDate: paymentDate ?? this.paymentDate,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      recordedById: recordedById ?? this.recordedById,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedById: updatedById ?? this.updatedById,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<int>(memberId.value);
    }
    if (membershipPeriodId.present) {
      map['membership_period_id'] = Variable<int>(membershipPeriodId.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(
        $PaymentsTable.$convertermethod.toSql(method.value),
      );
    }
    if (referenceNumber.present) {
      map['reference_number'] = Variable<String>(referenceNumber.value);
    }
    if (paymentDate.present) {
      map['payment_date'] = Variable<DateTime>(paymentDate.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $PaymentsTable.$convertersource.toSql(source.value),
      );
    }
    if (recordedById.present) {
      map['recorded_by_id'] = Variable<int>(recordedById.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedById.present) {
      map['updated_by_id'] = Variable<int>(updatedById.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentsCompanion(')
          ..write('id: $id, ')
          ..write('memberId: $memberId, ')
          ..write('membershipPeriodId: $membershipPeriodId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('method: $method, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('notes: $notes, ')
          ..write('source: $source, ')
          ..write('recordedById: $recordedById, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedById: $updatedById, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ReceiptsTable extends Receipts with TableInfo<$ReceiptsTable, Receipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _receiptNumberMeta = const VerificationMeta(
    'receiptNumber',
  );
  @override
  late final GeneratedColumn<String> receiptNumber = GeneratedColumn<String>(
    'receipt_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _paymentIdMeta = const VerificationMeta(
    'paymentId',
  );
  @override
  late final GeneratedColumn<int> paymentId = GeneratedColumn<int>(
    'payment_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES payments (id)',
    ),
  );
  static const VerificationMeta _pngPathMeta = const VerificationMeta(
    'pngPath',
  );
  @override
  late final GeneratedColumn<String> pngPath = GeneratedColumn<String>(
    'png_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pdfPathMeta = const VerificationMeta(
    'pdfPath',
  );
  @override
  late final GeneratedColumn<String> pdfPath = GeneratedColumn<String>(
    'pdf_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    receiptNumber,
    paymentId,
    pngPath,
    pdfPath,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Receipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('receipt_number')) {
      context.handle(
        _receiptNumberMeta,
        receiptNumber.isAcceptableOrUnknown(
          data['receipt_number']!,
          _receiptNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receiptNumberMeta);
    }
    if (data.containsKey('payment_id')) {
      context.handle(
        _paymentIdMeta,
        paymentId.isAcceptableOrUnknown(data['payment_id']!, _paymentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_paymentIdMeta);
    }
    if (data.containsKey('png_path')) {
      context.handle(
        _pngPathMeta,
        pngPath.isAcceptableOrUnknown(data['png_path']!, _pngPathMeta),
      );
    } else if (isInserting) {
      context.missing(_pngPathMeta);
    }
    if (data.containsKey('pdf_path')) {
      context.handle(
        _pdfPathMeta,
        pdfPath.isAcceptableOrUnknown(data['pdf_path']!, _pdfPathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Receipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Receipt(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      receiptNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_number'],
      )!,
      paymentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payment_id'],
      )!,
      pngPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}png_path'],
      )!,
      pdfPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pdf_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReceiptsTable createAlias(String alias) {
    return $ReceiptsTable(attachedDatabase, alias);
  }
}

class Receipt extends DataClass implements Insertable<Receipt> {
  final int id;
  final String receiptNumber;
  final int paymentId;
  final String pngPath;
  final String? pdfPath;
  final DateTime createdAt;
  const Receipt({
    required this.id,
    required this.receiptNumber,
    required this.paymentId,
    required this.pngPath,
    this.pdfPath,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['receipt_number'] = Variable<String>(receiptNumber);
    map['payment_id'] = Variable<int>(paymentId);
    map['png_path'] = Variable<String>(pngPath);
    if (!nullToAbsent || pdfPath != null) {
      map['pdf_path'] = Variable<String>(pdfPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ReceiptsCompanion toCompanion(bool nullToAbsent) {
    return ReceiptsCompanion(
      id: Value(id),
      receiptNumber: Value(receiptNumber),
      paymentId: Value(paymentId),
      pngPath: Value(pngPath),
      pdfPath: pdfPath == null && nullToAbsent
          ? const Value.absent()
          : Value(pdfPath),
      createdAt: Value(createdAt),
    );
  }

  factory Receipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Receipt(
      id: serializer.fromJson<int>(json['id']),
      receiptNumber: serializer.fromJson<String>(json['receiptNumber']),
      paymentId: serializer.fromJson<int>(json['paymentId']),
      pngPath: serializer.fromJson<String>(json['pngPath']),
      pdfPath: serializer.fromJson<String?>(json['pdfPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'receiptNumber': serializer.toJson<String>(receiptNumber),
      'paymentId': serializer.toJson<int>(paymentId),
      'pngPath': serializer.toJson<String>(pngPath),
      'pdfPath': serializer.toJson<String?>(pdfPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Receipt copyWith({
    int? id,
    String? receiptNumber,
    int? paymentId,
    String? pngPath,
    Value<String?> pdfPath = const Value.absent(),
    DateTime? createdAt,
  }) => Receipt(
    id: id ?? this.id,
    receiptNumber: receiptNumber ?? this.receiptNumber,
    paymentId: paymentId ?? this.paymentId,
    pngPath: pngPath ?? this.pngPath,
    pdfPath: pdfPath.present ? pdfPath.value : this.pdfPath,
    createdAt: createdAt ?? this.createdAt,
  );
  Receipt copyWithCompanion(ReceiptsCompanion data) {
    return Receipt(
      id: data.id.present ? data.id.value : this.id,
      receiptNumber: data.receiptNumber.present
          ? data.receiptNumber.value
          : this.receiptNumber,
      paymentId: data.paymentId.present ? data.paymentId.value : this.paymentId,
      pngPath: data.pngPath.present ? data.pngPath.value : this.pngPath,
      pdfPath: data.pdfPath.present ? data.pdfPath.value : this.pdfPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Receipt(')
          ..write('id: $id, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('paymentId: $paymentId, ')
          ..write('pngPath: $pngPath, ')
          ..write('pdfPath: $pdfPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, receiptNumber, paymentId, pngPath, pdfPath, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Receipt &&
          other.id == this.id &&
          other.receiptNumber == this.receiptNumber &&
          other.paymentId == this.paymentId &&
          other.pngPath == this.pngPath &&
          other.pdfPath == this.pdfPath &&
          other.createdAt == this.createdAt);
}

class ReceiptsCompanion extends UpdateCompanion<Receipt> {
  final Value<int> id;
  final Value<String> receiptNumber;
  final Value<int> paymentId;
  final Value<String> pngPath;
  final Value<String?> pdfPath;
  final Value<DateTime> createdAt;
  const ReceiptsCompanion({
    this.id = const Value.absent(),
    this.receiptNumber = const Value.absent(),
    this.paymentId = const Value.absent(),
    this.pngPath = const Value.absent(),
    this.pdfPath = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ReceiptsCompanion.insert({
    this.id = const Value.absent(),
    required String receiptNumber,
    required int paymentId,
    required String pngPath,
    this.pdfPath = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : receiptNumber = Value(receiptNumber),
       paymentId = Value(paymentId),
       pngPath = Value(pngPath);
  static Insertable<Receipt> custom({
    Expression<int>? id,
    Expression<String>? receiptNumber,
    Expression<int>? paymentId,
    Expression<String>? pngPath,
    Expression<String>? pdfPath,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (paymentId != null) 'payment_id': paymentId,
      if (pngPath != null) 'png_path': pngPath,
      if (pdfPath != null) 'pdf_path': pdfPath,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ReceiptsCompanion copyWith({
    Value<int>? id,
    Value<String>? receiptNumber,
    Value<int>? paymentId,
    Value<String>? pngPath,
    Value<String?>? pdfPath,
    Value<DateTime>? createdAt,
  }) {
    return ReceiptsCompanion(
      id: id ?? this.id,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      paymentId: paymentId ?? this.paymentId,
      pngPath: pngPath ?? this.pngPath,
      pdfPath: pdfPath ?? this.pdfPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (receiptNumber.present) {
      map['receipt_number'] = Variable<String>(receiptNumber.value);
    }
    if (paymentId.present) {
      map['payment_id'] = Variable<int>(paymentId.value);
    }
    if (pngPath.present) {
      map['png_path'] = Variable<String>(pngPath.value);
    }
    if (pdfPath.present) {
      map['pdf_path'] = Variable<String>(pdfPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptsCompanion(')
          ..write('id: $id, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('paymentId: $paymentId, ')
          ..write('pngPath: $pngPath, ')
          ..write('pdfPath: $pdfPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ReceiptCountersTable extends ReceiptCounters
    with TableInfo<$ReceiptCountersTable, ReceiptCounter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReceiptCountersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastNumberMeta = const VerificationMeta(
    'lastNumber',
  );
  @override
  late final GeneratedColumn<int> lastNumber = GeneratedColumn<int>(
    'last_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [year, lastNumber];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipt_counters';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceiptCounter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('last_number')) {
      context.handle(
        _lastNumberMeta,
        lastNumber.isAcceptableOrUnknown(data['last_number']!, _lastNumberMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {year};
  @override
  ReceiptCounter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceiptCounter(
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      )!,
      lastNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_number'],
      )!,
    );
  }

  @override
  $ReceiptCountersTable createAlias(String alias) {
    return $ReceiptCountersTable(attachedDatabase, alias);
  }
}

class ReceiptCounter extends DataClass implements Insertable<ReceiptCounter> {
  final int year;
  final int lastNumber;
  const ReceiptCounter({required this.year, required this.lastNumber});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['year'] = Variable<int>(year);
    map['last_number'] = Variable<int>(lastNumber);
    return map;
  }

  ReceiptCountersCompanion toCompanion(bool nullToAbsent) {
    return ReceiptCountersCompanion(
      year: Value(year),
      lastNumber: Value(lastNumber),
    );
  }

  factory ReceiptCounter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceiptCounter(
      year: serializer.fromJson<int>(json['year']),
      lastNumber: serializer.fromJson<int>(json['lastNumber']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'year': serializer.toJson<int>(year),
      'lastNumber': serializer.toJson<int>(lastNumber),
    };
  }

  ReceiptCounter copyWith({int? year, int? lastNumber}) => ReceiptCounter(
    year: year ?? this.year,
    lastNumber: lastNumber ?? this.lastNumber,
  );
  ReceiptCounter copyWithCompanion(ReceiptCountersCompanion data) {
    return ReceiptCounter(
      year: data.year.present ? data.year.value : this.year,
      lastNumber: data.lastNumber.present
          ? data.lastNumber.value
          : this.lastNumber,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptCounter(')
          ..write('year: $year, ')
          ..write('lastNumber: $lastNumber')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(year, lastNumber);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceiptCounter &&
          other.year == this.year &&
          other.lastNumber == this.lastNumber);
}

class ReceiptCountersCompanion extends UpdateCompanion<ReceiptCounter> {
  final Value<int> year;
  final Value<int> lastNumber;
  const ReceiptCountersCompanion({
    this.year = const Value.absent(),
    this.lastNumber = const Value.absent(),
  });
  ReceiptCountersCompanion.insert({
    this.year = const Value.absent(),
    this.lastNumber = const Value.absent(),
  });
  static Insertable<ReceiptCounter> custom({
    Expression<int>? year,
    Expression<int>? lastNumber,
  }) {
    return RawValuesInsertable({
      if (year != null) 'year': year,
      if (lastNumber != null) 'last_number': lastNumber,
    });
  }

  ReceiptCountersCompanion copyWith({
    Value<int>? year,
    Value<int>? lastNumber,
  }) {
    return ReceiptCountersCompanion(
      year: year ?? this.year,
      lastNumber: lastNumber ?? this.lastNumber,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (lastNumber.present) {
      map['last_number'] = Variable<int>(lastNumber.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptCountersCompanion(')
          ..write('year: $year, ')
          ..write('lastNumber: $lastNumber')
          ..write(')'))
        .toString();
  }
}

class $WhatsAppMessagesTable extends WhatsAppMessages
    with TableInfo<$WhatsAppMessagesTable, WhatsAppMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WhatsAppMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  @override
  late final GeneratedColumn<int> receiptId = GeneratedColumn<int>(
    'receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES receipts (id)',
    ),
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<int> memberId = GeneratedColumn<int>(
    'member_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<WhatsAppProviderKind, String>
  provider =
      GeneratedColumn<String>(
        'provider',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<WhatsAppProviderKind>(
        $WhatsAppMessagesTable.$converterprovider,
      );
  static const VerificationMeta _externalMessageIdMeta = const VerificationMeta(
    'externalMessageId',
  );
  @override
  late final GeneratedColumn<String> externalMessageId =
      GeneratedColumn<String>(
        'external_message_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<WhatsAppStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('queued'),
      ).withConverter<WhatsAppStatus>($WhatsAppMessagesTable.$converterstatus);
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptNumberMeta = const VerificationMeta(
    'attemptNumber',
  );
  @override
  late final GeneratedColumn<int> attemptNumber = GeneratedColumn<int>(
    'attempt_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failedAtMeta = const VerificationMeta(
    'failedAt',
  );
  @override
  late final GeneratedColumn<DateTime> failedAt = GeneratedColumn<DateTime>(
    'failed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    receiptId,
    memberId,
    phone,
    provider,
    externalMessageId,
    status,
    errorMessage,
    attemptNumber,
    sentAt,
    deliveredAt,
    readAt,
    failedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'whats_app_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<WhatsAppMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('external_message_id')) {
      context.handle(
        _externalMessageIdMeta,
        externalMessageId.isAcceptableOrUnknown(
          data['external_message_id']!,
          _externalMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('attempt_number')) {
      context.handle(
        _attemptNumberMeta,
        attemptNumber.isAcceptableOrUnknown(
          data['attempt_number']!,
          _attemptNumberMeta,
        ),
      );
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    if (data.containsKey('failed_at')) {
      context.handle(
        _failedAtMeta,
        failedAt.isAcceptableOrUnknown(data['failed_at']!, _failedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WhatsAppMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WhatsAppMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}receipt_id'],
      )!,
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_id'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      provider: $WhatsAppMessagesTable.$converterprovider.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}provider'],
        )!,
      ),
      externalMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_message_id'],
      ),
      status: $WhatsAppMessagesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      attemptNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_number'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      ),
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivered_at'],
      ),
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
      failedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}failed_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $WhatsAppMessagesTable createAlias(String alias) {
    return $WhatsAppMessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<WhatsAppProviderKind, String, String>
  $converterprovider = const EnumNameConverter<WhatsAppProviderKind>(
    WhatsAppProviderKind.values,
  );
  static JsonTypeConverter2<WhatsAppStatus, String, String> $converterstatus =
      const EnumNameConverter<WhatsAppStatus>(WhatsAppStatus.values);
}

class WhatsAppMessage extends DataClass implements Insertable<WhatsAppMessage> {
  final int id;
  final int receiptId;
  final int memberId;
  final String phone;
  final WhatsAppProviderKind provider;
  final String? externalMessageId;
  final WhatsAppStatus status;
  final String? errorMessage;
  final int attemptNumber;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? failedAt;
  final DateTime createdAt;
  const WhatsAppMessage({
    required this.id,
    required this.receiptId,
    required this.memberId,
    required this.phone,
    required this.provider,
    this.externalMessageId,
    required this.status,
    this.errorMessage,
    required this.attemptNumber,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.failedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['receipt_id'] = Variable<int>(receiptId);
    map['member_id'] = Variable<int>(memberId);
    map['phone'] = Variable<String>(phone);
    {
      map['provider'] = Variable<String>(
        $WhatsAppMessagesTable.$converterprovider.toSql(provider),
      );
    }
    if (!nullToAbsent || externalMessageId != null) {
      map['external_message_id'] = Variable<String>(externalMessageId);
    }
    {
      map['status'] = Variable<String>(
        $WhatsAppMessagesTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['attempt_number'] = Variable<int>(attemptNumber);
    if (!nullToAbsent || sentAt != null) {
      map['sent_at'] = Variable<DateTime>(sentAt);
    }
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    if (!nullToAbsent || failedAt != null) {
      map['failed_at'] = Variable<DateTime>(failedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  WhatsAppMessagesCompanion toCompanion(bool nullToAbsent) {
    return WhatsAppMessagesCompanion(
      id: Value(id),
      receiptId: Value(receiptId),
      memberId: Value(memberId),
      phone: Value(phone),
      provider: Value(provider),
      externalMessageId: externalMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalMessageId),
      status: Value(status),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      attemptNumber: Value(attemptNumber),
      sentAt: sentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sentAt),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
      failedAt: failedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(failedAt),
      createdAt: Value(createdAt),
    );
  }

  factory WhatsAppMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WhatsAppMessage(
      id: serializer.fromJson<int>(json['id']),
      receiptId: serializer.fromJson<int>(json['receiptId']),
      memberId: serializer.fromJson<int>(json['memberId']),
      phone: serializer.fromJson<String>(json['phone']),
      provider: $WhatsAppMessagesTable.$converterprovider.fromJson(
        serializer.fromJson<String>(json['provider']),
      ),
      externalMessageId: serializer.fromJson<String?>(
        json['externalMessageId'],
      ),
      status: $WhatsAppMessagesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      attemptNumber: serializer.fromJson<int>(json['attemptNumber']),
      sentAt: serializer.fromJson<DateTime?>(json['sentAt']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
      failedAt: serializer.fromJson<DateTime?>(json['failedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'receiptId': serializer.toJson<int>(receiptId),
      'memberId': serializer.toJson<int>(memberId),
      'phone': serializer.toJson<String>(phone),
      'provider': serializer.toJson<String>(
        $WhatsAppMessagesTable.$converterprovider.toJson(provider),
      ),
      'externalMessageId': serializer.toJson<String?>(externalMessageId),
      'status': serializer.toJson<String>(
        $WhatsAppMessagesTable.$converterstatus.toJson(status),
      ),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'attemptNumber': serializer.toJson<int>(attemptNumber),
      'sentAt': serializer.toJson<DateTime?>(sentAt),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'readAt': serializer.toJson<DateTime?>(readAt),
      'failedAt': serializer.toJson<DateTime?>(failedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  WhatsAppMessage copyWith({
    int? id,
    int? receiptId,
    int? memberId,
    String? phone,
    WhatsAppProviderKind? provider,
    Value<String?> externalMessageId = const Value.absent(),
    WhatsAppStatus? status,
    Value<String?> errorMessage = const Value.absent(),
    int? attemptNumber,
    Value<DateTime?> sentAt = const Value.absent(),
    Value<DateTime?> deliveredAt = const Value.absent(),
    Value<DateTime?> readAt = const Value.absent(),
    Value<DateTime?> failedAt = const Value.absent(),
    DateTime? createdAt,
  }) => WhatsAppMessage(
    id: id ?? this.id,
    receiptId: receiptId ?? this.receiptId,
    memberId: memberId ?? this.memberId,
    phone: phone ?? this.phone,
    provider: provider ?? this.provider,
    externalMessageId: externalMessageId.present
        ? externalMessageId.value
        : this.externalMessageId,
    status: status ?? this.status,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    attemptNumber: attemptNumber ?? this.attemptNumber,
    sentAt: sentAt.present ? sentAt.value : this.sentAt,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    readAt: readAt.present ? readAt.value : this.readAt,
    failedAt: failedAt.present ? failedAt.value : this.failedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  WhatsAppMessage copyWithCompanion(WhatsAppMessagesCompanion data) {
    return WhatsAppMessage(
      id: data.id.present ? data.id.value : this.id,
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      phone: data.phone.present ? data.phone.value : this.phone,
      provider: data.provider.present ? data.provider.value : this.provider,
      externalMessageId: data.externalMessageId.present
          ? data.externalMessageId.value
          : this.externalMessageId,
      status: data.status.present ? data.status.value : this.status,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      attemptNumber: data.attemptNumber.present
          ? data.attemptNumber.value
          : this.attemptNumber,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      failedAt: data.failedAt.present ? data.failedAt.value : this.failedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WhatsAppMessage(')
          ..write('id: $id, ')
          ..write('receiptId: $receiptId, ')
          ..write('memberId: $memberId, ')
          ..write('phone: $phone, ')
          ..write('provider: $provider, ')
          ..write('externalMessageId: $externalMessageId, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('attemptNumber: $attemptNumber, ')
          ..write('sentAt: $sentAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt, ')
          ..write('failedAt: $failedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    receiptId,
    memberId,
    phone,
    provider,
    externalMessageId,
    status,
    errorMessage,
    attemptNumber,
    sentAt,
    deliveredAt,
    readAt,
    failedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WhatsAppMessage &&
          other.id == this.id &&
          other.receiptId == this.receiptId &&
          other.memberId == this.memberId &&
          other.phone == this.phone &&
          other.provider == this.provider &&
          other.externalMessageId == this.externalMessageId &&
          other.status == this.status &&
          other.errorMessage == this.errorMessage &&
          other.attemptNumber == this.attemptNumber &&
          other.sentAt == this.sentAt &&
          other.deliveredAt == this.deliveredAt &&
          other.readAt == this.readAt &&
          other.failedAt == this.failedAt &&
          other.createdAt == this.createdAt);
}

class WhatsAppMessagesCompanion extends UpdateCompanion<WhatsAppMessage> {
  final Value<int> id;
  final Value<int> receiptId;
  final Value<int> memberId;
  final Value<String> phone;
  final Value<WhatsAppProviderKind> provider;
  final Value<String?> externalMessageId;
  final Value<WhatsAppStatus> status;
  final Value<String?> errorMessage;
  final Value<int> attemptNumber;
  final Value<DateTime?> sentAt;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime?> readAt;
  final Value<DateTime?> failedAt;
  final Value<DateTime> createdAt;
  const WhatsAppMessagesCompanion({
    this.id = const Value.absent(),
    this.receiptId = const Value.absent(),
    this.memberId = const Value.absent(),
    this.phone = const Value.absent(),
    this.provider = const Value.absent(),
    this.externalMessageId = const Value.absent(),
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.attemptNumber = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.failedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  WhatsAppMessagesCompanion.insert({
    this.id = const Value.absent(),
    required int receiptId,
    required int memberId,
    required String phone,
    required WhatsAppProviderKind provider,
    this.externalMessageId = const Value.absent(),
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.attemptNumber = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.failedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : receiptId = Value(receiptId),
       memberId = Value(memberId),
       phone = Value(phone),
       provider = Value(provider);
  static Insertable<WhatsAppMessage> custom({
    Expression<int>? id,
    Expression<int>? receiptId,
    Expression<int>? memberId,
    Expression<String>? phone,
    Expression<String>? provider,
    Expression<String>? externalMessageId,
    Expression<String>? status,
    Expression<String>? errorMessage,
    Expression<int>? attemptNumber,
    Expression<DateTime>? sentAt,
    Expression<DateTime>? deliveredAt,
    Expression<DateTime>? readAt,
    Expression<DateTime>? failedAt,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (receiptId != null) 'receipt_id': receiptId,
      if (memberId != null) 'member_id': memberId,
      if (phone != null) 'phone': phone,
      if (provider != null) 'provider': provider,
      if (externalMessageId != null) 'external_message_id': externalMessageId,
      if (status != null) 'status': status,
      if (errorMessage != null) 'error_message': errorMessage,
      if (attemptNumber != null) 'attempt_number': attemptNumber,
      if (sentAt != null) 'sent_at': sentAt,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (readAt != null) 'read_at': readAt,
      if (failedAt != null) 'failed_at': failedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  WhatsAppMessagesCompanion copyWith({
    Value<int>? id,
    Value<int>? receiptId,
    Value<int>? memberId,
    Value<String>? phone,
    Value<WhatsAppProviderKind>? provider,
    Value<String?>? externalMessageId,
    Value<WhatsAppStatus>? status,
    Value<String?>? errorMessage,
    Value<int>? attemptNumber,
    Value<DateTime?>? sentAt,
    Value<DateTime?>? deliveredAt,
    Value<DateTime?>? readAt,
    Value<DateTime?>? failedAt,
    Value<DateTime>? createdAt,
  }) {
    return WhatsAppMessagesCompanion(
      id: id ?? this.id,
      receiptId: receiptId ?? this.receiptId,
      memberId: memberId ?? this.memberId,
      phone: phone ?? this.phone,
      provider: provider ?? this.provider,
      externalMessageId: externalMessageId ?? this.externalMessageId,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      attemptNumber: attemptNumber ?? this.attemptNumber,
      sentAt: sentAt ?? this.sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      failedAt: failedAt ?? this.failedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (receiptId.present) {
      map['receipt_id'] = Variable<int>(receiptId.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<int>(memberId.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(
        $WhatsAppMessagesTable.$converterprovider.toSql(provider.value),
      );
    }
    if (externalMessageId.present) {
      map['external_message_id'] = Variable<String>(externalMessageId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $WhatsAppMessagesTable.$converterstatus.toSql(status.value),
      );
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (attemptNumber.present) {
      map['attempt_number'] = Variable<int>(attemptNumber.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (failedAt.present) {
      map['failed_at'] = Variable<DateTime>(failedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WhatsAppMessagesCompanion(')
          ..write('id: $id, ')
          ..write('receiptId: $receiptId, ')
          ..write('memberId: $memberId, ')
          ..write('phone: $phone, ')
          ..write('provider: $provider, ')
          ..write('externalMessageId: $externalMessageId, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('attemptNumber: $attemptNumber, ')
          ..write('sentAt: $sentAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt, ')
          ..write('failedAt: $failedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $MemberNotesTable extends MemberNotes
    with TableInfo<$MemberNotesTable, MemberNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemberNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<int> memberId = GeneratedColumn<int>(
    'member_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES members (id)',
    ),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdByIdMeta = const VerificationMeta(
    'createdById',
  );
  @override
  late final GeneratedColumn<int> createdById = GeneratedColumn<int>(
    'created_by_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    memberId,
    body,
    createdById,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'member_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemberNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('created_by_id')) {
      context.handle(
        _createdByIdMeta,
        createdById.isAcceptableOrUnknown(
          data['created_by_id']!,
          _createdByIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdByIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MemberNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemberNote(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      createdById: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_by_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MemberNotesTable createAlias(String alias) {
    return $MemberNotesTable(attachedDatabase, alias);
  }
}

class MemberNote extends DataClass implements Insertable<MemberNote> {
  final int id;
  final int memberId;
  final String body;
  final int createdById;
  final DateTime createdAt;
  const MemberNote({
    required this.id,
    required this.memberId,
    required this.body,
    required this.createdById,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['member_id'] = Variable<int>(memberId);
    map['body'] = Variable<String>(body);
    map['created_by_id'] = Variable<int>(createdById);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MemberNotesCompanion toCompanion(bool nullToAbsent) {
    return MemberNotesCompanion(
      id: Value(id),
      memberId: Value(memberId),
      body: Value(body),
      createdById: Value(createdById),
      createdAt: Value(createdAt),
    );
  }

  factory MemberNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemberNote(
      id: serializer.fromJson<int>(json['id']),
      memberId: serializer.fromJson<int>(json['memberId']),
      body: serializer.fromJson<String>(json['body']),
      createdById: serializer.fromJson<int>(json['createdById']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'memberId': serializer.toJson<int>(memberId),
      'body': serializer.toJson<String>(body),
      'createdById': serializer.toJson<int>(createdById),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MemberNote copyWith({
    int? id,
    int? memberId,
    String? body,
    int? createdById,
    DateTime? createdAt,
  }) => MemberNote(
    id: id ?? this.id,
    memberId: memberId ?? this.memberId,
    body: body ?? this.body,
    createdById: createdById ?? this.createdById,
    createdAt: createdAt ?? this.createdAt,
  );
  MemberNote copyWithCompanion(MemberNotesCompanion data) {
    return MemberNote(
      id: data.id.present ? data.id.value : this.id,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      body: data.body.present ? data.body.value : this.body,
      createdById: data.createdById.present
          ? data.createdById.value
          : this.createdById,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemberNote(')
          ..write('id: $id, ')
          ..write('memberId: $memberId, ')
          ..write('body: $body, ')
          ..write('createdById: $createdById, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, memberId, body, createdById, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemberNote &&
          other.id == this.id &&
          other.memberId == this.memberId &&
          other.body == this.body &&
          other.createdById == this.createdById &&
          other.createdAt == this.createdAt);
}

class MemberNotesCompanion extends UpdateCompanion<MemberNote> {
  final Value<int> id;
  final Value<int> memberId;
  final Value<String> body;
  final Value<int> createdById;
  final Value<DateTime> createdAt;
  const MemberNotesCompanion({
    this.id = const Value.absent(),
    this.memberId = const Value.absent(),
    this.body = const Value.absent(),
    this.createdById = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MemberNotesCompanion.insert({
    this.id = const Value.absent(),
    required int memberId,
    required String body,
    required int createdById,
    this.createdAt = const Value.absent(),
  }) : memberId = Value(memberId),
       body = Value(body),
       createdById = Value(createdById);
  static Insertable<MemberNote> custom({
    Expression<int>? id,
    Expression<int>? memberId,
    Expression<String>? body,
    Expression<int>? createdById,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (memberId != null) 'member_id': memberId,
      if (body != null) 'body': body,
      if (createdById != null) 'created_by_id': createdById,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MemberNotesCompanion copyWith({
    Value<int>? id,
    Value<int>? memberId,
    Value<String>? body,
    Value<int>? createdById,
    Value<DateTime>? createdAt,
  }) {
    return MemberNotesCompanion(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      body: body ?? this.body,
      createdById: createdById ?? this.createdById,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<int>(memberId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdById.present) {
      map['created_by_id'] = Variable<int>(createdById.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemberNotesCompanion(')
          ..write('id: $id, ')
          ..write('memberId: $memberId, ')
          ..write('body: $body, ')
          ..write('createdById: $createdById, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AuditEventsTable extends AuditEvents
    with TableInfo<$AuditEventsTable, AuditEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<AuditCategory, String> category =
      GeneratedColumn<String>(
        'category',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AuditCategory>($AuditEventsTable.$convertercategory);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AuditOutcome, String> outcome =
      GeneratedColumn<String>(
        'outcome',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AuditOutcome>($AuditEventsTable.$converteroutcome);
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<int> actorId = GeneratedColumn<int>(
    'actor_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actorNameMeta = const VerificationMeta(
    'actorName',
  );
  @override
  late final GeneratedColumn<String> actorName = GeneratedColumn<String>(
    'actor_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<int> memberId = GeneratedColumn<int>(
    'member_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memberNameMeta = const VerificationMeta(
    'memberName',
  );
  @override
  late final GeneratedColumn<String> memberName = GeneratedColumn<String>(
    'member_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentIdMeta = const VerificationMeta(
    'paymentId',
  );
  @override
  late final GeneratedColumn<int> paymentId = GeneratedColumn<int>(
    'payment_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptNumberMeta = const VerificationMeta(
    'receiptNumber',
  );
  @override
  late final GeneratedColumn<String> receiptNumber = GeneratedColumn<String>(
    'receipt_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _periodLabelMeta = const VerificationMeta(
    'periodLabel',
  );
  @override
  late final GeneratedColumn<String> periodLabel = GeneratedColumn<String>(
    'period_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    category,
    action,
    outcome,
    actorId,
    actorName,
    memberId,
    memberName,
    paymentId,
    receiptNumber,
    amountMinor,
    periodLabel,
    summary,
    detail,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    }
    if (data.containsKey('actor_name')) {
      context.handle(
        _actorNameMeta,
        actorName.isAcceptableOrUnknown(data['actor_name']!, _actorNameMeta),
      );
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    }
    if (data.containsKey('member_name')) {
      context.handle(
        _memberNameMeta,
        memberName.isAcceptableOrUnknown(data['member_name']!, _memberNameMeta),
      );
    }
    if (data.containsKey('payment_id')) {
      context.handle(
        _paymentIdMeta,
        paymentId.isAcceptableOrUnknown(data['payment_id']!, _paymentIdMeta),
      );
    }
    if (data.containsKey('receipt_number')) {
      context.handle(
        _receiptNumberMeta,
        receiptNumber.isAcceptableOrUnknown(
          data['receipt_number']!,
          _receiptNumberMeta,
        ),
      );
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    }
    if (data.containsKey('period_label')) {
      context.handle(
        _periodLabelMeta,
        periodLabel.isAcceptableOrUnknown(
          data['period_label']!,
          _periodLabelMeta,
        ),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      category: $AuditEventsTable.$convertercategory.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}category'],
        )!,
      ),
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      outcome: $AuditEventsTable.$converteroutcome.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}outcome'],
        )!,
      ),
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actor_id'],
      ),
      actorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_name'],
      ),
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_id'],
      ),
      memberName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_name'],
      ),
      paymentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payment_id'],
      ),
      receiptNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_number'],
      ),
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      ),
      periodLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_label'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AuditEventsTable createAlias(String alias) {
    return $AuditEventsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AuditCategory, String, String> $convertercategory =
      const EnumNameConverter<AuditCategory>(AuditCategory.values);
  static JsonTypeConverter2<AuditOutcome, String, String> $converteroutcome =
      const EnumNameConverter<AuditOutcome>(AuditOutcome.values);
}

class AuditEvent extends DataClass implements Insertable<AuditEvent> {
  final int id;
  final AuditCategory category;

  /// Dotted machine name, e.g. 'payment.edited'. Paired with [summary] rather
  /// than shown to the owner directly.
  final String action;
  final AuditOutcome outcome;

  /// Who did it. Copied, not referenced — see the class comment.
  final int? actorId;
  final String? actorName;

  /// What it was done to. Also copied.
  final int? memberId;
  final String? memberName;
  final int? paymentId;
  final String? receiptNumber;

  /// Minor units, matching Payments.amountMinor.
  final int? amountMinor;

  /// Already formatted, e.g. "August 2026 - October 2026". Stored rather than
  /// derived because the cycle it describes may no longer exist.
  final String? periodLabel;

  /// One readable line, e.g. "Payment edited for Ali Raza (RMF-2026-000012)".
  final String summary;

  /// Supporting detail, one "Field: before → after" per line, or an error
  /// category. Never holds tokens, credentials or raw API response bodies.
  final String? detail;
  final DateTime createdAt;
  const AuditEvent({
    required this.id,
    required this.category,
    required this.action,
    required this.outcome,
    this.actorId,
    this.actorName,
    this.memberId,
    this.memberName,
    this.paymentId,
    this.receiptNumber,
    this.amountMinor,
    this.periodLabel,
    required this.summary,
    this.detail,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['category'] = Variable<String>(
        $AuditEventsTable.$convertercategory.toSql(category),
      );
    }
    map['action'] = Variable<String>(action);
    {
      map['outcome'] = Variable<String>(
        $AuditEventsTable.$converteroutcome.toSql(outcome),
      );
    }
    if (!nullToAbsent || actorId != null) {
      map['actor_id'] = Variable<int>(actorId);
    }
    if (!nullToAbsent || actorName != null) {
      map['actor_name'] = Variable<String>(actorName);
    }
    if (!nullToAbsent || memberId != null) {
      map['member_id'] = Variable<int>(memberId);
    }
    if (!nullToAbsent || memberName != null) {
      map['member_name'] = Variable<String>(memberName);
    }
    if (!nullToAbsent || paymentId != null) {
      map['payment_id'] = Variable<int>(paymentId);
    }
    if (!nullToAbsent || receiptNumber != null) {
      map['receipt_number'] = Variable<String>(receiptNumber);
    }
    if (!nullToAbsent || amountMinor != null) {
      map['amount_minor'] = Variable<int>(amountMinor);
    }
    if (!nullToAbsent || periodLabel != null) {
      map['period_label'] = Variable<String>(periodLabel);
    }
    map['summary'] = Variable<String>(summary);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AuditEventsCompanion toCompanion(bool nullToAbsent) {
    return AuditEventsCompanion(
      id: Value(id),
      category: Value(category),
      action: Value(action),
      outcome: Value(outcome),
      actorId: actorId == null && nullToAbsent
          ? const Value.absent()
          : Value(actorId),
      actorName: actorName == null && nullToAbsent
          ? const Value.absent()
          : Value(actorName),
      memberId: memberId == null && nullToAbsent
          ? const Value.absent()
          : Value(memberId),
      memberName: memberName == null && nullToAbsent
          ? const Value.absent()
          : Value(memberName),
      paymentId: paymentId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentId),
      receiptNumber: receiptNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptNumber),
      amountMinor: amountMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(amountMinor),
      periodLabel: periodLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(periodLabel),
      summary: Value(summary),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
      createdAt: Value(createdAt),
    );
  }

  factory AuditEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditEvent(
      id: serializer.fromJson<int>(json['id']),
      category: $AuditEventsTable.$convertercategory.fromJson(
        serializer.fromJson<String>(json['category']),
      ),
      action: serializer.fromJson<String>(json['action']),
      outcome: $AuditEventsTable.$converteroutcome.fromJson(
        serializer.fromJson<String>(json['outcome']),
      ),
      actorId: serializer.fromJson<int?>(json['actorId']),
      actorName: serializer.fromJson<String?>(json['actorName']),
      memberId: serializer.fromJson<int?>(json['memberId']),
      memberName: serializer.fromJson<String?>(json['memberName']),
      paymentId: serializer.fromJson<int?>(json['paymentId']),
      receiptNumber: serializer.fromJson<String?>(json['receiptNumber']),
      amountMinor: serializer.fromJson<int?>(json['amountMinor']),
      periodLabel: serializer.fromJson<String?>(json['periodLabel']),
      summary: serializer.fromJson<String>(json['summary']),
      detail: serializer.fromJson<String?>(json['detail']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'category': serializer.toJson<String>(
        $AuditEventsTable.$convertercategory.toJson(category),
      ),
      'action': serializer.toJson<String>(action),
      'outcome': serializer.toJson<String>(
        $AuditEventsTable.$converteroutcome.toJson(outcome),
      ),
      'actorId': serializer.toJson<int?>(actorId),
      'actorName': serializer.toJson<String?>(actorName),
      'memberId': serializer.toJson<int?>(memberId),
      'memberName': serializer.toJson<String?>(memberName),
      'paymentId': serializer.toJson<int?>(paymentId),
      'receiptNumber': serializer.toJson<String?>(receiptNumber),
      'amountMinor': serializer.toJson<int?>(amountMinor),
      'periodLabel': serializer.toJson<String?>(periodLabel),
      'summary': serializer.toJson<String>(summary),
      'detail': serializer.toJson<String?>(detail),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AuditEvent copyWith({
    int? id,
    AuditCategory? category,
    String? action,
    AuditOutcome? outcome,
    Value<int?> actorId = const Value.absent(),
    Value<String?> actorName = const Value.absent(),
    Value<int?> memberId = const Value.absent(),
    Value<String?> memberName = const Value.absent(),
    Value<int?> paymentId = const Value.absent(),
    Value<String?> receiptNumber = const Value.absent(),
    Value<int?> amountMinor = const Value.absent(),
    Value<String?> periodLabel = const Value.absent(),
    String? summary,
    Value<String?> detail = const Value.absent(),
    DateTime? createdAt,
  }) => AuditEvent(
    id: id ?? this.id,
    category: category ?? this.category,
    action: action ?? this.action,
    outcome: outcome ?? this.outcome,
    actorId: actorId.present ? actorId.value : this.actorId,
    actorName: actorName.present ? actorName.value : this.actorName,
    memberId: memberId.present ? memberId.value : this.memberId,
    memberName: memberName.present ? memberName.value : this.memberName,
    paymentId: paymentId.present ? paymentId.value : this.paymentId,
    receiptNumber: receiptNumber.present
        ? receiptNumber.value
        : this.receiptNumber,
    amountMinor: amountMinor.present ? amountMinor.value : this.amountMinor,
    periodLabel: periodLabel.present ? periodLabel.value : this.periodLabel,
    summary: summary ?? this.summary,
    detail: detail.present ? detail.value : this.detail,
    createdAt: createdAt ?? this.createdAt,
  );
  AuditEvent copyWithCompanion(AuditEventsCompanion data) {
    return AuditEvent(
      id: data.id.present ? data.id.value : this.id,
      category: data.category.present ? data.category.value : this.category,
      action: data.action.present ? data.action.value : this.action,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      actorName: data.actorName.present ? data.actorName.value : this.actorName,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      memberName: data.memberName.present
          ? data.memberName.value
          : this.memberName,
      paymentId: data.paymentId.present ? data.paymentId.value : this.paymentId,
      receiptNumber: data.receiptNumber.present
          ? data.receiptNumber.value
          : this.receiptNumber,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      periodLabel: data.periodLabel.present
          ? data.periodLabel.value
          : this.periodLabel,
      summary: data.summary.present ? data.summary.value : this.summary,
      detail: data.detail.present ? data.detail.value : this.detail,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditEvent(')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('action: $action, ')
          ..write('outcome: $outcome, ')
          ..write('actorId: $actorId, ')
          ..write('actorName: $actorName, ')
          ..write('memberId: $memberId, ')
          ..write('memberName: $memberName, ')
          ..write('paymentId: $paymentId, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('periodLabel: $periodLabel, ')
          ..write('summary: $summary, ')
          ..write('detail: $detail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    category,
    action,
    outcome,
    actorId,
    actorName,
    memberId,
    memberName,
    paymentId,
    receiptNumber,
    amountMinor,
    periodLabel,
    summary,
    detail,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditEvent &&
          other.id == this.id &&
          other.category == this.category &&
          other.action == this.action &&
          other.outcome == this.outcome &&
          other.actorId == this.actorId &&
          other.actorName == this.actorName &&
          other.memberId == this.memberId &&
          other.memberName == this.memberName &&
          other.paymentId == this.paymentId &&
          other.receiptNumber == this.receiptNumber &&
          other.amountMinor == this.amountMinor &&
          other.periodLabel == this.periodLabel &&
          other.summary == this.summary &&
          other.detail == this.detail &&
          other.createdAt == this.createdAt);
}

class AuditEventsCompanion extends UpdateCompanion<AuditEvent> {
  final Value<int> id;
  final Value<AuditCategory> category;
  final Value<String> action;
  final Value<AuditOutcome> outcome;
  final Value<int?> actorId;
  final Value<String?> actorName;
  final Value<int?> memberId;
  final Value<String?> memberName;
  final Value<int?> paymentId;
  final Value<String?> receiptNumber;
  final Value<int?> amountMinor;
  final Value<String?> periodLabel;
  final Value<String> summary;
  final Value<String?> detail;
  final Value<DateTime> createdAt;
  const AuditEventsCompanion({
    this.id = const Value.absent(),
    this.category = const Value.absent(),
    this.action = const Value.absent(),
    this.outcome = const Value.absent(),
    this.actorId = const Value.absent(),
    this.actorName = const Value.absent(),
    this.memberId = const Value.absent(),
    this.memberName = const Value.absent(),
    this.paymentId = const Value.absent(),
    this.receiptNumber = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.periodLabel = const Value.absent(),
    this.summary = const Value.absent(),
    this.detail = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  AuditEventsCompanion.insert({
    this.id = const Value.absent(),
    required AuditCategory category,
    required String action,
    required AuditOutcome outcome,
    this.actorId = const Value.absent(),
    this.actorName = const Value.absent(),
    this.memberId = const Value.absent(),
    this.memberName = const Value.absent(),
    this.paymentId = const Value.absent(),
    this.receiptNumber = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.periodLabel = const Value.absent(),
    required String summary,
    this.detail = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : category = Value(category),
       action = Value(action),
       outcome = Value(outcome),
       summary = Value(summary);
  static Insertable<AuditEvent> custom({
    Expression<int>? id,
    Expression<String>? category,
    Expression<String>? action,
    Expression<String>? outcome,
    Expression<int>? actorId,
    Expression<String>? actorName,
    Expression<int>? memberId,
    Expression<String>? memberName,
    Expression<int>? paymentId,
    Expression<String>? receiptNumber,
    Expression<int>? amountMinor,
    Expression<String>? periodLabel,
    Expression<String>? summary,
    Expression<String>? detail,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (category != null) 'category': category,
      if (action != null) 'action': action,
      if (outcome != null) 'outcome': outcome,
      if (actorId != null) 'actor_id': actorId,
      if (actorName != null) 'actor_name': actorName,
      if (memberId != null) 'member_id': memberId,
      if (memberName != null) 'member_name': memberName,
      if (paymentId != null) 'payment_id': paymentId,
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (periodLabel != null) 'period_label': periodLabel,
      if (summary != null) 'summary': summary,
      if (detail != null) 'detail': detail,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  AuditEventsCompanion copyWith({
    Value<int>? id,
    Value<AuditCategory>? category,
    Value<String>? action,
    Value<AuditOutcome>? outcome,
    Value<int?>? actorId,
    Value<String?>? actorName,
    Value<int?>? memberId,
    Value<String?>? memberName,
    Value<int?>? paymentId,
    Value<String?>? receiptNumber,
    Value<int?>? amountMinor,
    Value<String?>? periodLabel,
    Value<String>? summary,
    Value<String?>? detail,
    Value<DateTime>? createdAt,
  }) {
    return AuditEventsCompanion(
      id: id ?? this.id,
      category: category ?? this.category,
      action: action ?? this.action,
      outcome: outcome ?? this.outcome,
      actorId: actorId ?? this.actorId,
      actorName: actorName ?? this.actorName,
      memberId: memberId ?? this.memberId,
      memberName: memberName ?? this.memberName,
      paymentId: paymentId ?? this.paymentId,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      amountMinor: amountMinor ?? this.amountMinor,
      periodLabel: periodLabel ?? this.periodLabel,
      summary: summary ?? this.summary,
      detail: detail ?? this.detail,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(
        $AuditEventsTable.$convertercategory.toSql(category.value),
      );
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(
        $AuditEventsTable.$converteroutcome.toSql(outcome.value),
      );
    }
    if (actorId.present) {
      map['actor_id'] = Variable<int>(actorId.value);
    }
    if (actorName.present) {
      map['actor_name'] = Variable<String>(actorName.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<int>(memberId.value);
    }
    if (memberName.present) {
      map['member_name'] = Variable<String>(memberName.value);
    }
    if (paymentId.present) {
      map['payment_id'] = Variable<int>(paymentId.value);
    }
    if (receiptNumber.present) {
      map['receipt_number'] = Variable<String>(receiptNumber.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (periodLabel.present) {
      map['period_label'] = Variable<String>(periodLabel.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditEventsCompanion(')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('action: $action, ')
          ..write('outcome: $outcome, ')
          ..write('actorId: $actorId, ')
          ..write('actorName: $actorName, ')
          ..write('memberId: $memberId, ')
          ..write('memberName: $memberName, ')
          ..write('paymentId: $paymentId, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('periodLabel: $periodLabel, ')
          ..write('summary: $summary, ')
          ..write('detail: $detail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTable users = $UsersTable(this);
  late final $AppSessionsTable appSessions = $AppSessionsTable(this);
  late final $GymSettingsTable gymSettings = $GymSettingsTable(this);
  late final $MembershipPlansTable membershipPlans = $MembershipPlansTable(
    this,
  );
  late final $MembersTable members = $MembersTable(this);
  late final $MembershipsTable memberships = $MembershipsTable(this);
  late final $MembershipPeriodsTable membershipPeriods =
      $MembershipPeriodsTable(this);
  late final $PaymentsTable payments = $PaymentsTable(this);
  late final $ReceiptsTable receipts = $ReceiptsTable(this);
  late final $ReceiptCountersTable receiptCounters = $ReceiptCountersTable(
    this,
  );
  late final $WhatsAppMessagesTable whatsAppMessages = $WhatsAppMessagesTable(
    this,
  );
  late final $MemberNotesTable memberNotes = $MemberNotesTable(this);
  late final $AuditEventsTable auditEvents = $AuditEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    users,
    appSessions,
    gymSettings,
    membershipPlans,
    members,
    memberships,
    membershipPeriods,
    payments,
    receipts,
    receiptCounters,
    whatsAppMessages,
    memberNotes,
    auditEvents,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'users',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('app_sessions', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      Value<int> id,
      required String name,
      required String email,
      required String passwordHash,
      Value<UserRole> role,
      Value<DateTime> createdAt,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> email,
      Value<String> passwordHash,
      Value<UserRole> role,
      Value<DateTime> createdAt,
    });

final class $$UsersTableReferences
    extends BaseReferences<_$AppDatabase, $UsersTable, User> {
  $$UsersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AppSessionsTable, List<AppSession>>
  _appSessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.appSessions,
    aliasName: 'users__id__app_sessions__user_id',
  );

  $$AppSessionsTableProcessedTableManager get appSessionsRefs {
    final manager = $$AppSessionsTableTableManager(
      $_db,
      $_db.appSessions,
    ).filter((f) => f.userId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_appSessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MemberNotesTable, List<MemberNote>>
  _memberNotesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.memberNotes,
    aliasName: 'users__id__member_notes__created_by_id',
  );

  $$MemberNotesTableProcessedTableManager get memberNotesRefs {
    final manager = $$MemberNotesTableTableManager(
      $_db,
      $_db.memberNotes,
    ).filter((f) => f.createdById.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_memberNotesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<UserRole, UserRole, String> get role =>
      $composableBuilder(
        column: $table.role,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> appSessionsRefs(
    Expression<bool> Function($$AppSessionsTableFilterComposer f) f,
  ) {
    final $$AppSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.appSessions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AppSessionsTableFilterComposer(
            $db: $db,
            $table: $db.appSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> memberNotesRefs(
    Expression<bool> Function($$MemberNotesTableFilterComposer f) f,
  ) {
    final $$MemberNotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memberNotes,
      getReferencedColumn: (t) => t.createdById,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MemberNotesTableFilterComposer(
            $db: $db,
            $table: $db.memberNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<UserRole, String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> appSessionsRefs<T extends Object>(
    Expression<T> Function($$AppSessionsTableAnnotationComposer a) f,
  ) {
    final $$AppSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.appSessions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AppSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.appSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> memberNotesRefs<T extends Object>(
    Expression<T> Function($$MemberNotesTableAnnotationComposer a) f,
  ) {
    final $$MemberNotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memberNotes,
      getReferencedColumn: (t) => t.createdById,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MemberNotesTableAnnotationComposer(
            $db: $db,
            $table: $db.memberNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, $$UsersTableReferences),
          User,
          PrefetchHooks Function({bool appSessionsRefs, bool memberNotesRefs})
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String> passwordHash = const Value.absent(),
                Value<UserRole> role = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => UsersCompanion(
                id: id,
                name: name,
                email: email,
                passwordHash: passwordHash,
                role: role,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String email,
                required String passwordHash,
                Value<UserRole> role = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => UsersCompanion.insert(
                id: id,
                name: name,
                email: email,
                passwordHash: passwordHash,
                role: role,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$UsersTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({appSessionsRefs = false, memberNotesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (appSessionsRefs) db.appSessions,
                    if (memberNotesRefs) db.memberNotes,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (appSessionsRefs)
                        await $_getPrefetchedData<
                          User,
                          $UsersTable,
                          AppSession
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._appSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).appSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (memberNotesRefs)
                        await $_getPrefetchedData<
                          User,
                          $UsersTable,
                          MemberNote
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._memberNotesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).memberNotesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.createdById == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, $$UsersTableReferences),
      User,
      PrefetchHooks Function({bool appSessionsRefs, bool memberNotesRefs})
    >;
typedef $$AppSessionsTableCreateCompanionBuilder =
    AppSessionsCompanion Function({
      Value<int> id,
      Value<int?> userId,
      Value<DateTime?> signedInAt,
    });
typedef $$AppSessionsTableUpdateCompanionBuilder =
    AppSessionsCompanion Function({
      Value<int> id,
      Value<int?> userId,
      Value<DateTime?> signedInAt,
    });

final class $$AppSessionsTableReferences
    extends BaseReferences<_$AppDatabase, $AppSessionsTable, AppSession> {
  $$AppSessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UsersTable _userIdTable(_$AppDatabase db) =>
      db.users.createAlias('app_sessions__user_id__users__id');

  $$UsersTableProcessedTableManager? get userId {
    final $_column = $_itemColumn<int>('user_id');
    if ($_column == null) return null;
    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AppSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSessionsTable> {
  $$AppSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get signedInAt => $composableBuilder(
    column: $table.signedInAt,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSessionsTable> {
  $$AppSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get signedInAt => $composableBuilder(
    column: $table.signedInAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSessionsTable> {
  $$AppSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get signedInAt => $composableBuilder(
    column: $table.signedInAt,
    builder: (column) => column,
  );

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSessionsTable,
          AppSession,
          $$AppSessionsTableFilterComposer,
          $$AppSessionsTableOrderingComposer,
          $$AppSessionsTableAnnotationComposer,
          $$AppSessionsTableCreateCompanionBuilder,
          $$AppSessionsTableUpdateCompanionBuilder,
          (AppSession, $$AppSessionsTableReferences),
          AppSession,
          PrefetchHooks Function({bool userId})
        > {
  $$AppSessionsTableTableManager(_$AppDatabase db, $AppSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> userId = const Value.absent(),
                Value<DateTime?> signedInAt = const Value.absent(),
              }) => AppSessionsCompanion(
                id: id,
                userId: userId,
                signedInAt: signedInAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> userId = const Value.absent(),
                Value<DateTime?> signedInAt = const Value.absent(),
              }) => AppSessionsCompanion.insert(
                id: id,
                userId: userId,
                signedInAt: signedInAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AppSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable: $$AppSessionsTableReferences
                                    ._userIdTable(db),
                                referencedColumn: $$AppSessionsTableReferences
                                    ._userIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AppSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSessionsTable,
      AppSession,
      $$AppSessionsTableFilterComposer,
      $$AppSessionsTableOrderingComposer,
      $$AppSessionsTableAnnotationComposer,
      $$AppSessionsTableCreateCompanionBuilder,
      $$AppSessionsTableUpdateCompanionBuilder,
      (AppSession, $$AppSessionsTableReferences),
      AppSession,
      PrefetchHooks Function({bool userId})
    >;
typedef $$GymSettingsTableCreateCompanionBuilder =
    GymSettingsCompanion Function({
      Value<int> id,
      Value<String> gymName,
      Value<String?> logoPath,
      Value<String?> phone,
      Value<String?> whatsappPhone,
      Value<String?> email,
      Value<String?> address,
      Value<String?> openingHours,
      Value<String> currency,
      Value<String> receiptPrefix,
      Value<String> receiptFooterMessage,
      Value<WhatsAppProviderKind> whatsappProvider,
      Value<String?> whatsappPhoneNumberId,
      Value<String?> whatsappAccessToken,
      Value<String?> whatsappBusinessAccountId,
      Value<String?> whatsappBusinessNumber,
      Value<bool> whatsappMockFails,
      Value<String> themeMode,
    });
typedef $$GymSettingsTableUpdateCompanionBuilder =
    GymSettingsCompanion Function({
      Value<int> id,
      Value<String> gymName,
      Value<String?> logoPath,
      Value<String?> phone,
      Value<String?> whatsappPhone,
      Value<String?> email,
      Value<String?> address,
      Value<String?> openingHours,
      Value<String> currency,
      Value<String> receiptPrefix,
      Value<String> receiptFooterMessage,
      Value<WhatsAppProviderKind> whatsappProvider,
      Value<String?> whatsappPhoneNumberId,
      Value<String?> whatsappAccessToken,
      Value<String?> whatsappBusinessAccountId,
      Value<String?> whatsappBusinessNumber,
      Value<bool> whatsappMockFails,
      Value<String> themeMode,
    });

class $$GymSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $GymSettingsTable> {
  $$GymSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gymName => $composableBuilder(
    column: $table.gymName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logoPath => $composableBuilder(
    column: $table.logoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get whatsappPhone => $composableBuilder(
    column: $table.whatsappPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get openingHours => $composableBuilder(
    column: $table.openingHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptPrefix => $composableBuilder(
    column: $table.receiptPrefix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptFooterMessage => $composableBuilder(
    column: $table.receiptFooterMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    WhatsAppProviderKind,
    WhatsAppProviderKind,
    String
  >
  get whatsappProvider => $composableBuilder(
    column: $table.whatsappProvider,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get whatsappPhoneNumberId => $composableBuilder(
    column: $table.whatsappPhoneNumberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get whatsappAccessToken => $composableBuilder(
    column: $table.whatsappAccessToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get whatsappBusinessAccountId => $composableBuilder(
    column: $table.whatsappBusinessAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get whatsappBusinessNumber => $composableBuilder(
    column: $table.whatsappBusinessNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get whatsappMockFails => $composableBuilder(
    column: $table.whatsappMockFails,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GymSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $GymSettingsTable> {
  $$GymSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gymName => $composableBuilder(
    column: $table.gymName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logoPath => $composableBuilder(
    column: $table.logoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get whatsappPhone => $composableBuilder(
    column: $table.whatsappPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get openingHours => $composableBuilder(
    column: $table.openingHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptPrefix => $composableBuilder(
    column: $table.receiptPrefix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptFooterMessage => $composableBuilder(
    column: $table.receiptFooterMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get whatsappProvider => $composableBuilder(
    column: $table.whatsappProvider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get whatsappPhoneNumberId => $composableBuilder(
    column: $table.whatsappPhoneNumberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get whatsappAccessToken => $composableBuilder(
    column: $table.whatsappAccessToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get whatsappBusinessAccountId => $composableBuilder(
    column: $table.whatsappBusinessAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get whatsappBusinessNumber => $composableBuilder(
    column: $table.whatsappBusinessNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get whatsappMockFails => $composableBuilder(
    column: $table.whatsappMockFails,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GymSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GymSettingsTable> {
  $$GymSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gymName =>
      $composableBuilder(column: $table.gymName, builder: (column) => column);

  GeneratedColumn<String> get logoPath =>
      $composableBuilder(column: $table.logoPath, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get whatsappPhone => $composableBuilder(
    column: $table.whatsappPhone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get openingHours => $composableBuilder(
    column: $table.openingHours,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get receiptPrefix => $composableBuilder(
    column: $table.receiptPrefix,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptFooterMessage => $composableBuilder(
    column: $table.receiptFooterMessage,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<WhatsAppProviderKind, String>
  get whatsappProvider => $composableBuilder(
    column: $table.whatsappProvider,
    builder: (column) => column,
  );

  GeneratedColumn<String> get whatsappPhoneNumberId => $composableBuilder(
    column: $table.whatsappPhoneNumberId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get whatsappAccessToken => $composableBuilder(
    column: $table.whatsappAccessToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get whatsappBusinessAccountId => $composableBuilder(
    column: $table.whatsappBusinessAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get whatsappBusinessNumber => $composableBuilder(
    column: $table.whatsappBusinessNumber,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get whatsappMockFails => $composableBuilder(
    column: $table.whatsappMockFails,
    builder: (column) => column,
  );

  GeneratedColumn<String> get themeMode =>
      $composableBuilder(column: $table.themeMode, builder: (column) => column);
}

class $$GymSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GymSettingsTable,
          GymSetting,
          $$GymSettingsTableFilterComposer,
          $$GymSettingsTableOrderingComposer,
          $$GymSettingsTableAnnotationComposer,
          $$GymSettingsTableCreateCompanionBuilder,
          $$GymSettingsTableUpdateCompanionBuilder,
          (
            GymSetting,
            BaseReferences<_$AppDatabase, $GymSettingsTable, GymSetting>,
          ),
          GymSetting,
          PrefetchHooks Function()
        > {
  $$GymSettingsTableTableManager(_$AppDatabase db, $GymSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GymSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GymSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GymSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> gymName = const Value.absent(),
                Value<String?> logoPath = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> whatsappPhone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> openingHours = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> receiptPrefix = const Value.absent(),
                Value<String> receiptFooterMessage = const Value.absent(),
                Value<WhatsAppProviderKind> whatsappProvider =
                    const Value.absent(),
                Value<String?> whatsappPhoneNumberId = const Value.absent(),
                Value<String?> whatsappAccessToken = const Value.absent(),
                Value<String?> whatsappBusinessAccountId = const Value.absent(),
                Value<String?> whatsappBusinessNumber = const Value.absent(),
                Value<bool> whatsappMockFails = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
              }) => GymSettingsCompanion(
                id: id,
                gymName: gymName,
                logoPath: logoPath,
                phone: phone,
                whatsappPhone: whatsappPhone,
                email: email,
                address: address,
                openingHours: openingHours,
                currency: currency,
                receiptPrefix: receiptPrefix,
                receiptFooterMessage: receiptFooterMessage,
                whatsappProvider: whatsappProvider,
                whatsappPhoneNumberId: whatsappPhoneNumberId,
                whatsappAccessToken: whatsappAccessToken,
                whatsappBusinessAccountId: whatsappBusinessAccountId,
                whatsappBusinessNumber: whatsappBusinessNumber,
                whatsappMockFails: whatsappMockFails,
                themeMode: themeMode,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> gymName = const Value.absent(),
                Value<String?> logoPath = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> whatsappPhone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> openingHours = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> receiptPrefix = const Value.absent(),
                Value<String> receiptFooterMessage = const Value.absent(),
                Value<WhatsAppProviderKind> whatsappProvider =
                    const Value.absent(),
                Value<String?> whatsappPhoneNumberId = const Value.absent(),
                Value<String?> whatsappAccessToken = const Value.absent(),
                Value<String?> whatsappBusinessAccountId = const Value.absent(),
                Value<String?> whatsappBusinessNumber = const Value.absent(),
                Value<bool> whatsappMockFails = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
              }) => GymSettingsCompanion.insert(
                id: id,
                gymName: gymName,
                logoPath: logoPath,
                phone: phone,
                whatsappPhone: whatsappPhone,
                email: email,
                address: address,
                openingHours: openingHours,
                currency: currency,
                receiptPrefix: receiptPrefix,
                receiptFooterMessage: receiptFooterMessage,
                whatsappProvider: whatsappProvider,
                whatsappPhoneNumberId: whatsappPhoneNumberId,
                whatsappAccessToken: whatsappAccessToken,
                whatsappBusinessAccountId: whatsappBusinessAccountId,
                whatsappBusinessNumber: whatsappBusinessNumber,
                whatsappMockFails: whatsappMockFails,
                themeMode: themeMode,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GymSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GymSettingsTable,
      GymSetting,
      $$GymSettingsTableFilterComposer,
      $$GymSettingsTableOrderingComposer,
      $$GymSettingsTableAnnotationComposer,
      $$GymSettingsTableCreateCompanionBuilder,
      $$GymSettingsTableUpdateCompanionBuilder,
      (
        GymSetting,
        BaseReferences<_$AppDatabase, $GymSettingsTable, GymSetting>,
      ),
      GymSetting,
      PrefetchHooks Function()
    >;
typedef $$MembershipPlansTableCreateCompanionBuilder =
    MembershipPlansCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> description,
      required int durationMonths,
      required int priceMinor,
      Value<bool> isActive,
    });
typedef $$MembershipPlansTableUpdateCompanionBuilder =
    MembershipPlansCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> description,
      Value<int> durationMonths,
      Value<int> priceMinor,
      Value<bool> isActive,
    });

final class $$MembershipPlansTableReferences
    extends
        BaseReferences<_$AppDatabase, $MembershipPlansTable, MembershipPlan> {
  $$MembershipPlansTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$MembershipsTable, List<Membership>>
  _membershipsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.memberships,
    aliasName: 'membership_plans__id__memberships__plan_id',
  );

  $$MembershipsTableProcessedTableManager get membershipsRefs {
    final manager = $$MembershipsTableTableManager(
      $_db,
      $_db.memberships,
    ).filter((f) => f.planId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_membershipsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MembershipPlansTableFilterComposer
    extends Composer<_$AppDatabase, $MembershipPlansTable> {
  $$MembershipPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMonths => $composableBuilder(
    column: $table.durationMonths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> membershipsRefs(
    Expression<bool> Function($$MembershipsTableFilterComposer f) f,
  ) {
    final $$MembershipsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableFilterComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembershipPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $MembershipPlansTable> {
  $$MembershipPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMonths => $composableBuilder(
    column: $table.durationMonths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MembershipPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembershipPlansTable> {
  $$MembershipPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMonths => $composableBuilder(
    column: $table.durationMonths,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  Expression<T> membershipsRefs<T extends Object>(
    Expression<T> Function($$MembershipsTableAnnotationComposer a) f,
  ) {
    final $$MembershipsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableAnnotationComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembershipPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MembershipPlansTable,
          MembershipPlan,
          $$MembershipPlansTableFilterComposer,
          $$MembershipPlansTableOrderingComposer,
          $$MembershipPlansTableAnnotationComposer,
          $$MembershipPlansTableCreateCompanionBuilder,
          $$MembershipPlansTableUpdateCompanionBuilder,
          (MembershipPlan, $$MembershipPlansTableReferences),
          MembershipPlan,
          PrefetchHooks Function({bool membershipsRefs})
        > {
  $$MembershipPlansTableTableManager(
    _$AppDatabase db,
    $MembershipPlansTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembershipPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembershipPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembershipPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> durationMonths = const Value.absent(),
                Value<int> priceMinor = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
              }) => MembershipPlansCompanion(
                id: id,
                name: name,
                description: description,
                durationMonths: durationMonths,
                priceMinor: priceMinor,
                isActive: isActive,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                required int durationMonths,
                required int priceMinor,
                Value<bool> isActive = const Value.absent(),
              }) => MembershipPlansCompanion.insert(
                id: id,
                name: name,
                description: description,
                durationMonths: durationMonths,
                priceMinor: priceMinor,
                isActive: isActive,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MembershipPlansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({membershipsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (membershipsRefs) db.memberships],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (membershipsRefs)
                    await $_getPrefetchedData<
                      MembershipPlan,
                      $MembershipPlansTable,
                      Membership
                    >(
                      currentTable: table,
                      referencedTable: $$MembershipPlansTableReferences
                          ._membershipsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MembershipPlansTableReferences(
                            db,
                            table,
                            p0,
                          ).membershipsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.planId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MembershipPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MembershipPlansTable,
      MembershipPlan,
      $$MembershipPlansTableFilterComposer,
      $$MembershipPlansTableOrderingComposer,
      $$MembershipPlansTableAnnotationComposer,
      $$MembershipPlansTableCreateCompanionBuilder,
      $$MembershipPlansTableUpdateCompanionBuilder,
      (MembershipPlan, $$MembershipPlansTableReferences),
      MembershipPlan,
      PrefetchHooks Function({bool membershipsRefs})
    >;
typedef $$MembersTableCreateCompanionBuilder =
    MembersCompanion Function({
      Value<int> id,
      required int memberCode,
      required String fullName,
      required String phone,
      Value<String?> phoneRaw,
      Value<String?> email,
      Value<String?> gender,
      Value<DateTime?> dateOfBirth,
      Value<String?> address,
      Value<String?> emergencyContact,
      required DateTime joiningDate,
      Value<DateTime?> deactivatedAt,
      Value<DateTime> createdAt,
    });
typedef $$MembersTableUpdateCompanionBuilder =
    MembersCompanion Function({
      Value<int> id,
      Value<int> memberCode,
      Value<String> fullName,
      Value<String> phone,
      Value<String?> phoneRaw,
      Value<String?> email,
      Value<String?> gender,
      Value<DateTime?> dateOfBirth,
      Value<String?> address,
      Value<String?> emergencyContact,
      Value<DateTime> joiningDate,
      Value<DateTime?> deactivatedAt,
      Value<DateTime> createdAt,
    });

final class $$MembersTableReferences
    extends BaseReferences<_$AppDatabase, $MembersTable, Member> {
  $$MembersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MembershipsTable, List<Membership>>
  _membershipsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.memberships,
    aliasName: 'members__id__memberships__member_id',
  );

  $$MembershipsTableProcessedTableManager get membershipsRefs {
    final manager = $$MembershipsTableTableManager(
      $_db,
      $_db.memberships,
    ).filter((f) => f.memberId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_membershipsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PaymentsTable, List<Payment>> _paymentsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.payments,
    aliasName: 'members__id__payments__member_id',
  );

  $$PaymentsTableProcessedTableManager get paymentsRefs {
    final manager = $$PaymentsTableTableManager(
      $_db,
      $_db.payments,
    ).filter((f) => f.memberId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_paymentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$WhatsAppMessagesTable, List<WhatsAppMessage>>
  _whatsAppMessagesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.whatsAppMessages,
    aliasName: 'members__id__whats_app_messages__member_id',
  );

  $$WhatsAppMessagesTableProcessedTableManager get whatsAppMessagesRefs {
    final manager = $$WhatsAppMessagesTableTableManager(
      $_db,
      $_db.whatsAppMessages,
    ).filter((f) => f.memberId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _whatsAppMessagesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MemberNotesTable, List<MemberNote>>
  _memberNotesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.memberNotes,
    aliasName: 'members__id__member_notes__member_id',
  );

  $$MemberNotesTableProcessedTableManager get memberNotesRefs {
    final manager = $$MemberNotesTableTableManager(
      $_db,
      $_db.memberNotes,
    ).filter((f) => f.memberId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_memberNotesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MembersTableFilterComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memberCode => $composableBuilder(
    column: $table.memberCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fullName => $composableBuilder(
    column: $table.fullName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneRaw => $composableBuilder(
    column: $table.phoneRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emergencyContact => $composableBuilder(
    column: $table.emergencyContact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get joiningDate => $composableBuilder(
    column: $table.joiningDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deactivatedAt => $composableBuilder(
    column: $table.deactivatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> membershipsRefs(
    Expression<bool> Function($$MembershipsTableFilterComposer f) f,
  ) {
    final $$MembershipsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableFilterComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> paymentsRefs(
    Expression<bool> Function($$PaymentsTableFilterComposer f) f,
  ) {
    final $$PaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableFilterComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> whatsAppMessagesRefs(
    Expression<bool> Function($$WhatsAppMessagesTableFilterComposer f) f,
  ) {
    final $$WhatsAppMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.whatsAppMessages,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WhatsAppMessagesTableFilterComposer(
            $db: $db,
            $table: $db.whatsAppMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> memberNotesRefs(
    Expression<bool> Function($$MemberNotesTableFilterComposer f) f,
  ) {
    final $$MemberNotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memberNotes,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MemberNotesTableFilterComposer(
            $db: $db,
            $table: $db.memberNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembersTableOrderingComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memberCode => $composableBuilder(
    column: $table.memberCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fullName => $composableBuilder(
    column: $table.fullName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneRaw => $composableBuilder(
    column: $table.phoneRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emergencyContact => $composableBuilder(
    column: $table.emergencyContact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get joiningDate => $composableBuilder(
    column: $table.joiningDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deactivatedAt => $composableBuilder(
    column: $table.deactivatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get memberCode => $composableBuilder(
    column: $table.memberCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fullName =>
      $composableBuilder(column: $table.fullName, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get phoneRaw =>
      $composableBuilder(column: $table.phoneRaw, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => column,
  );

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get emergencyContact => $composableBuilder(
    column: $table.emergencyContact,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get joiningDate => $composableBuilder(
    column: $table.joiningDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deactivatedAt => $composableBuilder(
    column: $table.deactivatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> membershipsRefs<T extends Object>(
    Expression<T> Function($$MembershipsTableAnnotationComposer a) f,
  ) {
    final $$MembershipsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableAnnotationComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> paymentsRefs<T extends Object>(
    Expression<T> Function($$PaymentsTableAnnotationComposer a) f,
  ) {
    final $$PaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> whatsAppMessagesRefs<T extends Object>(
    Expression<T> Function($$WhatsAppMessagesTableAnnotationComposer a) f,
  ) {
    final $$WhatsAppMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.whatsAppMessages,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WhatsAppMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.whatsAppMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> memberNotesRefs<T extends Object>(
    Expression<T> Function($$MemberNotesTableAnnotationComposer a) f,
  ) {
    final $$MemberNotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memberNotes,
      getReferencedColumn: (t) => t.memberId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MemberNotesTableAnnotationComposer(
            $db: $db,
            $table: $db.memberNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MembersTable,
          Member,
          $$MembersTableFilterComposer,
          $$MembersTableOrderingComposer,
          $$MembersTableAnnotationComposer,
          $$MembersTableCreateCompanionBuilder,
          $$MembersTableUpdateCompanionBuilder,
          (Member, $$MembersTableReferences),
          Member,
          PrefetchHooks Function({
            bool membershipsRefs,
            bool paymentsRefs,
            bool whatsAppMessagesRefs,
            bool memberNotesRefs,
          })
        > {
  $$MembersTableTableManager(_$AppDatabase db, $MembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> memberCode = const Value.absent(),
                Value<String> fullName = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<String?> phoneRaw = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> gender = const Value.absent(),
                Value<DateTime?> dateOfBirth = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> emergencyContact = const Value.absent(),
                Value<DateTime> joiningDate = const Value.absent(),
                Value<DateTime?> deactivatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MembersCompanion(
                id: id,
                memberCode: memberCode,
                fullName: fullName,
                phone: phone,
                phoneRaw: phoneRaw,
                email: email,
                gender: gender,
                dateOfBirth: dateOfBirth,
                address: address,
                emergencyContact: emergencyContact,
                joiningDate: joiningDate,
                deactivatedAt: deactivatedAt,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int memberCode,
                required String fullName,
                required String phone,
                Value<String?> phoneRaw = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> gender = const Value.absent(),
                Value<DateTime?> dateOfBirth = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> emergencyContact = const Value.absent(),
                required DateTime joiningDate,
                Value<DateTime?> deactivatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MembersCompanion.insert(
                id: id,
                memberCode: memberCode,
                fullName: fullName,
                phone: phone,
                phoneRaw: phoneRaw,
                email: email,
                gender: gender,
                dateOfBirth: dateOfBirth,
                address: address,
                emergencyContact: emergencyContact,
                joiningDate: joiningDate,
                deactivatedAt: deactivatedAt,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MembersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                membershipsRefs = false,
                paymentsRefs = false,
                whatsAppMessagesRefs = false,
                memberNotesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (membershipsRefs) db.memberships,
                    if (paymentsRefs) db.payments,
                    if (whatsAppMessagesRefs) db.whatsAppMessages,
                    if (memberNotesRefs) db.memberNotes,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (membershipsRefs)
                        await $_getPrefetchedData<
                          Member,
                          $MembersTable,
                          Membership
                        >(
                          currentTable: table,
                          referencedTable: $$MembersTableReferences
                              ._membershipsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembersTableReferences(
                                db,
                                table,
                                p0,
                              ).membershipsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.memberId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (paymentsRefs)
                        await $_getPrefetchedData<
                          Member,
                          $MembersTable,
                          Payment
                        >(
                          currentTable: table,
                          referencedTable: $$MembersTableReferences
                              ._paymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembersTableReferences(
                                db,
                                table,
                                p0,
                              ).paymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.memberId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (whatsAppMessagesRefs)
                        await $_getPrefetchedData<
                          Member,
                          $MembersTable,
                          WhatsAppMessage
                        >(
                          currentTable: table,
                          referencedTable: $$MembersTableReferences
                              ._whatsAppMessagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembersTableReferences(
                                db,
                                table,
                                p0,
                              ).whatsAppMessagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.memberId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (memberNotesRefs)
                        await $_getPrefetchedData<
                          Member,
                          $MembersTable,
                          MemberNote
                        >(
                          currentTable: table,
                          referencedTable: $$MembersTableReferences
                              ._memberNotesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembersTableReferences(
                                db,
                                table,
                                p0,
                              ).memberNotesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.memberId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MembersTable,
      Member,
      $$MembersTableFilterComposer,
      $$MembersTableOrderingComposer,
      $$MembersTableAnnotationComposer,
      $$MembersTableCreateCompanionBuilder,
      $$MembersTableUpdateCompanionBuilder,
      (Member, $$MembersTableReferences),
      Member,
      PrefetchHooks Function({
        bool membershipsRefs,
        bool paymentsRefs,
        bool whatsAppMessagesRefs,
        bool memberNotesRefs,
      })
    >;
typedef $$MembershipsTableCreateCompanionBuilder =
    MembershipsCompanion Function({
      Value<int> id,
      required int memberId,
      required int planId,
      Value<int?> feeOverrideMinor,
      required DateTime startDate,
      Value<DateTime?> endDate,
    });
typedef $$MembershipsTableUpdateCompanionBuilder =
    MembershipsCompanion Function({
      Value<int> id,
      Value<int> memberId,
      Value<int> planId,
      Value<int?> feeOverrideMinor,
      Value<DateTime> startDate,
      Value<DateTime?> endDate,
    });

final class $$MembershipsTableReferences
    extends BaseReferences<_$AppDatabase, $MembershipsTable, Membership> {
  $$MembershipsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MembersTable _memberIdTable(_$AppDatabase db) =>
      db.members.createAlias('memberships__member_id__members__id');

  $$MembersTableProcessedTableManager get memberId {
    final $_column = $_itemColumn<int>('member_id')!;

    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_memberIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MembershipPlansTable _planIdTable(_$AppDatabase db) => db
      .membershipPlans
      .createAlias('memberships__plan_id__membership_plans__id');

  $$MembershipPlansTableProcessedTableManager get planId {
    final $_column = $_itemColumn<int>('plan_id')!;

    final manager = $$MembershipPlansTableTableManager(
      $_db,
      $_db.membershipPlans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MembershipPeriodsTable, List<MembershipPeriod>>
  _membershipPeriodsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.membershipPeriods,
        aliasName: 'memberships__id__membership_periods__membership_id',
      );

  $$MembershipPeriodsTableProcessedTableManager get membershipPeriodsRefs {
    final manager = $$MembershipPeriodsTableTableManager(
      $_db,
      $_db.membershipPeriods,
    ).filter((f) => f.membershipId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _membershipPeriodsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MembershipsTableFilterComposer
    extends Composer<_$AppDatabase, $MembershipsTable> {
  $$MembershipsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feeOverrideMinor => $composableBuilder(
    column: $table.feeOverrideMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  $$MembersTableFilterComposer get memberId {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembershipPlansTableFilterComposer get planId {
    final $$MembershipPlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.membershipPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipPlansTableFilterComposer(
            $db: $db,
            $table: $db.membershipPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> membershipPeriodsRefs(
    Expression<bool> Function($$MembershipPeriodsTableFilterComposer f) f,
  ) {
    final $$MembershipPeriodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.membershipPeriods,
      getReferencedColumn: (t) => t.membershipId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipPeriodsTableFilterComposer(
            $db: $db,
            $table: $db.membershipPeriods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembershipsTableOrderingComposer
    extends Composer<_$AppDatabase, $MembershipsTable> {
  $$MembershipsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feeOverrideMinor => $composableBuilder(
    column: $table.feeOverrideMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  $$MembersTableOrderingComposer get memberId {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembershipPlansTableOrderingComposer get planId {
    final $$MembershipPlansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.membershipPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipPlansTableOrderingComposer(
            $db: $db,
            $table: $db.membershipPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MembershipsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembershipsTable> {
  $$MembershipsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get feeOverrideMinor => $composableBuilder(
    column: $table.feeOverrideMinor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  $$MembersTableAnnotationComposer get memberId {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembershipPlansTableAnnotationComposer get planId {
    final $$MembershipPlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.membershipPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipPlansTableAnnotationComposer(
            $db: $db,
            $table: $db.membershipPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> membershipPeriodsRefs<T extends Object>(
    Expression<T> Function($$MembershipPeriodsTableAnnotationComposer a) f,
  ) {
    final $$MembershipPeriodsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.membershipPeriods,
          getReferencedColumn: (t) => t.membershipId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MembershipPeriodsTableAnnotationComposer(
                $db: $db,
                $table: $db.membershipPeriods,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MembershipsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MembershipsTable,
          Membership,
          $$MembershipsTableFilterComposer,
          $$MembershipsTableOrderingComposer,
          $$MembershipsTableAnnotationComposer,
          $$MembershipsTableCreateCompanionBuilder,
          $$MembershipsTableUpdateCompanionBuilder,
          (Membership, $$MembershipsTableReferences),
          Membership,
          PrefetchHooks Function({
            bool memberId,
            bool planId,
            bool membershipPeriodsRefs,
          })
        > {
  $$MembershipsTableTableManager(_$AppDatabase db, $MembershipsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembershipsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembershipsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembershipsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> memberId = const Value.absent(),
                Value<int> planId = const Value.absent(),
                Value<int?> feeOverrideMinor = const Value.absent(),
                Value<DateTime> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
              }) => MembershipsCompanion(
                id: id,
                memberId: memberId,
                planId: planId,
                feeOverrideMinor: feeOverrideMinor,
                startDate: startDate,
                endDate: endDate,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int memberId,
                required int planId,
                Value<int?> feeOverrideMinor = const Value.absent(),
                required DateTime startDate,
                Value<DateTime?> endDate = const Value.absent(),
              }) => MembershipsCompanion.insert(
                id: id,
                memberId: memberId,
                planId: planId,
                feeOverrideMinor: feeOverrideMinor,
                startDate: startDate,
                endDate: endDate,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MembershipsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                memberId = false,
                planId = false,
                membershipPeriodsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (membershipPeriodsRefs) db.membershipPeriods,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (memberId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.memberId,
                                    referencedTable:
                                        $$MembershipsTableReferences
                                            ._memberIdTable(db),
                                    referencedColumn:
                                        $$MembershipsTableReferences
                                            ._memberIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (planId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.planId,
                                    referencedTable:
                                        $$MembershipsTableReferences
                                            ._planIdTable(db),
                                    referencedColumn:
                                        $$MembershipsTableReferences
                                            ._planIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (membershipPeriodsRefs)
                        await $_getPrefetchedData<
                          Membership,
                          $MembershipsTable,
                          MembershipPeriod
                        >(
                          currentTable: table,
                          referencedTable: $$MembershipsTableReferences
                              ._membershipPeriodsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembershipsTableReferences(
                                db,
                                table,
                                p0,
                              ).membershipPeriodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.membershipId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MembershipsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MembershipsTable,
      Membership,
      $$MembershipsTableFilterComposer,
      $$MembershipsTableOrderingComposer,
      $$MembershipsTableAnnotationComposer,
      $$MembershipsTableCreateCompanionBuilder,
      $$MembershipsTableUpdateCompanionBuilder,
      (Membership, $$MembershipsTableReferences),
      Membership,
      PrefetchHooks Function({
        bool memberId,
        bool planId,
        bool membershipPeriodsRefs,
      })
    >;
typedef $$MembershipPeriodsTableCreateCompanionBuilder =
    MembershipPeriodsCompanion Function({
      Value<int> id,
      required int membershipId,
      required DateTime periodStart,
      required DateTime periodEnd,
      required int expectedAmountMinor,
    });
typedef $$MembershipPeriodsTableUpdateCompanionBuilder =
    MembershipPeriodsCompanion Function({
      Value<int> id,
      Value<int> membershipId,
      Value<DateTime> periodStart,
      Value<DateTime> periodEnd,
      Value<int> expectedAmountMinor,
    });

final class $$MembershipPeriodsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $MembershipPeriodsTable,
          MembershipPeriod
        > {
  $$MembershipPeriodsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MembershipsTable _membershipIdTable(_$AppDatabase db) => db
      .memberships
      .createAlias('membership_periods__membership_id__memberships__id');

  $$MembershipsTableProcessedTableManager get membershipId {
    final $_column = $_itemColumn<int>('membership_id')!;

    final manager = $$MembershipsTableTableManager(
      $_db,
      $_db.memberships,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_membershipIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PaymentsTable, List<Payment>> _paymentsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.payments,
    aliasName: 'membership_periods__id__payments__membership_period_id',
  );

  $$PaymentsTableProcessedTableManager get paymentsRefs {
    final manager = $$PaymentsTableTableManager($_db, $_db.payments).filter(
      (f) => f.membershipPeriodId.id.sqlEquals($_itemColumn<int>('id')!),
    );

    final cache = $_typedResult.readTableOrNull(_paymentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MembershipPeriodsTableFilterComposer
    extends Composer<_$AppDatabase, $MembershipPeriodsTable> {
  $$MembershipPeriodsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get periodEnd => $composableBuilder(
    column: $table.periodEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedAmountMinor => $composableBuilder(
    column: $table.expectedAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  $$MembershipsTableFilterComposer get membershipId {
    final $$MembershipsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.membershipId,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableFilterComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> paymentsRefs(
    Expression<bool> Function($$PaymentsTableFilterComposer f) f,
  ) {
    final $$PaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.membershipPeriodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableFilterComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembershipPeriodsTableOrderingComposer
    extends Composer<_$AppDatabase, $MembershipPeriodsTable> {
  $$MembershipPeriodsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get periodEnd => $composableBuilder(
    column: $table.periodEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedAmountMinor => $composableBuilder(
    column: $table.expectedAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  $$MembershipsTableOrderingComposer get membershipId {
    final $$MembershipsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.membershipId,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableOrderingComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MembershipPeriodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembershipPeriodsTable> {
  $$MembershipPeriodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get periodEnd =>
      $composableBuilder(column: $table.periodEnd, builder: (column) => column);

  GeneratedColumn<int> get expectedAmountMinor => $composableBuilder(
    column: $table.expectedAmountMinor,
    builder: (column) => column,
  );

  $$MembershipsTableAnnotationComposer get membershipId {
    final $$MembershipsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.membershipId,
      referencedTable: $db.memberships,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipsTableAnnotationComposer(
            $db: $db,
            $table: $db.memberships,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> paymentsRefs<T extends Object>(
    Expression<T> Function($$PaymentsTableAnnotationComposer a) f,
  ) {
    final $$PaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.membershipPeriodId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MembershipPeriodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MembershipPeriodsTable,
          MembershipPeriod,
          $$MembershipPeriodsTableFilterComposer,
          $$MembershipPeriodsTableOrderingComposer,
          $$MembershipPeriodsTableAnnotationComposer,
          $$MembershipPeriodsTableCreateCompanionBuilder,
          $$MembershipPeriodsTableUpdateCompanionBuilder,
          (MembershipPeriod, $$MembershipPeriodsTableReferences),
          MembershipPeriod,
          PrefetchHooks Function({bool membershipId, bool paymentsRefs})
        > {
  $$MembershipPeriodsTableTableManager(
    _$AppDatabase db,
    $MembershipPeriodsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembershipPeriodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembershipPeriodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembershipPeriodsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> membershipId = const Value.absent(),
                Value<DateTime> periodStart = const Value.absent(),
                Value<DateTime> periodEnd = const Value.absent(),
                Value<int> expectedAmountMinor = const Value.absent(),
              }) => MembershipPeriodsCompanion(
                id: id,
                membershipId: membershipId,
                periodStart: periodStart,
                periodEnd: periodEnd,
                expectedAmountMinor: expectedAmountMinor,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int membershipId,
                required DateTime periodStart,
                required DateTime periodEnd,
                required int expectedAmountMinor,
              }) => MembershipPeriodsCompanion.insert(
                id: id,
                membershipId: membershipId,
                periodStart: periodStart,
                periodEnd: periodEnd,
                expectedAmountMinor: expectedAmountMinor,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MembershipPeriodsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({membershipId = false, paymentsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (paymentsRefs) db.payments],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (membershipId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.membershipId,
                                    referencedTable:
                                        $$MembershipPeriodsTableReferences
                                            ._membershipIdTable(db),
                                    referencedColumn:
                                        $$MembershipPeriodsTableReferences
                                            ._membershipIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (paymentsRefs)
                        await $_getPrefetchedData<
                          MembershipPeriod,
                          $MembershipPeriodsTable,
                          Payment
                        >(
                          currentTable: table,
                          referencedTable: $$MembershipPeriodsTableReferences
                              ._paymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MembershipPeriodsTableReferences(
                                db,
                                table,
                                p0,
                              ).paymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.membershipPeriodId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MembershipPeriodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MembershipPeriodsTable,
      MembershipPeriod,
      $$MembershipPeriodsTableFilterComposer,
      $$MembershipPeriodsTableOrderingComposer,
      $$MembershipPeriodsTableAnnotationComposer,
      $$MembershipPeriodsTableCreateCompanionBuilder,
      $$MembershipPeriodsTableUpdateCompanionBuilder,
      (MembershipPeriod, $$MembershipPeriodsTableReferences),
      MembershipPeriod,
      PrefetchHooks Function({bool membershipId, bool paymentsRefs})
    >;
typedef $$PaymentsTableCreateCompanionBuilder =
    PaymentsCompanion Function({
      Value<int> id,
      required int memberId,
      Value<int?> membershipPeriodId,
      required int amountMinor,
      required PaymentMethod method,
      Value<String?> referenceNumber,
      required DateTime paymentDate,
      Value<String?> notes,
      Value<PaymentSource> source,
      required int recordedById,
      Value<DateTime?> updatedAt,
      Value<int?> updatedById,
      required String idempotencyKey,
      Value<DateTime> createdAt,
    });
typedef $$PaymentsTableUpdateCompanionBuilder =
    PaymentsCompanion Function({
      Value<int> id,
      Value<int> memberId,
      Value<int?> membershipPeriodId,
      Value<int> amountMinor,
      Value<PaymentMethod> method,
      Value<String?> referenceNumber,
      Value<DateTime> paymentDate,
      Value<String?> notes,
      Value<PaymentSource> source,
      Value<int> recordedById,
      Value<DateTime?> updatedAt,
      Value<int?> updatedById,
      Value<String> idempotencyKey,
      Value<DateTime> createdAt,
    });

final class $$PaymentsTableReferences
    extends BaseReferences<_$AppDatabase, $PaymentsTable, Payment> {
  $$PaymentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MembersTable _memberIdTable(_$AppDatabase db) =>
      db.members.createAlias('payments__member_id__members__id');

  $$MembersTableProcessedTableManager get memberId {
    final $_column = $_itemColumn<int>('member_id')!;

    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_memberIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MembershipPeriodsTable _membershipPeriodIdTable(_$AppDatabase db) =>
      db.membershipPeriods.createAlias(
        'payments__membership_period_id__membership_periods__id',
      );

  $$MembershipPeriodsTableProcessedTableManager? get membershipPeriodId {
    final $_column = $_itemColumn<int>('membership_period_id');
    if ($_column == null) return null;
    final manager = $$MembershipPeriodsTableTableManager(
      $_db,
      $_db.membershipPeriods,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_membershipPeriodIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UsersTable _recordedByIdTable(_$AppDatabase db) =>
      db.users.createAlias('payments__recorded_by_id__users__id');

  $$UsersTableProcessedTableManager get recordedById {
    final $_column = $_itemColumn<int>('recorded_by_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recordedByIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UsersTable _updatedByIdTable(_$AppDatabase db) =>
      db.users.createAlias('payments__updated_by_id__users__id');

  $$UsersTableProcessedTableManager? get updatedById {
    final $_column = $_itemColumn<int>('updated_by_id');
    if ($_column == null) return null;
    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_updatedByIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ReceiptsTable, List<Receipt>> _receiptsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.receipts,
    aliasName: 'payments__id__receipts__payment_id',
  );

  $$ReceiptsTableProcessedTableManager get receiptsRefs {
    final manager = $$ReceiptsTableTableManager(
      $_db,
      $_db.receipts,
    ).filter((f) => f.paymentId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_receiptsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PaymentMethod, PaymentMethod, String>
  get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PaymentSource, PaymentSource, String>
  get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MembersTableFilterComposer get memberId {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembershipPeriodsTableFilterComposer get membershipPeriodId {
    final $$MembershipPeriodsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.membershipPeriodId,
      referencedTable: $db.membershipPeriods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipPeriodsTableFilterComposer(
            $db: $db,
            $table: $db.membershipPeriods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableFilterComposer get recordedById {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recordedById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableFilterComposer get updatedById {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.updatedById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> receiptsRefs(
    Expression<bool> Function($$ReceiptsTableFilterComposer f) f,
  ) {
    final $$ReceiptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.receipts,
      getReferencedColumn: (t) => t.paymentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceiptsTableFilterComposer(
            $db: $db,
            $table: $db.receipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MembersTableOrderingComposer get memberId {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembershipPeriodsTableOrderingComposer get membershipPeriodId {
    final $$MembershipPeriodsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.membershipPeriodId,
      referencedTable: $db.membershipPeriods,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembershipPeriodsTableOrderingComposer(
            $db: $db,
            $table: $db.membershipPeriods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableOrderingComposer get recordedById {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recordedById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableOrderingComposer get updatedById {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.updatedById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<PaymentMethod, String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PaymentSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$MembersTableAnnotationComposer get memberId {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembershipPeriodsTableAnnotationComposer get membershipPeriodId {
    final $$MembershipPeriodsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.membershipPeriodId,
          referencedTable: $db.membershipPeriods,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MembershipPeriodsTableAnnotationComposer(
                $db: $db,
                $table: $db.membershipPeriods,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$UsersTableAnnotationComposer get recordedById {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recordedById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableAnnotationComposer get updatedById {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.updatedById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> receiptsRefs<T extends Object>(
    Expression<T> Function($$ReceiptsTableAnnotationComposer a) f,
  ) {
    final $$ReceiptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.receipts,
      getReferencedColumn: (t) => t.paymentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceiptsTableAnnotationComposer(
            $db: $db,
            $table: $db.receipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PaymentsTable,
          Payment,
          $$PaymentsTableFilterComposer,
          $$PaymentsTableOrderingComposer,
          $$PaymentsTableAnnotationComposer,
          $$PaymentsTableCreateCompanionBuilder,
          $$PaymentsTableUpdateCompanionBuilder,
          (Payment, $$PaymentsTableReferences),
          Payment,
          PrefetchHooks Function({
            bool memberId,
            bool membershipPeriodId,
            bool recordedById,
            bool updatedById,
            bool receiptsRefs,
          })
        > {
  $$PaymentsTableTableManager(_$AppDatabase db, $PaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> memberId = const Value.absent(),
                Value<int?> membershipPeriodId = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<PaymentMethod> method = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<DateTime> paymentDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<PaymentSource> source = const Value.absent(),
                Value<int> recordedById = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int?> updatedById = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PaymentsCompanion(
                id: id,
                memberId: memberId,
                membershipPeriodId: membershipPeriodId,
                amountMinor: amountMinor,
                method: method,
                referenceNumber: referenceNumber,
                paymentDate: paymentDate,
                notes: notes,
                source: source,
                recordedById: recordedById,
                updatedAt: updatedAt,
                updatedById: updatedById,
                idempotencyKey: idempotencyKey,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int memberId,
                Value<int?> membershipPeriodId = const Value.absent(),
                required int amountMinor,
                required PaymentMethod method,
                Value<String?> referenceNumber = const Value.absent(),
                required DateTime paymentDate,
                Value<String?> notes = const Value.absent(),
                Value<PaymentSource> source = const Value.absent(),
                required int recordedById,
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int?> updatedById = const Value.absent(),
                required String idempotencyKey,
                Value<DateTime> createdAt = const Value.absent(),
              }) => PaymentsCompanion.insert(
                id: id,
                memberId: memberId,
                membershipPeriodId: membershipPeriodId,
                amountMinor: amountMinor,
                method: method,
                referenceNumber: referenceNumber,
                paymentDate: paymentDate,
                notes: notes,
                source: source,
                recordedById: recordedById,
                updatedAt: updatedAt,
                updatedById: updatedById,
                idempotencyKey: idempotencyKey,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PaymentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                memberId = false,
                membershipPeriodId = false,
                recordedById = false,
                updatedById = false,
                receiptsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (receiptsRefs) db.receipts],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (memberId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.memberId,
                                    referencedTable: $$PaymentsTableReferences
                                        ._memberIdTable(db),
                                    referencedColumn: $$PaymentsTableReferences
                                        ._memberIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (membershipPeriodId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.membershipPeriodId,
                                    referencedTable: $$PaymentsTableReferences
                                        ._membershipPeriodIdTable(db),
                                    referencedColumn: $$PaymentsTableReferences
                                        ._membershipPeriodIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (recordedById) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.recordedById,
                                    referencedTable: $$PaymentsTableReferences
                                        ._recordedByIdTable(db),
                                    referencedColumn: $$PaymentsTableReferences
                                        ._recordedByIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (updatedById) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.updatedById,
                                    referencedTable: $$PaymentsTableReferences
                                        ._updatedByIdTable(db),
                                    referencedColumn: $$PaymentsTableReferences
                                        ._updatedByIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (receiptsRefs)
                        await $_getPrefetchedData<
                          Payment,
                          $PaymentsTable,
                          Receipt
                        >(
                          currentTable: table,
                          referencedTable: $$PaymentsTableReferences
                              ._receiptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PaymentsTableReferences(
                                db,
                                table,
                                p0,
                              ).receiptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PaymentsTable,
      Payment,
      $$PaymentsTableFilterComposer,
      $$PaymentsTableOrderingComposer,
      $$PaymentsTableAnnotationComposer,
      $$PaymentsTableCreateCompanionBuilder,
      $$PaymentsTableUpdateCompanionBuilder,
      (Payment, $$PaymentsTableReferences),
      Payment,
      PrefetchHooks Function({
        bool memberId,
        bool membershipPeriodId,
        bool recordedById,
        bool updatedById,
        bool receiptsRefs,
      })
    >;
typedef $$ReceiptsTableCreateCompanionBuilder =
    ReceiptsCompanion Function({
      Value<int> id,
      required String receiptNumber,
      required int paymentId,
      required String pngPath,
      Value<String?> pdfPath,
      Value<DateTime> createdAt,
    });
typedef $$ReceiptsTableUpdateCompanionBuilder =
    ReceiptsCompanion Function({
      Value<int> id,
      Value<String> receiptNumber,
      Value<int> paymentId,
      Value<String> pngPath,
      Value<String?> pdfPath,
      Value<DateTime> createdAt,
    });

final class $$ReceiptsTableReferences
    extends BaseReferences<_$AppDatabase, $ReceiptsTable, Receipt> {
  $$ReceiptsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PaymentsTable _paymentIdTable(_$AppDatabase db) =>
      db.payments.createAlias('receipts__payment_id__payments__id');

  $$PaymentsTableProcessedTableManager get paymentId {
    final $_column = $_itemColumn<int>('payment_id')!;

    final manager = $$PaymentsTableTableManager(
      $_db,
      $_db.payments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$WhatsAppMessagesTable, List<WhatsAppMessage>>
  _whatsAppMessagesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.whatsAppMessages,
    aliasName: 'receipts__id__whats_app_messages__receipt_id',
  );

  $$WhatsAppMessagesTableProcessedTableManager get whatsAppMessagesRefs {
    final manager = $$WhatsAppMessagesTableTableManager(
      $_db,
      $_db.whatsAppMessages,
    ).filter((f) => f.receiptId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _whatsAppMessagesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ReceiptsTableFilterComposer
    extends Composer<_$AppDatabase, $ReceiptsTable> {
  $$ReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pngPath => $composableBuilder(
    column: $table.pngPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pdfPath => $composableBuilder(
    column: $table.pdfPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PaymentsTableFilterComposer get paymentId {
    final $$PaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentId,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableFilterComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> whatsAppMessagesRefs(
    Expression<bool> Function($$WhatsAppMessagesTableFilterComposer f) f,
  ) {
    final $$WhatsAppMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.whatsAppMessages,
      getReferencedColumn: (t) => t.receiptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WhatsAppMessagesTableFilterComposer(
            $db: $db,
            $table: $db.whatsAppMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ReceiptsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReceiptsTable> {
  $$ReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pngPath => $composableBuilder(
    column: $table.pngPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pdfPath => $composableBuilder(
    column: $table.pdfPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PaymentsTableOrderingComposer get paymentId {
    final $$PaymentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentId,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableOrderingComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReceiptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReceiptsTable> {
  $$ReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pngPath =>
      $composableBuilder(column: $table.pngPath, builder: (column) => column);

  GeneratedColumn<String> get pdfPath =>
      $composableBuilder(column: $table.pdfPath, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PaymentsTableAnnotationComposer get paymentId {
    final $$PaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentId,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> whatsAppMessagesRefs<T extends Object>(
    Expression<T> Function($$WhatsAppMessagesTableAnnotationComposer a) f,
  ) {
    final $$WhatsAppMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.whatsAppMessages,
      getReferencedColumn: (t) => t.receiptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WhatsAppMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.whatsAppMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ReceiptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReceiptsTable,
          Receipt,
          $$ReceiptsTableFilterComposer,
          $$ReceiptsTableOrderingComposer,
          $$ReceiptsTableAnnotationComposer,
          $$ReceiptsTableCreateCompanionBuilder,
          $$ReceiptsTableUpdateCompanionBuilder,
          (Receipt, $$ReceiptsTableReferences),
          Receipt,
          PrefetchHooks Function({bool paymentId, bool whatsAppMessagesRefs})
        > {
  $$ReceiptsTableTableManager(_$AppDatabase db, $ReceiptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> receiptNumber = const Value.absent(),
                Value<int> paymentId = const Value.absent(),
                Value<String> pngPath = const Value.absent(),
                Value<String?> pdfPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ReceiptsCompanion(
                id: id,
                receiptNumber: receiptNumber,
                paymentId: paymentId,
                pngPath: pngPath,
                pdfPath: pdfPath,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String receiptNumber,
                required int paymentId,
                required String pngPath,
                Value<String?> pdfPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ReceiptsCompanion.insert(
                id: id,
                receiptNumber: receiptNumber,
                paymentId: paymentId,
                pngPath: pngPath,
                pdfPath: pdfPath,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReceiptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({paymentId = false, whatsAppMessagesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (whatsAppMessagesRefs) db.whatsAppMessages,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (paymentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.paymentId,
                                    referencedTable: $$ReceiptsTableReferences
                                        ._paymentIdTable(db),
                                    referencedColumn: $$ReceiptsTableReferences
                                        ._paymentIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (whatsAppMessagesRefs)
                        await $_getPrefetchedData<
                          Receipt,
                          $ReceiptsTable,
                          WhatsAppMessage
                        >(
                          currentTable: table,
                          referencedTable: $$ReceiptsTableReferences
                              ._whatsAppMessagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReceiptsTableReferences(
                                db,
                                table,
                                p0,
                              ).whatsAppMessagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.receiptId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReceiptsTable,
      Receipt,
      $$ReceiptsTableFilterComposer,
      $$ReceiptsTableOrderingComposer,
      $$ReceiptsTableAnnotationComposer,
      $$ReceiptsTableCreateCompanionBuilder,
      $$ReceiptsTableUpdateCompanionBuilder,
      (Receipt, $$ReceiptsTableReferences),
      Receipt,
      PrefetchHooks Function({bool paymentId, bool whatsAppMessagesRefs})
    >;
typedef $$ReceiptCountersTableCreateCompanionBuilder =
    ReceiptCountersCompanion Function({Value<int> year, Value<int> lastNumber});
typedef $$ReceiptCountersTableUpdateCompanionBuilder =
    ReceiptCountersCompanion Function({Value<int> year, Value<int> lastNumber});

class $$ReceiptCountersTableFilterComposer
    extends Composer<_$AppDatabase, $ReceiptCountersTable> {
  $$ReceiptCountersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastNumber => $composableBuilder(
    column: $table.lastNumber,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReceiptCountersTableOrderingComposer
    extends Composer<_$AppDatabase, $ReceiptCountersTable> {
  $$ReceiptCountersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastNumber => $composableBuilder(
    column: $table.lastNumber,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReceiptCountersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReceiptCountersTable> {
  $$ReceiptCountersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get lastNumber => $composableBuilder(
    column: $table.lastNumber,
    builder: (column) => column,
  );
}

class $$ReceiptCountersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReceiptCountersTable,
          ReceiptCounter,
          $$ReceiptCountersTableFilterComposer,
          $$ReceiptCountersTableOrderingComposer,
          $$ReceiptCountersTableAnnotationComposer,
          $$ReceiptCountersTableCreateCompanionBuilder,
          $$ReceiptCountersTableUpdateCompanionBuilder,
          (
            ReceiptCounter,
            BaseReferences<
              _$AppDatabase,
              $ReceiptCountersTable,
              ReceiptCounter
            >,
          ),
          ReceiptCounter,
          PrefetchHooks Function()
        > {
  $$ReceiptCountersTableTableManager(
    _$AppDatabase db,
    $ReceiptCountersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReceiptCountersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReceiptCountersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReceiptCountersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> year = const Value.absent(),
                Value<int> lastNumber = const Value.absent(),
              }) =>
                  ReceiptCountersCompanion(year: year, lastNumber: lastNumber),
          createCompanionCallback:
              ({
                Value<int> year = const Value.absent(),
                Value<int> lastNumber = const Value.absent(),
              }) => ReceiptCountersCompanion.insert(
                year: year,
                lastNumber: lastNumber,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReceiptCountersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReceiptCountersTable,
      ReceiptCounter,
      $$ReceiptCountersTableFilterComposer,
      $$ReceiptCountersTableOrderingComposer,
      $$ReceiptCountersTableAnnotationComposer,
      $$ReceiptCountersTableCreateCompanionBuilder,
      $$ReceiptCountersTableUpdateCompanionBuilder,
      (
        ReceiptCounter,
        BaseReferences<_$AppDatabase, $ReceiptCountersTable, ReceiptCounter>,
      ),
      ReceiptCounter,
      PrefetchHooks Function()
    >;
typedef $$WhatsAppMessagesTableCreateCompanionBuilder =
    WhatsAppMessagesCompanion Function({
      Value<int> id,
      required int receiptId,
      required int memberId,
      required String phone,
      required WhatsAppProviderKind provider,
      Value<String?> externalMessageId,
      Value<WhatsAppStatus> status,
      Value<String?> errorMessage,
      Value<int> attemptNumber,
      Value<DateTime?> sentAt,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<DateTime?> failedAt,
      Value<DateTime> createdAt,
    });
typedef $$WhatsAppMessagesTableUpdateCompanionBuilder =
    WhatsAppMessagesCompanion Function({
      Value<int> id,
      Value<int> receiptId,
      Value<int> memberId,
      Value<String> phone,
      Value<WhatsAppProviderKind> provider,
      Value<String?> externalMessageId,
      Value<WhatsAppStatus> status,
      Value<String?> errorMessage,
      Value<int> attemptNumber,
      Value<DateTime?> sentAt,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<DateTime?> failedAt,
      Value<DateTime> createdAt,
    });

final class $$WhatsAppMessagesTableReferences
    extends
        BaseReferences<_$AppDatabase, $WhatsAppMessagesTable, WhatsAppMessage> {
  $$WhatsAppMessagesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ReceiptsTable _receiptIdTable(_$AppDatabase db) =>
      db.receipts.createAlias('whats_app_messages__receipt_id__receipts__id');

  $$ReceiptsTableProcessedTableManager get receiptId {
    final $_column = $_itemColumn<int>('receipt_id')!;

    final manager = $$ReceiptsTableTableManager(
      $_db,
      $_db.receipts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_receiptIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MembersTable _memberIdTable(_$AppDatabase db) =>
      db.members.createAlias('whats_app_messages__member_id__members__id');

  $$MembersTableProcessedTableManager get memberId {
    final $_column = $_itemColumn<int>('member_id')!;

    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_memberIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WhatsAppMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $WhatsAppMessagesTable> {
  $$WhatsAppMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    WhatsAppProviderKind,
    WhatsAppProviderKind,
    String
  >
  get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get externalMessageId => $composableBuilder(
    column: $table.externalMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<WhatsAppStatus, WhatsAppStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptNumber => $composableBuilder(
    column: $table.attemptNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get failedAt => $composableBuilder(
    column: $table.failedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ReceiptsTableFilterComposer get receiptId {
    final $$ReceiptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.receiptId,
      referencedTable: $db.receipts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceiptsTableFilterComposer(
            $db: $db,
            $table: $db.receipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableFilterComposer get memberId {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WhatsAppMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $WhatsAppMessagesTable> {
  $$WhatsAppMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalMessageId => $composableBuilder(
    column: $table.externalMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptNumber => $composableBuilder(
    column: $table.attemptNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get failedAt => $composableBuilder(
    column: $table.failedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ReceiptsTableOrderingComposer get receiptId {
    final $$ReceiptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.receiptId,
      referencedTable: $db.receipts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceiptsTableOrderingComposer(
            $db: $db,
            $table: $db.receipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableOrderingComposer get memberId {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WhatsAppMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WhatsAppMessagesTable> {
  $$WhatsAppMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumnWithTypeConverter<WhatsAppProviderKind, String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get externalMessageId => $composableBuilder(
    column: $table.externalMessageId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<WhatsAppStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptNumber => $composableBuilder(
    column: $table.attemptNumber,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumn<DateTime> get failedAt =>
      $composableBuilder(column: $table.failedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ReceiptsTableAnnotationComposer get receiptId {
    final $$ReceiptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.receiptId,
      referencedTable: $db.receipts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceiptsTableAnnotationComposer(
            $db: $db,
            $table: $db.receipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MembersTableAnnotationComposer get memberId {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WhatsAppMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WhatsAppMessagesTable,
          WhatsAppMessage,
          $$WhatsAppMessagesTableFilterComposer,
          $$WhatsAppMessagesTableOrderingComposer,
          $$WhatsAppMessagesTableAnnotationComposer,
          $$WhatsAppMessagesTableCreateCompanionBuilder,
          $$WhatsAppMessagesTableUpdateCompanionBuilder,
          (WhatsAppMessage, $$WhatsAppMessagesTableReferences),
          WhatsAppMessage,
          PrefetchHooks Function({bool receiptId, bool memberId})
        > {
  $$WhatsAppMessagesTableTableManager(
    _$AppDatabase db,
    $WhatsAppMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WhatsAppMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WhatsAppMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WhatsAppMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> receiptId = const Value.absent(),
                Value<int> memberId = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<WhatsAppProviderKind> provider = const Value.absent(),
                Value<String?> externalMessageId = const Value.absent(),
                Value<WhatsAppStatus> status = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> attemptNumber = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<DateTime?> failedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => WhatsAppMessagesCompanion(
                id: id,
                receiptId: receiptId,
                memberId: memberId,
                phone: phone,
                provider: provider,
                externalMessageId: externalMessageId,
                status: status,
                errorMessage: errorMessage,
                attemptNumber: attemptNumber,
                sentAt: sentAt,
                deliveredAt: deliveredAt,
                readAt: readAt,
                failedAt: failedAt,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int receiptId,
                required int memberId,
                required String phone,
                required WhatsAppProviderKind provider,
                Value<String?> externalMessageId = const Value.absent(),
                Value<WhatsAppStatus> status = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> attemptNumber = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<DateTime?> failedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => WhatsAppMessagesCompanion.insert(
                id: id,
                receiptId: receiptId,
                memberId: memberId,
                phone: phone,
                provider: provider,
                externalMessageId: externalMessageId,
                status: status,
                errorMessage: errorMessage,
                attemptNumber: attemptNumber,
                sentAt: sentAt,
                deliveredAt: deliveredAt,
                readAt: readAt,
                failedAt: failedAt,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$WhatsAppMessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({receiptId = false, memberId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (receiptId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.receiptId,
                                referencedTable:
                                    $$WhatsAppMessagesTableReferences
                                        ._receiptIdTable(db),
                                referencedColumn:
                                    $$WhatsAppMessagesTableReferences
                                        ._receiptIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (memberId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.memberId,
                                referencedTable:
                                    $$WhatsAppMessagesTableReferences
                                        ._memberIdTable(db),
                                referencedColumn:
                                    $$WhatsAppMessagesTableReferences
                                        ._memberIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WhatsAppMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WhatsAppMessagesTable,
      WhatsAppMessage,
      $$WhatsAppMessagesTableFilterComposer,
      $$WhatsAppMessagesTableOrderingComposer,
      $$WhatsAppMessagesTableAnnotationComposer,
      $$WhatsAppMessagesTableCreateCompanionBuilder,
      $$WhatsAppMessagesTableUpdateCompanionBuilder,
      (WhatsAppMessage, $$WhatsAppMessagesTableReferences),
      WhatsAppMessage,
      PrefetchHooks Function({bool receiptId, bool memberId})
    >;
typedef $$MemberNotesTableCreateCompanionBuilder =
    MemberNotesCompanion Function({
      Value<int> id,
      required int memberId,
      required String body,
      required int createdById,
      Value<DateTime> createdAt,
    });
typedef $$MemberNotesTableUpdateCompanionBuilder =
    MemberNotesCompanion Function({
      Value<int> id,
      Value<int> memberId,
      Value<String> body,
      Value<int> createdById,
      Value<DateTime> createdAt,
    });

final class $$MemberNotesTableReferences
    extends BaseReferences<_$AppDatabase, $MemberNotesTable, MemberNote> {
  $$MemberNotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MembersTable _memberIdTable(_$AppDatabase db) =>
      db.members.createAlias('member_notes__member_id__members__id');

  $$MembersTableProcessedTableManager get memberId {
    final $_column = $_itemColumn<int>('member_id')!;

    final manager = $$MembersTableTableManager(
      $_db,
      $_db.members,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_memberIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UsersTable _createdByIdTable(_$AppDatabase db) =>
      db.users.createAlias('member_notes__created_by_id__users__id');

  $$UsersTableProcessedTableManager get createdById {
    final $_column = $_itemColumn<int>('created_by_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_createdByIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MemberNotesTableFilterComposer
    extends Composer<_$AppDatabase, $MemberNotesTable> {
  $$MemberNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MembersTableFilterComposer get memberId {
    final $$MembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableFilterComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableFilterComposer get createdById {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.createdById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MemberNotesTableOrderingComposer
    extends Composer<_$AppDatabase, $MemberNotesTable> {
  $$MemberNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MembersTableOrderingComposer get memberId {
    final $$MembersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableOrderingComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableOrderingComposer get createdById {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.createdById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MemberNotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemberNotesTable> {
  $$MemberNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$MembersTableAnnotationComposer get memberId {
    final $$MembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.memberId,
      referencedTable: $db.members,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MembersTableAnnotationComposer(
            $db: $db,
            $table: $db.members,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableAnnotationComposer get createdById {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.createdById,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MemberNotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemberNotesTable,
          MemberNote,
          $$MemberNotesTableFilterComposer,
          $$MemberNotesTableOrderingComposer,
          $$MemberNotesTableAnnotationComposer,
          $$MemberNotesTableCreateCompanionBuilder,
          $$MemberNotesTableUpdateCompanionBuilder,
          (MemberNote, $$MemberNotesTableReferences),
          MemberNote,
          PrefetchHooks Function({bool memberId, bool createdById})
        > {
  $$MemberNotesTableTableManager(_$AppDatabase db, $MemberNotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemberNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemberNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemberNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> memberId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> createdById = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MemberNotesCompanion(
                id: id,
                memberId: memberId,
                body: body,
                createdById: createdById,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int memberId,
                required String body,
                required int createdById,
                Value<DateTime> createdAt = const Value.absent(),
              }) => MemberNotesCompanion.insert(
                id: id,
                memberId: memberId,
                body: body,
                createdById: createdById,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MemberNotesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({memberId = false, createdById = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (memberId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.memberId,
                                referencedTable: $$MemberNotesTableReferences
                                    ._memberIdTable(db),
                                referencedColumn: $$MemberNotesTableReferences
                                    ._memberIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (createdById) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.createdById,
                                referencedTable: $$MemberNotesTableReferences
                                    ._createdByIdTable(db),
                                referencedColumn: $$MemberNotesTableReferences
                                    ._createdByIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MemberNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemberNotesTable,
      MemberNote,
      $$MemberNotesTableFilterComposer,
      $$MemberNotesTableOrderingComposer,
      $$MemberNotesTableAnnotationComposer,
      $$MemberNotesTableCreateCompanionBuilder,
      $$MemberNotesTableUpdateCompanionBuilder,
      (MemberNote, $$MemberNotesTableReferences),
      MemberNote,
      PrefetchHooks Function({bool memberId, bool createdById})
    >;
typedef $$AuditEventsTableCreateCompanionBuilder =
    AuditEventsCompanion Function({
      Value<int> id,
      required AuditCategory category,
      required String action,
      required AuditOutcome outcome,
      Value<int?> actorId,
      Value<String?> actorName,
      Value<int?> memberId,
      Value<String?> memberName,
      Value<int?> paymentId,
      Value<String?> receiptNumber,
      Value<int?> amountMinor,
      Value<String?> periodLabel,
      required String summary,
      Value<String?> detail,
      Value<DateTime> createdAt,
    });
typedef $$AuditEventsTableUpdateCompanionBuilder =
    AuditEventsCompanion Function({
      Value<int> id,
      Value<AuditCategory> category,
      Value<String> action,
      Value<AuditOutcome> outcome,
      Value<int?> actorId,
      Value<String?> actorName,
      Value<int?> memberId,
      Value<String?> memberName,
      Value<int?> paymentId,
      Value<String?> receiptNumber,
      Value<int?> amountMinor,
      Value<String?> periodLabel,
      Value<String> summary,
      Value<String?> detail,
      Value<DateTime> createdAt,
    });

class $$AuditEventsTableFilterComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AuditCategory, AuditCategory, String>
  get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AuditOutcome, AuditOutcome, String>
  get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberName => $composableBuilder(
    column: $table.memberName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paymentId => $composableBuilder(
    column: $table.paymentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodLabel => $composableBuilder(
    column: $table.periodLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberName => $composableBuilder(
    column: $table.memberName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paymentId => $composableBuilder(
    column: $table.paymentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodLabel => $composableBuilder(
    column: $table.periodLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AuditCategory, String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AuditOutcome, String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<int> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get actorName =>
      $composableBuilder(column: $table.actorName, builder: (column) => column);

  GeneratedColumn<int> get memberId =>
      $composableBuilder(column: $table.memberId, builder: (column) => column);

  GeneratedColumn<String> get memberName => $composableBuilder(
    column: $table.memberName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get paymentId =>
      $composableBuilder(column: $table.paymentId, builder: (column) => column);

  GeneratedColumn<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodLabel => $composableBuilder(
    column: $table.periodLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AuditEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AuditEventsTable,
          AuditEvent,
          $$AuditEventsTableFilterComposer,
          $$AuditEventsTableOrderingComposer,
          $$AuditEventsTableAnnotationComposer,
          $$AuditEventsTableCreateCompanionBuilder,
          $$AuditEventsTableUpdateCompanionBuilder,
          (
            AuditEvent,
            BaseReferences<_$AppDatabase, $AuditEventsTable, AuditEvent>,
          ),
          AuditEvent,
          PrefetchHooks Function()
        > {
  $$AuditEventsTableTableManager(_$AppDatabase db, $AuditEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<AuditCategory> category = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<AuditOutcome> outcome = const Value.absent(),
                Value<int?> actorId = const Value.absent(),
                Value<String?> actorName = const Value.absent(),
                Value<int?> memberId = const Value.absent(),
                Value<String?> memberName = const Value.absent(),
                Value<int?> paymentId = const Value.absent(),
                Value<String?> receiptNumber = const Value.absent(),
                Value<int?> amountMinor = const Value.absent(),
                Value<String?> periodLabel = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<String?> detail = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AuditEventsCompanion(
                id: id,
                category: category,
                action: action,
                outcome: outcome,
                actorId: actorId,
                actorName: actorName,
                memberId: memberId,
                memberName: memberName,
                paymentId: paymentId,
                receiptNumber: receiptNumber,
                amountMinor: amountMinor,
                periodLabel: periodLabel,
                summary: summary,
                detail: detail,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required AuditCategory category,
                required String action,
                required AuditOutcome outcome,
                Value<int?> actorId = const Value.absent(),
                Value<String?> actorName = const Value.absent(),
                Value<int?> memberId = const Value.absent(),
                Value<String?> memberName = const Value.absent(),
                Value<int?> paymentId = const Value.absent(),
                Value<String?> receiptNumber = const Value.absent(),
                Value<int?> amountMinor = const Value.absent(),
                Value<String?> periodLabel = const Value.absent(),
                required String summary,
                Value<String?> detail = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AuditEventsCompanion.insert(
                id: id,
                category: category,
                action: action,
                outcome: outcome,
                actorId: actorId,
                actorName: actorName,
                memberId: memberId,
                memberName: memberName,
                paymentId: paymentId,
                receiptNumber: receiptNumber,
                amountMinor: amountMinor,
                periodLabel: periodLabel,
                summary: summary,
                detail: detail,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AuditEventsTable,
      AuditEvent,
      $$AuditEventsTableFilterComposer,
      $$AuditEventsTableOrderingComposer,
      $$AuditEventsTableAnnotationComposer,
      $$AuditEventsTableCreateCompanionBuilder,
      $$AuditEventsTableUpdateCompanionBuilder,
      (
        AuditEvent,
        BaseReferences<_$AppDatabase, $AuditEventsTable, AuditEvent>,
      ),
      AuditEvent,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$AppSessionsTableTableManager get appSessions =>
      $$AppSessionsTableTableManager(_db, _db.appSessions);
  $$GymSettingsTableTableManager get gymSettings =>
      $$GymSettingsTableTableManager(_db, _db.gymSettings);
  $$MembershipPlansTableTableManager get membershipPlans =>
      $$MembershipPlansTableTableManager(_db, _db.membershipPlans);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db, _db.members);
  $$MembershipsTableTableManager get memberships =>
      $$MembershipsTableTableManager(_db, _db.memberships);
  $$MembershipPeriodsTableTableManager get membershipPeriods =>
      $$MembershipPeriodsTableTableManager(_db, _db.membershipPeriods);
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db, _db.payments);
  $$ReceiptsTableTableManager get receipts =>
      $$ReceiptsTableTableManager(_db, _db.receipts);
  $$ReceiptCountersTableTableManager get receiptCounters =>
      $$ReceiptCountersTableTableManager(_db, _db.receiptCounters);
  $$WhatsAppMessagesTableTableManager get whatsAppMessages =>
      $$WhatsAppMessagesTableTableManager(_db, _db.whatsAppMessages);
  $$MemberNotesTableTableManager get memberNotes =>
      $$MemberNotesTableTableManager(_db, _db.memberNotes);
  $$AuditEventsTableTableManager get auditEvents =>
      $$AuditEventsTableTableManager(_db, _db.auditEvents);
}
