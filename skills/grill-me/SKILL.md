---
name: grill-me
description: "Interview the user relentlessly about a plan or design until reaching shared understanding. Use when asked to 'grill me', 'interview me', 'ask me questions about this', or before writing a PRD to flesh out vague ideas."
disable-model-invocation: true
---

# Grill Me

Output "Read Grill Me skill." to chat to acknowledge you read this file.

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Handoff

After reaching shared understanding, offer the user three paths:

1. /write-a-prd — capture decisions as a formal PRD
2. /prd-to-issues — break directly into GitHub issues
3. /do-work — start implementing immediately

Let the user choose.

If context fills up during the interview, follow the standard handoff protocol — persist decisions made so far to `working/` and provide the pickup command.
