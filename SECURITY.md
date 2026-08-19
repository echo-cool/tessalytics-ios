# Security policy

## Supported versions

Security updates are provided for the latest version on the default branch while Tessalytics is pre-1.0.

## Report a vulnerability

Do not open a public issue for a vulnerability or include real tokens, VINs, coordinates, addresses, or server URLs in a report. Use GitHub’s private vulnerability reporting feature for this repository. If it is unavailable, open a minimal public issue asking a maintainer to enable a private reporting channel without disclosing technical details.

Include the affected version, reproducible impact, and a redacted proof of concept. Allow maintainers reasonable time to investigate before public disclosure.

## Deployment responsibilities

Treat a TeslaMateApi credential as a sensitive location-tracking credential. Protect every read route with a VPN or authenticated HTTPS reverse proxy. TeslaMateApi’s built-in `API_TOKEN` does not protect all read-only endpoints. Never expose PostgreSQL, MQTT, Owner API tokens, or an unauthenticated TeslaMateApi instance.

Owner API access and refresh tokens can expose live vehicle state and permit vehicle commands. Tessalytics stores them with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never logs them, and requires device-owner authentication before each command. Do not paste real tokens into issues, logs, test fixtures, or support messages.

Tessalytics never disables TLS validation and does not provide a trust-any-certificate option.
