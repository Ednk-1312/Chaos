# Security Policy

Chaos is a tool that **deliberately manipulates system and application
conditions** — network routing, resource pressure, processes, filesystems. That
makes its security posture unusual, and we take it seriously.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security reports.**

Use GitHub's **Private vulnerability reporting** (Repository → Security →
Report a vulnerability). This is currently the supported reporting mechanism;
no dedicated security email address exists for this project yet.

## What counts as a vulnerability in Chaos

This project's *purpose* is to change system state, so "it changed my network
settings" is not by itself a vulnerability. Report things like:

- A fault or restoration path that escapes its documented scope (e.g. modifies
  settings outside the pf anchor / dummynet pipes it owns)
- Restoration that reports success without verification, or fails silently
- Crash/orphan behavior that leaves persistent system changes behind
- The safety confirmation or emergency-stop path being bypassable
- A privilege-escalation path (Chaos gaining more OS authority than the
  documented on-demand authorization model)
- Secrets, credentials, or personal data in the repository
- Anything that would let a *third party* use Chaos to attack a machine they
  don't control

## What a useful report contains

- Chaos commit or version, macOS version, and Mac model
- The experiment/fault involved and its parameters
- Steps to reproduce, and what happened vs. what the documentation promises
- The restoration state afterwards (Restore Center screenshot or `chaos restore --json` output) — **redact anything you consider sensitive**
- Logs only if they contain no private data

**Do not include secrets, tokens, or personal information in reports.**

## Scope

- In scope: the `ChaosKit` engine, the `Chaos` app, the `chaos` CLI, the
  `chaos-stress` worker, and everything in this repository.
- Out of scope: macOS itself, third-party target applications, and the
  documented, intended effects of running an experiment.

## Supported versions

Only the latest `main` branch receives fixes at this stage (developer preview).

## Responsible disclosure

We will acknowledge reports as fast as practical, keep them private while a fix
is prepared, and credit reporters in the changelog unless they prefer anonymity.
Please give us a reasonable window before any public disclosure.
