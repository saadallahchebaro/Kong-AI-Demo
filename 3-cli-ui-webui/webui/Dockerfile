# GNB Assist: Open WebUI v0.11.4 (pinned), branded for the GNB demo.
# Licence basis: the v0.11.4 LICENSE allows altering the Open WebUI branding when the number of end users does not exceed
# fifty in any rolling thirty-day period (clause 4(i)). This demo has the presenter and six test personas.
FROM ghcr.io/open-webui/open-webui:v0.11.4@sha256:9591b13f13843c7721c2b8eaf7382846c81b3ffe126526d1888d1fed50c6a33f

# the app name without the " (Open WebUI)" suffix
RUN python3 - <<'PY'
import pathlib
p = pathlib.Path("/app/backend/open_webui/env.py"); s = p.read_text()
old = "    WEBUI_NAME += ' (Open WebUI)'"
assert old in s, "env.py changed: re-check the branding override"
p.write_text(s.replace(old, "    pass  # GNB demo: LICENSE 4(i), <= 50 end users"))
PY

# the GNB mark everywhere Open WebUI serves its own (same file names and sizes), and GNB styling
COPY brand/static/ /app/backend/open_webui/static/
COPY brand/static/ /app/build/static/
COPY brand/static/favicon.png /app/build/favicon.png
COPY brand/custom.css /app/backend/open_webui/static/custom.css
COPY brand/custom.css /app/build/static/custom.css
