import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

/// 画像の取得と保存（アイコン画像の投稿など）。
/// - すべての画像は指定サイズに自動リサイズされ、JPEG品質を下げて
///   ファイル容量を抑える（ベータ: アイコン 400px/品質70、投稿写真 800px/品質70）
/// - モックモード: リサイズ済み画像をアプリ専用領域に保存
/// - Supabase モード: Storage の公開バケットへアップロードし公開URLを返す
/// アップロードに失敗した場合は端末内パスにフォールバックする。
class IconService {
  /// アイコン画像（400px四方・品質70。プロフィール表示に十分）
  Future<String?> pickAndSave(ImageSource source) {
    return _pickAndSave(
      source,
      subDir: 'icons',
      prefix: 'icon',
      bucket: 'icons',
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 70,
    );
  }

  /// アップロードするファイルの上限（KB）。超える場合は警告ログのみ
  /// （image_picker のリサイズでほぼ確実に収まるが、稀に端末によって
  ///  圧縮が効かないケースがあるため保険として設ける）
  static const int maxUploadKb = 512;

  Future<String?> _pickAndSave(
    ImageSource source, {
    required String subDir,
    required String prefix,
    required String bucket,
    double? maxWidth,
    double? maxHeight,
    int imageQuality = 70,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
    if (picked == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final targetDir =
        Directory('${dir.path}${Platform.pathSeparator}$subDir');
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    final ts = DateTime.now().microsecondsSinceEpoch;
    final dest =
        '${targetDir.path}${Platform.pathSeparator}${prefix}_$ts.jpg';
    File(picked.path).copySync(dest);

    // 容量チェック（超過時はログのみ。image_picker の圧縮で通常は問題ない）
    final sizeKb = File(dest).lengthSync() ~/ 1024;
    if (sizeKb > maxUploadKb) {
      debugPrint('$prefix: file size ${sizeKb}KB > ${maxUploadKb}KB');
    }

    if (AppConfig.useSupabase) {
      try {
        final client = Supabase.instance.client;
        final uid = client.auth.currentUser?.id;
        if (uid != null) {
          final bytes = File(dest).readAsBytesSync();
          final remotePath = '$uid/${prefix}_$ts.jpg';
          await client.storage.from(bucket).uploadBinary(
                remotePath,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
          return client.storage.from(bucket).getPublicUrl(remotePath);
        }
      } catch (e) {
        // アップロード失敗時は端末内パスで続行（デバッグ用に記録のみ）
        debugPrint('$prefix upload failed: $e');
      }
    }
    return dest;
  }
}

/// グローバルインスタンス（本開発では DI / Riverpod Provider に置き換える）
final IconService iconService = IconService();
