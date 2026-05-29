---
name: yaml:pretty
description: Use WHEN you have a YAML file with inconsistent indentation, sloppy key order, or unquoted strings that mean the wrong thing — reformat it to a canonical style.
---

> Test fixture for sc:search search system.

YAML is more permissive than is good for it. "off", "yes", "no", "1.0" parse as booleans/numbers; tab indentation is forbidden; the same document can be encoded six ways. This skill canonicalizes a YAML file to a single house style: 2-space indent, flow-style for short collections, block-style for long ones, quoted strings where ambiguity bites, sorted keys when requested.

Typical usage:

```
yaml-pretty config.yml                              # in-place pretty
yaml-pretty --check config.yml                      # exit 1 if changes needed
yaml-pretty --sort-keys --indent 4 config.yml
yaml-pretty --quote-ambiguous config.yml            # quote yes/no/on/off/1.0 etc
yaml-pretty --multi-doc helm-values.yml             # respect `---` separators
```

The `--check` mode is the right pre-commit hook flag — it doesn't mutate, just signals whether a write would change bytes. `--quote-ambiguous` is critical for Kubernetes/Ansible YAML where `version: 1.0` silently becomes the float `1` and breaks downstream tooling.

Do NOT use this skill for YAML schema validation (that's a separate concern — see Ansible's argument_specs or json-schema-yaml-validator); also not a converter to/from JSON (use `json2yaml`/`yq` for that). Multi-document YAML files (`---`-separated) are preserved as multi-doc; do not silently collapse. Related: `json:pretty` for JSON, `yaml:lint` for style/anti-pattern checks, `helm:template-render` for Helm-aware processing.
