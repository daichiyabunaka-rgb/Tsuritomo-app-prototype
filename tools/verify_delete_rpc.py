"""delete_my_account RPC をREST経由（RLS/authenticated）で検証する。"""
import json
import os
import time
import urllib.request

BASE = "https://jkctwrphqomfetrlrsem.supabase.co"
PUBLISHABLE = "sb_publishable_xIVCNhG1LQrued-VRlbuww_NnyYUi3_"
SECRET = os.environ["SUPA_SECRET"]
EMAIL = f"tsuritomo-del-{int(time.time())}@example-test.com"
PASSWORD = "DelProbe123!@"


def call(method, path, headers, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={**headers, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


admin = {"apikey": SECRET, "Authorization": f"Bearer {SECRET}"}

# 一時ユーザー作成 + プロフィール + 募集 を作り、その後削除する
code, res = call("POST", "/auth/v1/admin/users", admin, {
    "email": EMAIL, "password": PASSWORD, "email_confirm": True,
})
uid = res["id"]
print("create:", code)

code, res = call("POST", "/auth/v1/token?grant_type=password",
                 {"apikey": PUBLISHABLE},
                 {"email": EMAIL, "password": PASSWORD})
token = res["access_token"]
client = {"apikey": PUBLISHABLE, "Authorization": f"Bearer {token}"}

code, _ = call("POST", "/rest/v1/profiles", client, {
    "id": uid, "nickname": "削除検証", "birth_decade": "30代",
    "gender": "male", "role": "general", "icon_category_id": "ramen",
    "interest_ids": [], "bio": "",
})
print("profile:", code)
code, _ = call("POST", "/rest/v1/recruitments", client, {
    "host_id": uid, "genre_id": "meshi", "title": "削除対象の募集",
    "body": "", "meetup": "駅", "capacity": 3,
    "expires_at": "2026-12-31T12:00:00+00:00", "status": "active",
})
print("recruitment:", code)

# RPC でアカウント削除
code, res = call("POST", "/rest/v1/rpc/delete_my_account", client, {})
print("delete_my_account rpc:", code, res if code >= 400 else "OK")

# 削除後、同じパスワードでログインできないことを確認
code, res = call("POST", "/auth/v1/token?grant_type=password",
                 {"apikey": PUBLISHABLE},
                 {"email": EMAIL, "password": PASSWORD})
print("login after delete:", code, "(400 = 削除済みで期待どおり)")
