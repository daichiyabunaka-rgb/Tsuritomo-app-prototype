"""auth.users と public.profiles の整合を確認する（募集/コミュニティ作成失敗の診断）。
DB パスワードは環境変数 SUPA_DB_PASSWORD で渡す。
"""
import os
import pg8000.native

con = pg8000.native.Connection(
    "postgres.jkctwrphqomfetrlrsem",
    host="aws-0-ap-southeast-2.pooler.supabase.com",
    port=5432,
    database="postgres",
    password=os.environ["SUPA_DB_PASSWORD"],
    ssl_context=True,
    timeout=20,
)
try:
    auth_users = con.run(
        "select id, email, created_at from auth.users order by created_at"
    )
    profiles = con.run(
        "select id, nickname from public.profiles"
    )
    profile_ids = {row[0] for row in profiles}
    print("== auth.users ==")
    for uid, email, created in auth_users:
        has_profile = uid in profile_ids
        print(f"{email} | profiles行: {'あり' if has_profile else 'なし(破壊的!)'}")
    print("== public.profiles ==")
    for pid, nickname in profiles:
        print(f"{pid} | {nickname}")
finally:
    con.close()
