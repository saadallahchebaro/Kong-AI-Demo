# What an app team changes to go through Kong: the base URL and their use case's key. Same OpenAI SDK.
# Run: set -a; . ./.env.demo-keys; set +a; .venv/bin/python app/copilot_client.py
import os
from openai import OpenAI

client = OpenAI(base_url="http://localhost:8000/v1",                  # Kong, not the model
                api_key="unused",                                     # Kong reads the key from the apikey header
                default_headers={"apikey": os.environ["KEY_AISHA"]})  # the retail copilot's key
reply = client.chat.completions.create(model="gnb-assistant",
                                       messages=[{"role": "user", "content": "In one sentence: what documents do I need to open a savings account?"}])
print(reply.model, "·", reply.choices[0].message.content)
