import '../models.dart';

/// AI接客のデモ応答ロジック（プロトタイプ用のモック）。
/// 本開発では LLM API に置き換える。このロジックは店舗業態と
/// ユーザーの興味カテゴリからおすすめを案内する最低限のルールベース。
class AiConcierge {
  /// 最初の挨拶（店舗の口調 + ユーザーの興味を踏まえる）
  String greeting(AppUser me, BusinessUser store) {
    final interest = me.interestIds.isNotEmpty ? me.interestIds.first : null;
    final label = interest == null ? null : _categoryLabel(interest);
    final base = '${_opener(store)}'
        '${me.nickname}さん、${store.nickname}（${store.storeType}）のAI接客です。';
    if (label == null) {
      return '$base 釣りのことなら何でも聞いてください。';
    }
    return '$base $labelがお好みなんですね。'
        'うちの${_recommend(store)}がおすすめです。';
  }

  /// 店舗タイプごとの口調（本開発では LLM に店舗キャラ設定を渡して生成する）
  String _opener(BusinessUser store) {
    switch (store.storeType) {
      case '釣具店':
        return 'いらっしゃい！仕掛けやタックルの相談、何でも聞いてください。';
      case '乗り合い船・渡船':
        return 'いらっしゃい！当日の空き状況と出港時刻をお伝えします。';
      case '釣り堀・管理釣り場':
        return 'ようこそ。エサ・レンタル竿のご用意があります。';
      case 'フィッシングカフェ・飲食':
        return 'こんにちは。釣りのあとにひと息どうぞ。';
      case 'ロッド・リール修理工房':
        return 'いらっしゃいませ。メンテナンスのご相談は気軽にどうぞ。';
      default:
        return 'いらっしゃいませ。';
    }
  }

  /// ユーザー発話への応答
  String reply(String input, AppUser me, BusinessUser store) {
    final text = input.replaceAll(RegExp(r'\s'), '');
    if (text.contains('予約') || text.contains('来店') ||
        text.contains('乗船') || text.contains('出港')) {
      return 'ありがとうございます。土日は混み合うため、'
          '平日の午前中でしたらゆっくりご案内できます。'
          'ご希望の時間をメモしておきますね。'
          '（デモのため実際の予約機能は本開発で提供します）';
    }
    if (text.contains('おすすめ') || text.contains('オススメ') ||
        text.contains('釣れる')) {
      return '今回は${_recommend(store)}がおすすめです。'
          '狙いたい魚種があれば教えてください。';
    }
    if (text.contains('アジ') || text.contains('イカ') ||
        text.contains('キス') || text.contains('バス') ||
        text.contains('ニジマス') || text.contains('青物') ||
        text.contains('魚種')) {
      return '回遊魚から管理魚まで、釣り方に合わせてご案内できます。'
          '初心者には仕入れの良いお手軽スタイルから始めるのがおすすめです。';
    }
    if (text.contains('初心者') || text.contains('初めて')) {
      return '初めての方も大歓迎です。仕掛け・エサの使い方から'
          'スタッフが丁寧にご案内します。短時間のお試しからどうぞ。';
    }
    if (text.contains('料金') || text.contains('いくら') ||
        text.contains('価格')) {
      return 'ご利用内容によって変わりますが、まずは一度お試しいただけます。'
          '詳しいプランは店舗ページをご確認ください（デモの固定値です）。';
    }
    if (text.contains('何時') || text.contains('営業時間')) {
      return '本日は10:00〜18:00で営業しております。'
          '混雑しやすいのは土曜午前です。（デモの固定値です）';
    }
    if (text.contains('ライフジャケット') || text.contains('安全') ||
        text.contains('保険')) {
      return 'ライフジャケットの無料貸し出しと、安全に関するご案内を'
          '必ず行っています。お子さま連れも安心してご利用ください。';
    }
    if (text.contains('水') || text.contains('トイレ') || text.contains('絞め')) {
      return '水道とお手洗いをご用意しています。'
          '魚の絞め台・クーラーボックスの氷も借りられますので、お気軽にお声がけください。';
    }
    return '承知しました。「おすすめ」「料金」「営業時間」「予約」'
        '「ライフジャケット」など、気になることを聞いていただければ答えます。';
  }

  String _recommend(BusinessUser store) {
    switch (store.storeType) {
      case '釣具店':
        return '初心者向けのロッド＋リールお試しセット';
      case '乗り合い船・渡船':
        return '貸し竿・ライフジャケット付きの乗り合いプラン';
      case '釣り堀・管理釣り場':
        return '午前の放流後の釣れやすい時間帯プラン';
      case 'フィッシングカフェ・飲食':
        return '釣った魚の持ち込み調理メニュー';
      case 'ロッド・リール修理工房':
        return 'リールのオーバーホールお試しコース';
      default:
        return 'おすすめサービス';
    }
  }

  String _categoryLabel(String id) {
    const labels = {
      'sabiki': 'サビキ・堤防釣り',
      'surf': '投げ・サーフ釣り',
      'lure': 'ルアー・エギング',
      'fly': 'フライ・渓流釣り',
      'pond': '管理釣り場・淡水',
      'boat': '船釣り',
      'night': '夜釣り',
      'cook': '釣った魚を食べる',
      'tackle': '釣り具・自作仕掛け',
      'photo': '釣果・風景撮影',
      'travel': '遠征・釣行旅行',
      'cleanup': '釣り場の清掃・環境保護',
    };
    return labels[id] ?? '釣りのこと';
  }
}

/// グローバルインスタンス（本開発では DI / LLM API クライアントに置き換える）
final AiConcierge aiConcierge = AiConcierge();
