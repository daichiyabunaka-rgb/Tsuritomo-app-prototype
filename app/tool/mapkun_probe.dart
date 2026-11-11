// 釣りスポット情報共有MAPくん API の導通確認スクリプト（開発用）。
// Dart の HTTP/TLS スタックで API が利用できるかを確認する。
// 実行: dart run tool/mapkun_probe.dart
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:http/http.dart' as http;

const String ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Future<void> main() async {
  final client = http.Client();
  try {
    // 1. ページを取得して api_key（get_objects用）と my_connection_id を取り出す
    final page = await client.get(
      Uri.parse('https://share-map.net/fishing/'),
      headers: {'User-Agent': ua},
    );
    final html = utf8.decode(page.bodyBytes);
    final connMatch =
        RegExp(r'my_connection_id.{0,20}"([0-9a-f]{64})').firstMatch(html);
    final allKeys = RegExp(r'api_key","([0-9a-z]{16})')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toList();
    final connId = connMatch?.group(1) ?? '(none)';
    print('conn id: ${connId.substring(0, 10)}...');
    print('all api keys: $allKeys');
    // ページ内の出現順: get_objects_by_names が先、get_objects が後
    final apiKey = allKeys.length >= 2 ? allKeys[1] : allKeys.first;

    // 2. get_objects を呼ぶ
    final body = 'api_key=$apiKey&cmd=get_objects'
        '&lat_from=35.64&lat_to=35.74&lng_from=139.72&lng_to=139.82';
    final res = await client.post(
      Uri.parse('https://share-map.net/fishing/api/'),
      headers: {
        'User-Agent': ua,
        'Referer': 'https://share-map.net/fishing/',
        'Origin': 'https://share-map.net',
        'X-Requested-With': 'XMLHttpRequest',
        'Cookie': 'my_connection_id=$connId',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    final text = utf8.decode(res.bodyBytes);
    print('HTTP ${res.statusCode}, len=${text.length}');
    print(text.substring(0, text.length > 120 ? 120 : text.length));
  } finally {
    client.close();
  }
}
