"""アプリと同じREST経路（RLS有効）で募集・コミュニティ作成を検証する。
一時ユーザーを作成し、最後に削除する。"""
import json
import os
import urllib.request

BASE = "https://jkctwrphqomfetrlrsem.supabase.co"
PUBLISHABLE = "sb_publishable_xIVCNhG1LQrued-VRlbuww_NnyYUi3_"
SECRET = os.environ["SUPA_SECRET"]


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

# 1. 一時ユーザー作成（確認済み）
code, res = call("POST", "/auth/v1/admin/users", admin, {
    "email": "tsuritomo-rls-probe@example-test.com",
    "password": "RlsProbe123!@",
    "email_confirm": True,
})
uid = res.get("id")
print("create temp user:", code, uid)

# 2. ログインしてクライアントトークン取得
code, res = call("POST", "/auth/v1/token?grant_type=password",
                 {"apikey": PUBLISHABLE},
                 {"email": "tsuritomo-rls-probe@example-test.com",
                  "password": "RlsProbe123!@"})
token = res["access_token"]
client = {"apikey": PUBLISHABLE, "Authorization": f"Bearer {token}"}
print("login:", code)

# 3. profiles 行をアプリと同じように作成
code, res = call("POST", "/rest/v1/profiles", client, {
    "id": uid, "nickname": "RLS検証", "birth_decade": "30代",
    "gender": "male", "role": "general", "icon_category_id": "ramen",
    "interest_ids": ["ramen"], "bio": "",
})
print("insert profile:", code, res if code >= 400 else "ok")

# 4. 募集を作成（トリガーも通るか）
code, res = call("POST", "/rest/v1/recruitments", client, {
    "host_id": uid, "genre_id": "meshi", "title": "検証の募集",
    "body": "", "meetup": "駅前", "capacity": 3,
    "expires_at": "2026-12-31T12:00:00+00:00", "status": "active",
})
print("insert recruitment:", code,
      res[0]["id"] if code < 400 and res else res)
rec_id = res[0]["id"] if code < 400 and isinstance(res, list) else None

# 5. コミュニティを作成
code, res = call("POST", "/rest/v1/communities", client, {
    "owner_id": uid, "name": "検証コミュニティ", "description": "",
})
print("insert community:", code,
      res[0]["id"] if code < 400 and res else res)
com_id = res[0]["id"] if code < 400 and isinstance(res, list) else None

# 6. コミュニティ参加 + チャット部屋作成（joinCommunity の経路）
if com_id:
    code, res = call("POST", "/rest/v1/community_members", client, {
        "community_id": com_id, "user_id": uid,
    })
    print("join community:", code, res if code >= 400 else "ok")
    code, res = call("POST", "/rest/v1/chat_rooms", client, {
        "community_id": com_id, "type": "community",
    })
    room_id = res[0]["id"] if code < 400 and isinstance(res, list) else None
    print("create chat room:", code, room_id)
    if room_id:
        code, res = call("POST", "/rest/v1/chat_room_members", client, {
            "room_id": room_id, "user_id": uid,
        })
        print("join chat room:", code, res if code >= 400 else "ok")
        code, res = call("POST", "/rest/v1/chat_messages", client, {
            "room_id": room_id, "sender_id": uid,
            "body": "検証メッセージ", "is_system": True,
        })
        print("post message:", code, res if code >= 400 else "ok")

# 7. 後片付け（ユーザーごと削除。カスケードでデータも消える）
code, res = call("DELETE", f"/auth/v1/admin/users/{uid}", admin)
print("cleanup:", code)
