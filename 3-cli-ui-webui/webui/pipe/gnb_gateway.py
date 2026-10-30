"""
title: GNB AI Gateway
author: GNB AI Platform (demo)
version: 1.0.0
description: GNB Assist's use-case assistants. Each one is a governed route through the GNB AI Gateway (Kong): the use case's app key, the signed-in employee as the end user, and Kong's policies on every call.
"""
# An Open WebUI "pipe" (manifold): one model per use case. It calls Kong's OpenAI-compatible /v1 with the use case's key
# (apikey header) and the signed-in employee's id (X-End-User), then shows what Kong did as a status line under the answer
# (site, model, tokens, cache, budget), and turns policy decisions (guards, access, budget) into plain messages for staff.
# Kong does all the governing; nothing here changes a request or decides anything.
import json
import time

import aiohttp
from pydantic import BaseModel, Field

ASSISTANTS = {
    "retail-assistant": {"name": "Retail Assistant", "model": "gnb-assistant", "key": "KEY_RETAIL"},
    "retail-copilot": {"name": "Retail Copilot", "model": "gnb-copilot", "key": "KEY_RETAIL"},
    "aml-copilot": {"name": "AML Copilot", "model": "gnb-copilot", "key": "KEY_AML"},
    "complaints-copilot": {"name": "Complaints Copilot", "model": "gnb-assistant", "key": "KEY_COMPLAINTS"},
}
# where each answer came from (the demo factory: DC1 primary 7B + 1.5B, DC2 DR 1.5B)
SITES = {("gnb-assistant", "qwen2.5:7b"): "DC1 · primary", ("gnb-assistant", "qwen2.5:1.5b"): "DC2 · DR site",
         ("gnb-copilot", "qwen2.5:7b"): "DC1 · large model", ("gnb-copilot", "qwen2.5:1.5b"): "DC1 · small model"}
GUARDS = {  # Kong plugin → (what staff see, the status line)
    "ai-semantic-prompt-guard": ("I can't help with investment advice in GNB Assist. For investment questions, please refer the customer to a licensed GNB wealth adviser.",
                                 "GNB AI policy · investment-advice guard blocked this request"),
    "ai-semantic-response-guard": ("I can't confirm that here. The decision on an application comes from a GNB officer, who will contact the customer directly.",
                                   "GNB AI policy · the answer check withheld a reply that would commit the bank"),
    "ai-prompt-guard": ("I can't do that. This request isn't allowed by GNB's AI policy.",
                        "GNB AI policy · prompt-injection guard blocked this request"),
}


class Pipe:
    class Valves(BaseModel):
        KONG_URL: str = Field(default="http://host.docker.internal:8000/v1/chat/completions", description="Kong's OpenAI-compatible endpoint")
        KEY_RETAIL: str = Field(default="", description="Retail copilot app key (consumer group retail-copilot)")
        KEY_AML: str = Field(default="", description="AML summaries app key (aml-summaries)")
        KEY_COMPLAINTS: str = Field(default="", description="Complaints copilot app key (complaints-copilot)")
        SHOW_GATEWAY_STATUS: bool = Field(default=True, description="Show what the gateway did under each answer")
        TIMEOUT_S: int = 90

    def __init__(self):
        self.type = "manifold"
        self.valves = self.Valves()

    def pipes(self):
        return [{"id": k, "name": v["name"]} for k, v in ASSISTANTS.items()]

    async def _status(self, emit, text):
        if emit and self.valves.SHOW_GATEWAY_STATUS:
            await emit({"type": "status", "data": {"description": text, "done": True}})

    async def pipe(self, body: dict, __user__: dict = None, __event_emitter__=None):
        aid = body.get("model", "").split(".", 1)[-1]
        a = ASSISTANTS.get(aid)
        if not a:
            return f"Unknown GNB assistant: {aid}"
        end_user = ((__user__ or {}).get("email") or "unknown").split("@")[0]
        messages = [{"role": m.get("role"), "content": m.get("content")} for m in body.get("messages", []) if m.get("role") in ("system", "user", "assistant")]
        headers = {"Content-Type": "application/json", "apikey": getattr(self.valves, a["key"]), "X-End-User": end_user}
        t0 = time.time()
        try:
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=self.valves.TIMEOUT_S)) as s:
                async with s.post(self.valves.KONG_URL, headers=headers, json={"model": a["model"], "messages": messages}) as r:
                    status, h, raw = r.status, r.headers, await r.text()
        except Exception as e:  # Kong unreachable
            await self._status(__event_emitter__, "GNB AI Gateway · unreachable")
            return f"GNB Assist can't reach the AI service right now. ({type(e).__name__})"
        dt = time.time() - t0
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = {}

        if status == 200:
            model = (h.get("X-Kong-LLM-Model") or "").split("/", 1)[-1]
            usage = (data.get("usage") or {}).get("total_tokens")
            parts = ["GNB AI Gateway"]
            if (h.get("X-Cache-Status") or "").lower() == "hit":
                parts += ["answered from cache · no model call", f"{dt:.1f} s"]
            else:
                parts += [p for p in [SITES.get((a["model"], model)), model, f"{usage} tokens" if usage is not None else None, f"{dt:.1f} s"] if p]
            # Kong names the budget headers per window and policy: X-AI-RateLimit-Remaining-600-policy-1, …-day-policy-1
            pick = lambda w: next((v for k, v in h.items() if k.lower().startswith(f"x-ai-ratelimit-remaining-{w}")), None)
            b600, bday = pick("600"), pick("day")
            if b600 is not None:
                parts.append(f"budget left {int(b600):,} (10 min) · {int(bday or 0):,} today")
            elif bday is not None:
                parts.append(f"budget left today {int(bday):,}")
            await self._status(__event_emitter__, " · ".join(parts))
            return ((data.get("choices") or [{}])[0].get("message") or {}).get("content") or ""

        err = data.get("error") if isinstance(data.get("error"), dict) else data
        plugin = (err or {}).get("plugin")
        if status == 403 and plugin in GUARDS:
            text, line = GUARDS[plugin]
            d = (err or {}).get("detail") or {}
            matched = d.get("matched_prompt") or d.get("matched_response") or d.get("matched_pattern")
            await self._status(__event_emitter__, line + (f' (matched "{matched}")' if matched and plugin != "ai-prompt-guard" else ""))
            return text
        if status == 403:
            await self._status(__event_emitter__, "GNB AI Gateway · access denied: this use case isn't onboarded")
            return "This assistant isn't enabled for your team yet. Ask the GNB AI platform team to onboard your use case."
        if status == 429:
            await self._status(__event_emitter__, "GNB AI Gateway · token budget reached · no model call")
            return (err or {}).get("message") or "GNB AI budget reached for this use case."
        await self._status(__event_emitter__, f"GNB AI Gateway · HTTP {status}")
        return f"GNB Assist couldn't get an answer (HTTP {status}). Please try again."
