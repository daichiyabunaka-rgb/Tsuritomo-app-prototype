"""auth.users を直接削除する際に必要な子テーブルの片付けを調べる。"""
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
    rows = con.run(
        """
        select conrelid::regclass::text as child,
               confdeltype,
               pg_get_constraintdef(oid)
        from pg_constraint
        where contype = 'f'
          and confrelid::regclass::text = 'auth.users'
        order by 1
        """
    )
    for child, deltype, defn in rows:
        print(f"{child} | on_delete={deltype} | {defn}")
finally:
    con.close()
