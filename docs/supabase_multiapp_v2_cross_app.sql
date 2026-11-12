-- ============================================================
-- ともつく！連携マイグレーション（v2: アプリ横断表示）
-- 対象: 共有プロジェクト（犬とも！稼働中プロジェクト）追加のみ
--
-- 内容:
--   profiles.cross_app_visible boolean
--   - false（既定）: そのアプリのプロフィールはそのアプリ内だけで表示
--   - true: 「ともつく！全体」に表示され、他のアプリ（犬とも！/釣りとも！等）
--     の「近くの人」「探す」にも、そのアプリのプロフィールが
--     アプリ名バッジ付きで現れる
--   - ユーザー詳細の「使っているともつく！」一覧も、この設定が true の
--     アプリだけが表示される
--
-- チャットの app_id 'cross' は新規テーブル不要（chat_rooms.app_id への
-- 値としてそのまま使う。get_or_create_dm の p_app に 'cross' を渡すと
-- そのまま機能する）
-- ============================================================

begin;

alter table public.profiles
  add column if not exists cross_app_visible boolean not null default false;

commit;
