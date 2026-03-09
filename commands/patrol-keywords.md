---
name: patrol-keywords
description: Manage custom trigger keywords — list, add, remove, or reset
---

# Patrol Keywords

Manage the keywords that trigger bug-fix mode. Custom keywords extend the built-in defaults.

## Instructions

1. Parse the user's arguments (text after `/patrol-keywords`):
   - No arguments → list all keywords
   - `add "word1" "word2" ...` → add to custom_keywords
   - `remove "word"` → remove from custom_keywords
   - `reset` → clear all custom keywords

2. Read current config:
```bash
cat ~/.patrol/config.json 2>/dev/null || echo '{}'
```

3. For **list**: show defaults and custom separately:

**Default keywords** (built-in, always active):
fix, bug, broken, error, crash, doesn't work, not working, Fehler, kaputt, Absturz, funktioniert nicht, erreur, plantage, cassé, ne marche pas

**Custom keywords** (from config):
[list from custom_keywords array, or "none" if empty]

4. For **add**: read current `custom_keywords` array, append new words, write back:
```bash
# Read current
CURRENT=$(jq -r '.custom_keywords // []' ~/.patrol/config.json 2>/dev/null || echo '[]')
# Add new words (replace WORDS with actual words)
NEW=$(echo "$CURRENT" | jq --arg w "WORD" '. + [$w] | unique')
# Write back
jq --argjson kw "$NEW" '.custom_keywords = $kw' ~/.patrol/config.json > /tmp/patrol-config-tmp.json && mv /tmp/patrol-config-tmp.json ~/.patrol/config.json
```

5. For **remove**: filter out the word:
```bash
jq --arg w "WORD" '.custom_keywords = (.custom_keywords // [] | map(select(. != $w)))' ~/.patrol/config.json > /tmp/patrol-config-tmp.json && mv /tmp/patrol-config-tmp.json ~/.patrol/config.json
```

6. For **reset**: remove custom_keywords key:
```bash
jq 'del(.custom_keywords)' ~/.patrol/config.json > /tmp/patrol-config-tmp.json && mv /tmp/patrol-config-tmp.json ~/.patrol/config.json
```

7. Show confirmation with the updated keyword list.
