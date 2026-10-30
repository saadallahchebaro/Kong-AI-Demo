#!/usr/bin/env python3
"""Generate .personas.env: GNB Assist's test credentials (admin bootstrap, the five personas, the session secret).
Throwaway values, git-ignored, never printed. Only for a fresh install; setup.py reads them."""
import pathlib, secrets
p = pathlib.Path(__file__).with_name(".personas.env")
if p.exists():
    raise SystemExit(".personas.env exists; delete it (and the gnb-assist volume) for a fresh install")
pw = lambda: "Gnb-" + secrets.token_urlsafe(12)
lines = ["# GNB Assist test credentials (generated, throwaway, git-ignored). Used by up.sh / setup.py; never shown on screen.",
         f"WEBUI_SECRET_KEY={secrets.token_hex(32)}", "WEBUI_ADMIN_EMAIL=platform@gnb.test", f"WEBUI_ADMIN_PASSWORD={pw()}"]
lines += [f"PW_{n}={pw()}" for n in ("AISHA", "LAYLA", "OMAR", "NOURA", "KHALID")]
p.write_text("\n".join(lines) + "\n"); print("created", p.name, "(values not shown)")
