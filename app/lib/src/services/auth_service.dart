import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'app_config.dart';

/// 認証サービス。
/// - Supabase モード（--dart-define で SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY
///   を渡した場合）: 本物の Supabase Auth（メール・パスワード）と profiles テーブル
/// - モックモード（未指定）: 端末内の簡易認証（SharedPreferences）
/// どちらも画面側は同じ API を使う。
class AuthService extends ChangeNotifier {
  static const _kAccounts = 'tsuritomo_accounts';
  static const _kSession = 'tsuritomo_session';

  final Map<String, _Account> _accounts = {}; // モック用: key = email(小文字)
  String? _sessionEmail; // モック用
  final Map<String, dynamic> _profileCache = {}; // Supabase用: profiles 行
  bool initialized = false;

  bool get useSupabase => AppConfig.useSupabase;

  SupabaseClient get _client {
    // Supabase は main() で AppConfig.useSupabase が true のときのみ初期化される
    return Supabase.instance.client;
  }

  String? get sessionEmail =>
      useSupabase ? _client.auth.currentUser?.email : _sessionEmail;

  bool get hasSession {
    if (useSupabase) {
      return _client.auth.currentSession != null;
    }
    return _sessionEmail != null;
  }

  Future<void> init() async {
    if (initialized) return;
    if (!useSupabase) {
      // モック: 端末に保存したアカウントとセッションを復元する
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kAccounts) ?? const [];
      for (final json in raw) {
        try {
          final acc =
              _Account.fromJson(jsonDecode(json) as Map<String, dynamic>);
          _accounts[acc.email] = acc;
        } catch (_) {
          // 壊れたレコードは読み飛ばす
        }
      }
      final saved = prefs.getString(_kSession);
      if (saved != null && _accounts.containsKey(saved)) {
        _sessionEmail = saved;
      }
    }
    initialized = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ register

