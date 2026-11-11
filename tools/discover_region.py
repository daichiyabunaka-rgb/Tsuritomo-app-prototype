"""プロジェクトのリージョンを特定する（Supavisor プーラー経由で接続試行）。"""
import os
import pg8000.native

ref = "jkctwrphqomfetrlrsem"
regions = [
    "ap-northeast-1", "ap-northeast-2", "ap-southeast-1", "ap-southeast-2",
    "ap-south-1", "us-east-1", "us-east-2", "us-west-1", "eu-west-1",
    "eu-west-2", "eu-west-3", "eu-central-1", "ca-central-1", "sa-east-1",
]
for r in regions:
    host = f"aws-0-{r}.pooler.supabase.com"
    try:
        con = pg8000.native.Connection(
            f"postgres.{ref}", host=host, port=5432, database="postgres",
            password=os.environ["SUPA_DB_PASSWORD"], ssl_context=True,
            timeout=8,
        )
        ver = con.run("select version()")[0][0]
        print("CONNECTED:", r, "|", ver[:50])
        con.close()
        break
    except Exception as e:
        print("fail:", r, str(e)[:90])
