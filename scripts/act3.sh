#!/usr/bin/env bash
# ACT 3 · Govern tokens: right-size routing, semantic cache, token budget, cost per use case.
. "$(dirname "$0")/lib/common.sh"
SYS="You are GNB's assistant. Reply in at most three sentences."
T_START=$(now_ms)
banner "ACT 3 · GOVERN TOKENS" "right-size routing · cache · budgets · cost per use case (lever 3)"

step "Every token has an internal price. A routine question from the retail copilot."
ask "Aisha · retail-copilot" KEY_AISHA gnb-copilot "$SYS" "What time do branches open on Saturday?"

step "An AML case from the AML team. Same endpoint."
ask "Layla · aml-summaries" KEY_LAYLA gnb-copilot "$SYS" "14 cash deposits of AED 9,500 across 3 branches in 5 days. Assess structuring risk and recommend next steps."

step "A customer question. Then the same question in different words. Watch the DC1 pane."
ask "Aisha · retail-copilot" KEY_AISHA gnb-copilot "$SYS" "What documents do I need to open a savings account?"
ask "Aisha · retail-copilot" KEY_AISHA gnb-copilot "$SYS" "Which papers are required to open a savings account?"

step "The retail copilot's budget: 500,000 tokens a day. For the demo, 700 tokens per 10 minutes."
for q in "How do I activate my new debit card?" "How do I order a new chequebook?" "How do I report a lost card?" \
         "Can I change my registered mobile number online?" "What are the fees for an international transfer?" \
         "How do I set up a standing order?" "How long does a cheque take to clear?" "Can I freeze my card temporarily?"; do
  ask "Aisha · retail-copilot" KEY_AISHA gnb-copilot "$SYS" "$q"
  [ "$LAST_CODE" = 429 ] && break
done

step "The CIO's view: tokens and cost per use case (Konnect Analytics). Same data as the dashboard."
show "POST https://${KONGCTL_DEFAULT_KONNECT_REGION:-eu}.api.konghq.com/v2/metrics  {datasource: llm_usage, dimensions: [ai_gateway_consumer_group]}"
analytics 1h
