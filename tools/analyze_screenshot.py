"""解析截图：调用千问多模态 API 描述 UI 布局"""
import base64
import json
import sys
import urllib.request

API_KEY = "sk-ws-H.ERYHIXX.YbcV.MEQCIFSKscDGWSC2htlmg-1hUm1FKjhrTuFKkiDu8ngtXju_AiBsc7CYNLwCkGcC2R4fp9jBSFcywArzuwSxVnDFt54eBA"
URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

def analyze(image_path: str, question: str) -> str:
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")
    payload = {
        "model": "qwen-vl-plus",
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
                    {"type": "text", "text": question},
                ],
            }
        ],
        "max_tokens": 1200,
    }
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data["choices"][0]["message"]["content"]

if __name__ == "__main__":
    path = sys.argv[1]
    question = sys.argv[2]
    print(analyze(path, question))
