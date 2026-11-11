"""Supabase (Postgres) に docs/supabase_schema.sql を適用するワンオフスクリプト。
使い方: DB パスワードは環境変数 SUPA_DB_PASSWORD で渡す（ファイルに書かない）。

pg8000 はマルチステートメント実行できないため、$$（ドル引用符）の中の
セミコロンを保護したまま文に分割して順に実行する。
"""
import os
import sys
import pg8000.native

REQUIRED_TABLES = []


def split_statements(sql: str):
    statements = []
    buf = []
    in_dollar = False
    i = 0
    while i < len(sql):
        ch = sql[i]
        if not in_dollar and sql.startswith("$$", i):
            in_dollar = True
            buf.append("$$")
            i += 2
            continue
        if in_dollar and sql.startswith("$$", i):
            in_dollar = False
            buf.append("$$")
            i += 2
            continue
        if not in_dollar and ch == ";":
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        statements.append(tail)
    return statements


def strip_comments(statements):
    out = []
    for s in statements:
        lines = []
        for line in s.splitlines():
            ls = line.strip()
            if ls.startswith("--"):
                continue
            lines.append(line)
        cleaned = "\n".join(lines).strip()
        if cleaned:
            out.append(cleaned)
    return out


def main():
    host = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5432
    # プーラー経由の場合はユーザー名は postgres.<project_ref> 形式
    user = sys.argv[3] if len(sys.argv) > 3 else "postgres"
    password = os.environ["SUPA_DB_PASSWORD"]
    sql = open(
        os.path.join(os.path.dirname(__file__), "..", "docs", sys.argv[4] if len(sys.argv) > 4 else "supabase_schema.sql"),
        encoding="utf-8",
    ).read()
    statements = strip_comments(split_statements(sql))
    print(f"{len(statements)} statements to run")

    con = pg8000.native.Connection(
        user, host=host, port=port, database="postgres",
        password=password, ssl_context=True, timeout=20,
    )
    try:
        ran = 0
        for stmt in statements:
            con.run(stmt)
            ran += 1
        print(f"applied {ran} statements")
        rows = con.run(
            "select table_name from information_schema.tables "
            "where table_schema = 'public'"
        )
        tables = sorted(r[0] for r in rows)
        print("tables:", tables)
        missing = [t for t in REQUIRED_TABLES if t not in tables]
        if missing:
            print("MISSING:", missing)
            sys.exit(1)
        print("OK: all tables created")
    finally:
        con.close()


if __name__ == "__main__":
    main()
