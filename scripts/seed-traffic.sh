#!/usr/bin/env bash
# Fill Konnect Analytics with realistic traffic across use cases before the panel (~3 min).
# Retail goes through gnb-assistant so it doesn't touch the retail copilot's Act 3 budget.
. "$(dirname "$0")/lib/common.sh"
SYS="You are GNB's assistant. Reply in at most three sentences."
call() { ask "$1" "$2" "$3" "$SYS" "$4" > /dev/null; printf '%s %-22s %-13s %s\n' "$LAST_CODE" "$1" "$3" "$(grep -i '^x-cache-status:' run/last.h | tr -d '\r' | cut -d' ' -f2)"; }
retail=("What documents do I need to open a savings account?" "How do I reset my mobile banking PIN?" "What are your branch hours on Friday?" "How do I report a lost card?" "Can I increase my debit card limit?" "How do I update my address?")
aml=("Summarise this alert: 6 international transfers just under AED 50,000 to new beneficiaries in 2 weeks." "Assess this pattern: rapid in-and-out movement of AED 300,000 through a dormant account." "Summarise risk: cash deposits at 4 branches on the same day, each AED 9,000." "Review this case: a trading company receiving round-sum payments from 12 unrelated individuals.")
credit=("Summarise the credit risk of a mid-size logistics company with rising receivables and flat revenue." "Draft the risk paragraph of a credit memo for a restaurant group expanding to 3 new sites." "Assess debt service coverage for a property developer with 70% pre-sales.")
know=("What is our policy on dormant accounts?" "Which documents prove UAE residency for account opening?" "What documents prove UAE residency for opening an account?" "How long do we retain KYC records?" "How long are KYC records retained?")
for round in 1 2; do
  for q in "${retail[@]}"; do call "Aisha · retail" KEY_AISHA gnb-assistant "$q"; done
  for q in "${aml[@]}"; do call "Layla · AML" KEY_LAYLA gnb-copilot "$q"; done
  for q in "${credit[@]}"; do call "Credit memo app" KEY_CREDIT_MEMO gnb-copilot "$q"; done
  for q in "${know[@]}"; do call "Knowledge assistant" KEY_KNOWLEDGE gnb-copilot "$q"; done
done
echo "✓ seeded; Analytics shows it within ~15 s"
