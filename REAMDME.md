# hwkey

**hwkey** is a CLI tool and infrastructure workflow designed to manage physical FIDO2/U2F hardware security keys (such as YubiKeys) for remote SSH access[cite: 5]. 

It maintains an encrypted, central Git-backed ledger of authorized hardware keys and target remote hosts, allowing you to atomically deploy, rotate, and revoke SSH resident keys across your entire infrastructure[cite: 5]. It also provides an interactive SSH wrapper to connect seamlessly using hardware key stubs on demand[cite: 4].

---

## Architecture Overview

```
                      +-----------------------------+
                      |    Local Workstation        |
                      |                             |
                      |   ~/.hwkey/repo/            |
                      |   ├── .sops.yaml            |
  +---------------+   |   └── ledger.enc.yaml <----+----+
  |  YubiKey USB  |   |             │              |    | (Decrypted in-memory)
  | (FIDO2 / SSH) |   +─────────────┼──────────────+    |
  +───────┬───────+                 │                   │
          │                         │ (SOPS Encrypted)  │ (SOPS Decrypted)
          ▼                         ▼                   │
  +---------------+       +───────────────────+         │
  |  Paramiko     |       |   Remote Git      |         │
  |  SFTP Engine  |       |   (GitHub / Git)  |         │
  +───────┬───────+       +───────────────────+         │
          │                                             │
          ▼                                             │
+───────────────────+                                   │
|  Target Server    |                                   │
|  (~/.ssh/         |                                   │
|   authorized_keys)│───────────────────────────────────+
+───────────────────+
```

