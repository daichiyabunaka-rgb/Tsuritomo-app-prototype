"""auth.users にだけ存在し profiles が無いアカウントを補完する
（募集・コミュニティ作成のFK違反を解消する）。
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
    missing = con.run(
        """
        select u.id, u.email
        from auth.users u
        left join public.profiles p on p.id = u.id
        where p.id is null
        """
    )
    print(f"backfill targets: {len(missing)}")
    for uid, email in missing:
        local = email.split("@")[0]
        con.run(
            """
            insert into public.profiles
              (id, nickname, birth_decade, gender, role,
               icon_category_id, interest_ids, bio)
            values
              (:uid, :nickname, '非公開', 'undisclosed', 'general',
               'ramen', '{}', '')
            on conflict (id) do nothing
            """,
            uid=uid,
            nickname=f"{local}（プロフィール未設定）",
        )
        print(f"  created profile: {email}")
    # 確認
    cnt = con.run(
        "select count(*) from public.profiles p "
        "join auth.users u on u.id = p.id"
    )
    print("profiles rows joined to auth.users:", cnt[0][0])
finally:
    con.close()
