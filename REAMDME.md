# hwkey

**hwkey** is a CLI tool and infrastructure workflow designed to manage physical FIDO2/U2F hardware security keys (such as YubiKeys) for remote SSH access. 

It maintains an encrypted, central Git-backed ledger of authorized hardware keys and target remote hosts, allowing you to atomically deploy, rotate, and revoke SSH resident keys across your entire infrastructure.

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

* **Local Encryption:** The central ledger (`ledger.enc.yaml`) is encrypted at rest using [SOPS](https://github.com/getsops/sops) and [Age](https://github.com/FiloSottile/age). 
* **Git Synchronization:** Every update to the ledger is automatically committed and pushed to your central Git repository.
* **Atomic Host Management:** Remote server updates use Paramiko SFTP to update `~/.ssh/authorized_keys` atomically via temporary files, preventing file corruption or lockout.

---

## Features

* **Zero-Touch Setup:** One-liner installer handles Python virtualenvs, binary path configuration, and native system dependencies (`pcscd`, `golang`, `age`, `sops`).
* **FIDO2 Hardware Key Auto-Discovery:** Direct HID bus scanning to detect connected YubiKeys and discover FIDO2 resident keys (`ssh-ed25519-sk`).
* **Centralized Key Deployment:** Register target hosts once; all enrolled hardware keys are automatically deployed to `authorized_keys`.
* **Instant Global Revocation:** Revoke lost or compromised hardware keys across all deployed servers with a single command.
* **Key Rotation:** Replace aging keys on all target hosts in a single operation.

---

## Prerequisites & Installation

### Operating System
Tested on **Fedora Linux** (RHEL/CentOS compatible).

### One-Step Automated Installation

Clone this repository and run the included `install.sh` script:

```bash
git clone [https://github.com/your-user/hwkey.git](https://github.com/your-user/hwkey.git)
cd hwkey
chmod +x install.sh
./install.sh
```

What `install.sh` does:
1. Installs system crypto dependencies (`python3-virtualenv`, `yubikey-manager`, `pcsc-lite`, `golang`, `age`) via DNF.
2. Enables and starts the Linux Smartcard service (`pcscd`).
3. Compiles `sops` directly from upstream source via Go.
4. Sets up an isolated Python virtual environment (`.venv`) and installs `typer`, `paramiko`, `pyyaml`, `rich`, and `fido2`.
5. Symlinks `hwkey` into `~/.local/bin/hwkey` and updates your shell `$PATH`.

After installation, reload your shell profile:

```bash
source ~/.bashrc
```

---

## Quick Start Guide

### 1. Initialize the Repository

Create an empty Git repository (e.g., on GitHub) to host your encrypted ledger, then run `hwkey init`:

```bash
hwkey init -g git@github.com:your-user/hwkey-repo.git
```

* This automatically provisions a local Age key (`~/.config/sops/age/keys.txt`).
* Writes the correct `.sops.yaml` creation rules matching `ledger.enc.yaml`.
* Sets up the local Git repository at `~/.hwkey/repo/`.

### 2. Discover & Enroll Attached YubiKeys

Plug in your YubiKey and run:

```bash
hwkey scan
```

* **If resident keys already exist on the device:** `hwkey` reads them and prompts you to enroll them into the ledger.
* **If no resident keys exist:** `hwkey` prompts to create a new `ed25519-sk` resident key directly on the hardware token.

### 3. Register & Deploy Keys to a Server

Add a target SSH host to the ledger:

```bash
hwkey register server1.example.com --user root --alias web-prod
```

`hwkey` connects via SFTP and atomically appends all enrolled hardware keys to the remote user's `~/.ssh/authorized_keys` file.

---

## CLI Reference

### Environment & Key Setup

| Command | Description |
| :--- | :--- |
| `hwkey init [-g <git_url>]` | Provisions local Age keys, writes `.sops.yaml`, initializes Git repo, and attaches optional remote URL. |
| `hwkey set-remote <git_url>` | Updates or sets the origin remote Git repository URL. |

### Hardware Key Operations

| Command | Description |
| :--- | :--- |
| `hwkey scan` | Scans USB bus for connected FIDO2 YubiKeys and enrolls discovered or generated resident keys. |
| `hwkey enroll <key_id> <pubkey>` | Manually adds an SSH public key string to the ledger. |
| `hwkey show-keys` | Displays a formatted table of all enrolled keys and the hosts they are deployed to. |

### Host & Key Management

| Command | Description |
| :--- | :--- |
| `hwkey register <host>` | Registers a remote server (`--user`, `--port`, `--alias`) and deploys all ledger keys to it. |
| `hwkey revoke <key_id>` | Connects to all servers holding `<key_id>`, removes it from `authorized_keys`, and updates the ledger. |
| `hwkey rotate <old_key_id> <new_key_id> <new_pubkey>` | Swaps an old key for a new key across all servers holding the old key. |
| `hwkey remove <key_id>` | Executes a full revocation of `<key_id>` from all hosts and deletes it from the ledger. |

---

## Key Recovery & Security Model

* **Hardware Authentication (`ssh-ed25519-sk`):** Private SSH keys never leave the YubiKey secure element. Touch presence (and optional PIN) is enforced for every remote connection.
* **Ledger Encryption (SOPS + Age):** The Git repository holds encrypted data (`ledger.enc.yaml`). Even if your Git repository is public, server hostnames, username metadata, and public key mappings are unreadable without your local Age private key (`~/.config/sops/age/keys.txt`).
* **Multi-Recipient Backup:** When running `hwkey init`, you can specify additional Age public key recipients (e.g., a secondary workstation or offline paper backup). This ensures that if a workstation hard drive fails, your encrypted Git ledger remains recoverable.

---

## File Structure

* `~/.hwkey/repo/` — Local Git working directory.
* `~/.hwkey/repo/.sops.yaml` — SOPS recipient configuration and file-matching regex.
* `~/.hwkey/repo/ledger.enc.yaml` — Decrypted in-memory, stored encrypted on disk and in Git.
* `~/.config/sops/age/keys.txt` — Local private Age decryption key.