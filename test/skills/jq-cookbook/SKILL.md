---
name: jq:cookbook
description: Use WHEN you need to slice, reshape, filter, or aggregate JSON on the command line with jq — and want the right idiom instead of guessing at jq's quirky syntax.
---

> Test fixture for sc:search search system.

jq is a small functional language inside a CLI, and its docs assume you already know functional programming. This skill is the cookbook: ten recipes that cover ~90% of real-world JSON munging, ready to copy-paste-adapt.

Recipes:

```
# 1. Pretty-print
jq . file.json

# 2. Extract one field across an array of objects
jq '.users[].email' users.json

# 3. Filter
jq '.users[] | select(.role == "admin")' users.json

# 4. Reshape (rename + project)
jq '.users | map({id: .userId, name: .displayName})' users.json

# 5. Aggregate count by group
jq 'group_by(.country) | map({country: .[0].country, n: length})' users.json

# 6. Flatten nested arrays
jq '[.events[] | .items[]]' nested.json

# 7. Join two files on a key
jq -s '.[0] as $a | .[1] | map(. + ($a[] | select(.id == .id)))' a.json b.json

# 8. Sort by a numeric field, descending
jq 'sort_by(-.score)' rows.json

# 9. CSV out
jq -r '.[] | [.id, .email, .signup] | @csv' rows.json

# 10. Update in place (preserve key order)
jq '.config.timeout = 30' settings.json | sponge settings.json
```

`-r` strips JSON quoting on string outputs; `-s` ("slurp") reads multiple inputs as one array; `-c` ("compact") emits one JSON value per line — great for piping to `parallel`. For mutation-in-place, `sponge` (from moreutils) is safer than shell redirection because the file would otherwise be truncated before jq reads it.

Do NOT use jq for streaming over >GB JSON arrays (use `jq --stream` mode, or switch to `gojq` for speed); also not the right tool for JSON schema validation. Related: `json:pretty` for formatting, `yq` for YAML equivalents, `parquet:inspect` for non-JSON columnar.