* **Local Encryption:** The central ledger (`ledger.enc.yaml`) is encrypted at rest using [SOPS](https://github.com/getsops/sops) and [Age](https://github.com/FiloSottile/age)[cite: 5]. 
* **Git Synchronization:** Every update to the ledger or SOPS configuration is automatically committed and pushed to your central Git repository[cite: 5].
* **Atomic Host Management:** Remote server updates use Paramiko SFTP to update `~/.ssh/authorized_keys` atomically via temporary files, preventing file corruption or lockout[cite: 5].

---

## Features

* **Zero-Touch Setup:** One-liner installer handles Python virtualenvs via `requirements.txt`, binary path configuration, and native system dependencies (`pcscd`, `golang`, `age`, `sops`)[cite: 5].
* **FIDO2 Hardware Key Auto-Discovery:** Direct HID bus scanning to detect connected YubiKeys and discover FIDO2 resident keys (`ssh-ed25519-sk`)[cite: 5].
* **Seamless SSH Launcher:** `hwkey ssh` extracts temporary resident stubs without passphrase prompts and launches interactive SSH sessions[cite: 4].
* **Multi-Workstation SOPS Management:** Easily add, list, revoke, or rotate Age recipient keys for multi-workstation access[cite: 5].
* **Centralized Key Deployment:** Register target hosts once; all enrolled hardware keys are automatically deployed to `authorized_keys`[cite: 5].
* **Instant Global Revocation:** Revoke lost hardware keys or workstation decryption access with instant Git and server updates[cite: 5].

---

## Prerequisites & Installation

### Operating System
Tested on **Fedora Linux** (RHEL/CentOS compatible)[cite: 5].

### Automated Installation

Clone this repository and run the included `install.sh` script[cite: 5]:

```bash
git clone [https://github.com/your-user/hwkey.git](https://github.com/your-user/hwkey.git)
cd hwkey
chmod +x install.sh
./install.sh
```

What `install.sh` does[cite: 5]:
1. Installs system crypto dependencies (`python3-virtualenv`, `yubikey-manager`, `pcsc-lite`, `golang`, `age`) via DNF[cite: 5].
2. Enables and starts the Linux Smartcard service (`pcscd`)[cite: 5].
3. Compiles `sops` directly from upstream source via Go[cite: 5].
4. Sets up an isolated Python virtual environment (`.venv`) and installs dependencies from `requirements.txt` (or fallback packages)[cite: 5].
5. Symlinks `hwkey` into `~/.local/bin/hwkey` and updates your shell `$PATH`[cite: 5].

After installation, reload your shell profile[cite: 5]:

```bash
source ~/.bashrc
```

---

## Quick Start Guide

### 1. Initialize the Repository

Create an empty Git repository (e.g., on GitHub) to host your encrypted ledger, then run `hwkey init`[cite: 5]:

```bash
hwkey init -g git@github.com:your-user/hwkey-repo.git
```

* This automatically provisions a local Age key (`~/.config/sops/age/keys.txt`)[cite: 5].
* Writes the correct `.sops.yaml` creation rules matching `ledger.enc.yaml`[cite: 5].
* Sets up the local Git repository at `~/.hwkey/repo/`[cite: 5].

### 2. Discover & Enroll Attached YubiKeys

Plug in your YubiKey and run[cite: 5]:

```bash
hwkey scan
```

### 3. Register & Deploy Keys to a Server

Add a target SSH host to the ledger[cite: 5]:

```bash
hwkey register server1.example.com --user root --alias web-prod
```

### 4. Connect via `hwkey ssh`

Launch an interactive SSH session using your YubiKey[cite: 4]:

```bash
hwkey ssh web-prod
```

---

## CLI Reference

### Environment & Remote Setup

| Command | Description |
| :--- | :--- |
| `hwkey init [-g <git_url>]` | Provisions local Age keys, writes `.sops.yaml`, initializes Git repo, and attaches optional remote URL[cite: 5]. |
| `hwkey set-remote <git_url>` | Updates or sets the origin remote Git repository URL[cite: 5]. |

### SOPS / Workstation Decryption Key Management

| Command | Description |
| :--- | :--- |
| `hwkey list-sops-keys` | Lists all Age recipient public keys configured in `.sops.yaml` (active local key marked with `*`). |
| `hwkey add-sops-key <age_pubkey>` | Adds a new Age public key recipient to `.sops.yaml`, re-encrypts ledger, and syncs to Git[cite: 5]. |
| `hwkey revoke-sops-key <age_pubkey>` | Revokes an Age public key recipient from `.sops.yaml` (protected against self-revocation). |
| `hwkey rotate-sops-key` | Generates a new local Age key, activates it, re-encrypts the ledger, and revokes the old local key. |

### Hardware Key Operations & SSH Access

| Command | Description |
| :--- | :--- |
| `hwkey scan` | Scans USB bus for connected FIDO2 YubiKeys and enrolls discovered or generated resident keys[cite: 5]. |
| `hwkey enroll <key_id> <pubkey>` | Manually adds an SSH public key string to the ledger[cite: 5]. |
| `hwkey show-keys` | Displays a formatted table of all enrolled keys and the hosts they are deployed to[cite: 5]. |
| `hwkey ssh <target> [-k <key>]` | Interactive SSH wrapper that extracts temporary key stubs and logs into `<target>`[cite: 4]. |

### Host & Key Infrastructure Management

| Command | Description |
| :--- | :--- |
| `hwkey register <host>` | Registers a remote server (`--user`, `--port`, `--alias`) and deploys all ledger keys to it[cite: 5]. |
| `hwkey revoke <key_id>` | Connects to all servers holding `<key_id>`, removes it from `authorized_keys`, and updates ledger[cite: 5]. |
| `hwkey rotate <old_id> <new_id> <pubkey>` | Swaps an old key for a new key across all servers holding the old key[cite: 5]. |
| `hwkey remove <key_id>` | Executes a full revocation of `<key_id>` from all hosts and deletes it from the ledger[cite: 5]. |

---

## Key Recovery & Security Model

* **Hardware Authentication (`ssh-ed25519-sk`):** Private SSH keys never leave the YubiKey secure element[cite: 5]. Touch presence and optional PIN are enforced for every connection[cite: 5].
* **Ledger Encryption (SOPS + Age):** The Git repository holds encrypted data (`ledger.enc.yaml`)[cite: 5]. Server hostnames, username metadata, and public key mappings are unreadable without an authorized Age private key[cite: 5].
* **Workstation Authorization:** Multi-workstation access is managed safely via `hwkey add-sops-key` and `hwkey revoke-sops-key`, allowing seamless onboarding and offboarding without sharing private keys[cite: 5].

---

## File Structure

* `~/.hwkey/repo/` — Local Git working directory[cite: 5].
* `~/.hwkey/repo/.sops.yaml` — SOPS recipient configuration and file-matching regex[cite: 5].
* `~/.hwkey/repo/ledger.enc.yaml` — Decrypted in-memory, stored encrypted on disk and in Git[cite: 5].
* `~/.config/sops/age/keys.txt` — Active local private Age decryption key[cite: 5].