  /// 会員登録（成功すると同時にログインする）。
  /// Supabase でメール確認が必須の設定の場合、確認メール送信の案内を返す。
  /// [role] は一般 / ビジネスの区別（登録フローが分かれている）。
  Future<void> register({
    required String email,
    required String password,
    required String nickname,
    required String decade,
    required String gender,
    required String iconCategoryId,
    required List<String> interestIds,
    required String bio,
    String? iconImagePath,
    String role = 'general',
    String? websiteUrl,
    String? snsNote,
    String? phone,
    String? storeType,
  }) async {
    if (useSupabase) {
      try {
        final res = await _client.auth.signUp(
          email: email.trim(),
          password: password,
        );
        if (res.user == null) {
          throw AuthException('登録できませんでした。しばらくしてからもう一度お試しください');
        }
        if (res.session == null) {
          // メール確認が必須のケース
          throw const AuthException(
              '確認メールを送信しました。メール内のリンクで登録を完了してください（迷惑メール箱も確認）');
        }
        await _upsertProfile(
          nickname: nickname,
          decade: decade,
          gender: gender,
          iconCategoryId: iconCategoryId,
          interestIds: interestIds,
          bio: bio,
          iconImagePath: iconImagePath,
          role: role,
          websiteUrl: websiteUrl,
          snsNote: snsNote,
          phone: phone,
          storeType: storeType,
        );
      } on AuthException {
        rethrow;
      } on AuthApiException catch (e) {
        throw AuthException(_friendlyAuthError(e));
      } catch (_) {
        throw const AuthException('登録中にエラーが発生しました');
      }
      notifyListeners();
      return;
    }

    // ---- モック
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw AuthException('このメールアドレスは既に登録されています');
    }
    final acc = _Account(
      id: 'acc-${_accounts.length + 1}',
      email: key,
      passwordHash: _mockHash(key, password),
      nickname: nickname,
      decade: decade,
      gender: gender,
      iconCategoryId: iconCategoryId,
      interestIds: interestIds,
      bio: bio,
      iconImagePath: iconImagePath,
      role: role,
      websiteUrl: websiteUrl,
      snsNote: snsNote,
      phone: phone,
      storeType: storeType,
    );
    _accounts[key] = acc;
    _sessionEmail = key;
    _persistMock();
    notifyListeners();
  }

  // ------------------------------------------------------------ login

  Future<void> login(String email, String password) async {
    if (useSupabase) {
      try {
        final res = await _client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        if (res.session == null) {
          throw const AuthException('メールアドレスまたはパスワードが違います');
        }
        await _loadProfileCache();
      } on AuthException {
        rethrow;
      } on AuthApiException catch (e) {
        throw AuthException(_friendlyAuthError(e));
      } catch (_) {
        throw const AuthException('ログイン中にエラーが発生しました');
      }
      notifyListeners();
      return;
    }

    // ---- モック
    final key = email.trim().toLowerCase();
    final acc = _accounts[key];
    if (acc == null || acc.passwordHash != _mockHash(key, password)) {
      throw AuthException('メールアドレスまたはパスワードが違います');
    }
    _sessionEmail = key;
    _persistMock();
    notifyListeners();
  }

  // ------------------------------------------------------------ logout

  Future<void> logout() async {
    if (useSupabase) {
      try {
        await _client.auth.signOut();
      } catch (_) {
        // スキップ（セッション切れの場合も無視してログイン画面へ戻す）
      }
      _profileCache.clear();
    } else {
      _sessionEmail = null;
      _persistMock();
    }
    notifyListeners();
  }

  /// アカウント削除（profiles・募集・コミュニティ・部屋・auth ユーザーを含む）。
  /// Supabase モードは delete_my_account() を呼ぶ（適用済みマイグレーション）。
  Future<void> deleteAccount() async {
    if (useSupabase) {
      await _client.rpc('delete_my_account');
      _profileCache.clear();
      try {
        await _client.auth.signOut();
      } catch (_) {
        // 削除後のセッション無効化は best-effort
      }
      notifyListeners();
      return;
    }
    // モック: 端末から自分のアカウントを消す
    final email = _sessionEmail;
    if (email != null) {
      _accounts.remove(email);
      _sessionEmail = null;
      _persistMock();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ profile

  /// セッション中のユーザーを AppUser に変換して返す
  Future<AppUser?> buildSessionUser({
    required double lat,
    required double lng,
  }) async {
    if (useSupabase) {
      final user = _client.auth.currentUser;
      if (user == null) return null;
      await _loadProfileCache();
      // 自己修復: profiles 行が無い古いアカウント（確認メール時代の登録で
      // プロフィール作成が漏れたもの）は最小限の行を自動作成する。
      // これが無いと recruitments / communities の外部キー違反で
      // 募集・コミュニティ作成が失敗する。
      if (_profileCache.isEmpty) {
        await _client.from('profiles').upsert({
          'id': user.id,
          'nickname': '名無し',
          'birth_decade': '非公開',
          'gender': 'undisclosed',
          'role': 'general',
          'icon_category_id': 'sabiki',
          'interest_ids': const <String>[],
          'bio': '',
        });
        await _loadProfileCache();
      }
      final role = (_profileCache['role'] as String?) ?? 'general';
      final base = {
        'id': user.id,
        'nickname': (_profileCache['nickname'] as String?) ?? '名無し',
        'decade': (_profileCache['birth_decade'] as String?) ?? '非公開',
        'gender': (_profileCache['gender'] as String?) ?? 'undisclosed',
        'iconCategoryId':
            (_profileCache['icon_category_id'] as String?) ?? 'sabiki',
        'interestIds':
            ((_profileCache['interest_ids'] as List?) ?? const []).cast<String>(),
        'bio': (_profileCache['bio'] as String?) ?? '',
        'lat': lat,
        'lng': lng,
        'iconImagePath': _profileCache['icon_image_path'] as String?,
        'websiteUrl': _profileCache['website_url'] as String?,
        'snsNote': _profileCache['sns_note'] as String?,
        'phone': _profileCache['phone'] as String?,
      };
      if (role == 'business') {
        return BusinessUser(
          id: base['id'] as String,
          nickname: base['nickname'] as String,
          decade: '経営者',
          gender: base['gender'] as String,
          iconCategoryId: base['iconCategoryId'] as String,
          interestIds: base['interestIds'] as List<String>,
          bio: base['bio'] as String,
          lat: lat,
          lng: lng,
          storeType: (_profileCache['store_type'] as String?) ?? '店舗',
          iconImagePath: base['iconImagePath'] as String?,
          websiteUrl: base['websiteUrl'] as String?,
          snsNote: base['snsNote'] as String?,
          phone: base['phone'] as String?,
        );
      }
      return AppUser(
        id: base['id'] as String,
        nickname: base['nickname'] as String,
        decade: base['decade'] as String,
        gender: base['gender'] as String,
        iconCategoryId: base['iconCategoryId'] as String,
        interestIds: base['interestIds'] as List<String>,
        bio: base['bio'] as String,
        lat: lat,
        lng: lng,
        iconImagePath: base['iconImagePath'] as String?,
        websiteUrl: base['websiteUrl'] as String?,
        snsNote: base['snsNote'] as String?,
        phone: base['phone'] as String?,
      );
    }
    final email = _sessionEmail;
    if (email == null) return null;
    final acc = _accounts[email];
    if (acc == null) return null;
    if (acc.role == 'business') {
      return BusinessUser(
        id: acc.id,
        nickname: acc.nickname,
        decade: '経営者',
        gender: acc.gender,
        iconCategoryId: acc.iconCategoryId,
        interestIds: acc.interestIds,
        bio: acc.bio,
        lat: lat,
        lng: lng,
        storeType: acc.storeType ?? '店舗',
        iconImagePath: acc.iconImagePath,
        websiteUrl: acc.websiteUrl,
        snsNote: acc.snsNote,
        phone: acc.phone,
      );
    }
    return AppUser(
      id: acc.id,
      nickname: acc.nickname,
      decade: acc.decade,
      gender: acc.gender,
      iconCategoryId: acc.iconCategoryId,
      interestIds: acc.interestIds,
      bio: acc.bio,
      lat: lat,
      lng: lng,
      iconImagePath: acc.iconImagePath,
      websiteUrl: acc.websiteUrl,
      snsNote: acc.snsNote,
      phone: acc.phone,
    );
  }

  String? sessionNickname() {
    if (useSupabase) return _profileCache['nickname'] as String?;
    final email = _sessionEmail;
    if (email == null) return null;
    return _accounts[email]?.nickname;
  }

  /// ログイン中アカウントのプロフィール更新
  Future<void> updateCurrentProfile({
    String? nickname,
    String? decade,
    String? gender,
    String? iconCategoryId,
    List<String>? interestIds,
    String? bio,
    String? iconImagePath,
    String? websiteUrl,
    String? snsNote,
    String? phone,
    String? storeType,
  }) async {
    if (useSupabase) {
      await _upsertProfile(
        nickname: nickname,
        decade: decade,
        gender: gender,
        iconCategoryId: iconCategoryId,
        interestIds: interestIds,
        bio: bio,
        iconImagePath: iconImagePath,
        websiteUrl: websiteUrl,
        snsNote: snsNote,
        phone: phone,
        storeType: storeType,
        onlyUpdate: true,
      );
      notifyListeners();
      return;
    }
    final email = _sessionEmail;
    if (email == null) return;
    final old = _accounts[email]!;
    _accounts[email] = _Account(
      id: old.id,
      email: old.email,
      passwordHash: old.passwordHash,
      nickname: nickname ?? old.nickname,
      decade: decade ?? old.decade,
      gender: gender ?? old.gender,
      iconCategoryId: iconCategoryId ?? old.iconCategoryId,
      interestIds: interestIds ?? old.interestIds,
      bio: bio ?? old.bio,
      iconImagePath: iconImagePath ?? old.iconImagePath,
      role: old.role,
      websiteUrl: websiteUrl ?? old.websiteUrl,
      snsNote: snsNote ?? old.snsNote,
      phone: phone ?? old.phone,
      storeType: storeType ?? old.storeType,
    );
    _persistMock();
    notifyListeners();
  }

  // ------------------------------------------------------------ internals

  Future<void> _loadProfileCache() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final rows =
        await _client.from('profiles').select().eq('id', user.id).limit(1);
    final list = rows as List;
    if (list.isNotEmpty) {
      _profileCache
        ..clear()
        ..addAll((list.first as Map).cast<String, dynamic>());
    }
  }

  Future<void> _upsertProfile({
    String? nickname,
    String? decade,
    String? gender,
    String? iconCategoryId,
    List<String>? interestIds,
    String? bio,
    String? iconImagePath,
    String? role,
    String? websiteUrl,
    String? snsNote,
    String? phone,
    String? storeType,
    bool onlyUpdate = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    // Supabase モードでローカルパス（http で始まらない値）が渡ってきた場合、
    // 他のユーザーから見えないため icon_image_path に保存しない。
    // 空文字列＝明示的な解除のためそのまま保存する。
    String? effectiveIconPath;
    if (iconImagePath != null && iconImagePath.isNotEmpty) {
      if (!iconImagePath.startsWith('http')) {
        effectiveIconPath = null; // ローカルパスはサーバーに保存しない
      } else {
        effectiveIconPath = iconImagePath;
      }
    } else if (iconImagePath != null && iconImagePath.isEmpty) {
      effectiveIconPath = ''; // 明示的な画像解除
    }
    final data = {
      // 登録時のみ入力し、更新時は渡された項目だけを書き換える
      if (!onlyUpdate) 'id': user.id,
      if (!onlyUpdate && role != null) 'role': role,
      'nickname': ?nickname,
      'birth_decade': ?decade,
      'gender': ?gender,
      'icon_category_id': ?iconCategoryId,
      'interest_ids': ?interestIds,
      'bio': ?bio,
      'icon_image_path': ?effectiveIconPath,
      'website_url': ?websiteUrl,
      'sns_note': ?snsNote,
      'phone': ?phone,
      'store_type': ?storeType,
    };
    if (data.isEmpty) return;
    if (onlyUpdate) {
      await _client.from('profiles').update(data).eq('id', user.id);
    } else {
      await _client.from('profiles').upsert(data);
    }
    await _loadProfileCache();
  }

  String _friendlyAuthError(AuthApiException e) {
    switch (e.code) {
      case 'email_not_confirmed':
        return 'メール確認がまだ完了していません。確認メールのリンクを開いてください';
      case 'invalid_credentials':
        return 'メールアドレスまたはパスワードが違います';
      case 'over_email_send_rate_limit':
        return '確認メールの送信回数が上限に達しました。しばらく待ってからもう一度お試しください';
      case 'user_already_exists':
      case 'email_exists':
        return 'このメールアドレスは既に登録されています';
      case 'weak_password':
        return 'パスワードが弱すぎます。6文字以上の推測されにくいものにしてください';
      default:
        return e.message;
    }
  }

  // ------------------------------------------------------------ mock only

  String _mockHash(String email, String password) {
    final digest =
        sha256.convert(utf8.encode('tsuritomo-v1:$email:$password'));
    return digest.toString();
  }

  void _persistMock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kAccounts,
        _accounts.values.map((a) => jsonEncode(a.toJson())).toList());
    if (_sessionEmail == null) {
      await prefs.remove(_kSession);
    } else {
      await prefs.setString(_kSession, _sessionEmail!);
    }
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class _Account {
  final String id;
  final String email;
  final String passwordHash;
  final String nickname;
  final String decade;
  final String gender;
  final String iconCategoryId;
  final List<String> interestIds;
  final String bio;
  final String? iconImagePath;
  final String role;
  final String? websiteUrl;
  final String? snsNote;
  final String? phone;
  final String? storeType;

  _Account({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.nickname,
    required this.decade,
    required this.gender,
    required this.iconCategoryId,
    required this.interestIds,
    required this.bio,
    this.iconImagePath,
    this.role = 'general',
    this.websiteUrl,
    this.snsNote,
    this.phone,
    this.storeType,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'passwordHash': passwordHash,
        'nickname': nickname,
        'decade': decade,
        'gender': gender,
        'iconCategoryId': iconCategoryId,
        'interestIds': interestIds,
        'bio': bio,
        'iconImagePath': iconImagePath,
        'role': role,
        'websiteUrl': websiteUrl,
        'snsNote': snsNote,
        'phone': phone,
        'storeType': storeType,
      };

  factory _Account.fromJson(Map<String, dynamic> j) => _Account(
        id: j['id'] as String,
        email: j['email'] as String,
        passwordHash: j['passwordHash'] as String,
        nickname: j['nickname'] as String,
        decade: j['decade'] as String,
        gender: j['gender'] as String,
        iconCategoryId: j['iconCategoryId'] as String,
        interestIds: (j['interestIds'] as List).cast<String>(),
        bio: j['bio'] as String,
        iconImagePath: j['iconImagePath'] as String?,
        role: (j['role'] as String?) ?? 'general',
        websiteUrl: j['websiteUrl'] as String?,
        snsNote: j['snsNote'] as String?,
        phone: j['phone'] as String?,
        storeType: j['storeType'] as String?,
      );
}

/// グローバルインスタンス（本開発では DI / Riverpod Provider に置き換える）
final AuthService authService = AuthService();
