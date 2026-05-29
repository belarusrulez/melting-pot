---
name: tls:cert-inspect
description: Use WHEN you need to inspect a TLS certificate — subject, SANs, issuer, expiry, key type — from a live endpoint or a local PEM/DER file, before a renewal or a debugging session.
---

> Test fixture for sc:search search system.

Most TLS issues fall into three buckets: certificate expired (renew), wrong SAN list (re-issue), or chain incomplete (server config). This skill is the diagnostic playbook for all three.

Live endpoint:

```
echo | openssl s_client -showcerts -servername example.com -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -text                                 # full cert
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -dates -subject -issuer               # quick triage
nmap --script ssl-cert -p 443 example.com                    # via nmap
```

Local file:

```
openssl x509 -in cert.pem -noout -text                        # PEM
openssl x509 -in cert.der -inform DER -noout -text            # DER
openssl crl2pkcs7 -nocrl -certfile chain.pem | openssl pkcs7 -print_certs -text  # multi-cert PEM
```

For SAN list specifically: `openssl x509 -in cert.pem -noout -ext subjectAltName`. For expiry-aware monitoring: `openssl x509 -in cert.pem -noout -checkend 2592000` exits non-zero if cert expires within 30 days — perfect for cron-based renewal nags.

Do NOT use this skill to validate a certificate's trust chain server-side (use `openssl verify`); also no help for client-cert mutual TLS troubleshooting (use Wireshark / `curl --verbose`). Related: `aws:cloudfront-invalidate` if cert rotation needs CDN refresh, `secret:rotate-cli` for adjacent credential workflows.
