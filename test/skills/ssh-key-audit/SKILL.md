---
name: ssh:key-audit
description: Use WHEN you need to audit SSH keys — find weak keys (DSA, short RSA), find unrotated keys, enumerate which keys can reach which hosts, before a compliance review.
---

> Test fixture for sc:search search system.

SSH key debt is the silent cousin of IAM debt. Every developer has at least one key on every host; departing employees often leave keys in `authorized_keys` files months after they've left. This skill audits local and known-host key state.

Local audit:

```
ssh-keygen -lf ~/.ssh/id_ed25519                          # fingerprint + key type + bits
for f in ~/.ssh/id_*.pub; do ssh-keygen -lf "$f"; done    # all local public keys
ssh-keygen -E sha256 -lf ~/.ssh/id_ed25519                 # specific hash algo
```

Server audit (per host, ideally via Ansible/SSM):

```
# List keys allowed to log in as a given user
awk '{print $1, $2, $3}' /home/deploy/.ssh/authorized_keys | while read t k c; do
  echo "$c -> $(echo $k | base64 -d 2>/dev/null | sha256sum | head -c 12)"
done
```

The skill's `ssh-key-audit fleet --hosts-file hosts.txt --user deploy` command fans out across the inventory, collects every `authorized_keys` file, dedupes by fingerprint, and emits a CSV showing (fingerprint, comment, hosts-it-can-reach, age-of-key). Findings flagged: DSA keys (deprecated), RSA <3072 bits (weak), keys with no comment (un-attributable), keys with `comment` matching ex-employees.

Do NOT confuse this with TLS cert audit (different protocol, different store). For host-key changes after re-provisioning use `ssh-keygen -R hostname` plus `ssh -o StrictHostKeyChecking=accept-new`. Related: `tls:cert-inspect`, `aws:iam-audit`, `secret:rotate-cli`.
