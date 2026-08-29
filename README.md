Markdown

# hwkey

**hwkey** is a CLI tool and infrastructure workflow designed to manage physical FIDO2/U2F hardware security keys (such as YubiKeys) for remote SSH access. 

It maintains an encrypted, central Git-backed ledger of authorized hardware keys and target remote hosts, allowing you to atomically deploy, rotate, and revoke SSH resident keys across your entire infrastructure. It also provides an interactive SSH wrapper to connect seamlessly using hardware key stubs on demand.

# rationale

In my view, hwkey solves a problem for for small teams and homelab/infrastructure engineers, though it operates in a middle ground between basic personal tools and enterprise access management.

* **The Core Problem It Solves**: Managing SSH keys on remote servers usually becomes a mess. People either share static, unencrypted `authorized_keys` files, use manual copy-pasting, or rely on plaintext Ansible/Puppet manifests to push keys. `hwkey` solves this by giving you **GitOps-driven, encrypted access control** coupled with mandatory **hardware token enforcement** (FIDO2/YubiKey).
* **Where It Shines**:
  * **Encrypted Metadata**: Unlike storing public keys in open Git repos, encrypting the ledger with SOPS/Age hides hostnames, user accounts, and key mappings from prying eyes.
  * **Hardware Enforcement**: Forcing `ssh-ed25519-sk` means keys cannot be copied off a developer's machine; a physical touch/PIN is strictly required.
  * **Automated Lifecycle**: Doing key rotation or global key revocation across a fleet of remote servers manually via Paramiko/SFTP is tedious; `hwkey` turns that into a single CLI command.
* **The Caveat (Where It Hits Limits)**:
  * **Scale**: Because it relies on direct SFTP/SSH updates to `~/.ssh/authorized_keys`, it works exceptionally well for tens or hundreds of static nodes. At true enterprise scale (thousands of instances), infrastructure teams move away from managing individual `authorized_keys` files altogether and switch to **Ephemeral SSH Certificates** or **OIDC identity proxies**.

---

## Key Recovery & Security Model

> **CRITICAL CAVEAT: MANDATORY BACKUP HARDWARE KEYS**
> 
> Resident SSH keys (`ssh-ed25519-sk`) are stored **exclusively inside the hardware security token's secure element**. By design, private key material cannot be extracted, exported, or backed up.
> 
> **If you lose your hardware token, forget its PIN, or the hardware breaks, the key is permanently unrecoverable.** 
> 
> Using `hwkey` safely mandates enrolling **at least two independent hardware keys** (a primary and a physically separated backup/spare) into the ledger. When a server host is registered via `hwkey host add`, `hwkey` automatically deploys **all active hardware public keys** to the server's `authorized_keys` file, ensuring you retain access if your main YubiKey is lost.

* **Hardware Authentication (`ssh-ed25519-sk`):** Private SSH keys never leave the YubiKey secure element. Touch presence and optional PIN are enforced for every connection.
* **Ledger Encryption (SOPS + Age):** The Git repository holds encrypted data (`ledger.enc.yaml`). Server hostnames, username metadata, and public key mappings are unreadable without an authorized Age private key.
* **Workstation Authorization:** Multi-workstation access is managed safely via `hwkey sops add` and `hwkey sops revoke`, allowing seamless onboarding and offboarding without sharing private keys.

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
* **Git Synchronization:** Every update to the ledger or SOPS configuration is automatically committed and pushed to your central Git repository.
* **Atomic Host Management:** Remote server updates use Paramiko SFTP to update `~/.ssh/authorized_keys` atomically via temporary files, preventing file corruption or lockout.

---

## Features

* **Zero-Touch Setup:** One-liner installer handles Python virtualenvs via `requirements.txt`, binary path configuration, and native system dependencies (`pcscd`, `golang`, `age`, `sops`).
* **FIDO2 Hardware Key Auto-Discovery:** Direct HID bus scanning to detect connected YubiKeys and discover FIDO2 resident keys (`ssh-ed25519-sk`) without interactive passphrase prompts.
* **Sub-Application CLI Layout:** Structured domain sub-commands (`host`, `key`, `sops`, `git`) for intuitive administration.
* **Flexible Host Target Parsing:** Robust user and port resolution via command arguments or `user@hostname` strings.
* **Seamless SSH Launcher:** `hwkey ssh` extracts non-interactive temporary resident stubs and launches interactive SSH sessions directly.
* **Multi-Workstation SOPS Management:** Easily add, list, revoke, or rotate Age recipient keys for multi-workstation access.
* **Centralized Key Deployment:** Register target hosts once; all enrolled hardware keys are automatically deployed to `authorized_keys`.
* **Instant Global Revocation:** Revoke lost hardware keys or workstation decryption access with instant Git and server updates.

---

## Prerequisites & Installation

### Operating System
Tested on **Fedora Linux** (RHEL/CentOS compatible).

### Automated Installation

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
4. Sets up an isolated Python virtual environment (`.venv`) and installs dependencies from `requirements.txt` (or fallback packages).
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
hwkey key scan
```

### 3. Register & Deploy Keys to a Server

Add a target SSH host to the ledger:

```bash
hwkey host add server1.example.com --user root --alias web-prod
```

### 4. Connect via `hwkey ssh`

Launch an interactive SSH session using your YubiKey:

```bash
hwkey ssh web-prod
```

---

## CLI Reference

### Environment & Root Operations

| Command | Description |
| :--- | :--- |
| `hwkey init [-g <git_url>]` | Provisions local Age keys, writes `.sops.yaml`, initializes Git repo, and attaches optional remote URL. |
| `hwkey ssh <target> [-k <key>] [-u <user>] [-p <port>]` | Interactive SSH wrapper that extracts temporary key stubs and logs into `<target>`. |

### Host Domain (`hwkey host`)

| Command | Description |
| :--- | :--- |
| `hwkey host add <hostname> [-a <alias>] [-u <user>] [-p <port>]` | Registers a target server host entry and deploys all active ledger keys to it. |
| `hwkey host list` | Lists all registered target hosts in the encrypted ledger. |
| `hwkey host remove <alias_or_host> [-u <user>]` | Removes a target host entry from the encrypted ledger. |

### Hardware Key Domain (`hwkey key`)

| Command | Description |
| :--- | :--- |
| `hwkey key scan` | Scans USB bus for FIDO2 YubiKeys and syncs existing resident keys into the ledger without passphrase prompts. |
| `hwkey key enroll [-i <id>] [-a <app>]` | Generates a brand-new resident SSH key (`ed25519-sk`) on the YubiKey and records it in the ledger. |
| `hwkey key stub [-o <out_dir>]` | Extracts resident key handles into local persistent SSH stub files (`~/.ssh/id_*_rk`). |
| `hwkey key add <key_id> <pubkey>` | Manually adds an SSH public key string to the ledger. |
| `hwkey key list` | Displays a formatted table of all enrolled keys and the hosts they are deployed to. |
| `hwkey key rotate <old_id> <new_id> <new_pubkey>` | Swaps an old key for a new key across all hosts holding the old key. |
| `hwkey key revoke <key_id>` | Connects to all servers holding `<key_id>`, removes it from `authorized_keys`, and updates ledger. |

### SOPS & Decryption Domain (`hwkey sops`)

| Command | Description |
| :--- | :--- |
| `hwkey sops list` | Lists all Age recipient public keys configured in `.sops.yaml` (active local key marked with `*`). |
| `hwkey sops add <age_pubkey>` | Adds a new Age public key recipient to `.sops.yaml`, re-encrypts ledger, and syncs to Git. |
| `hwkey sops revoke <age_pubkey>` | Revokes an Age public key recipient from `.sops.yaml` (protected against self-revocation). |
| `hwkey sops rotate` | Generates a new local Age key, activates it, re-encrypts ledger, and revokes old key. |

### Git Remote Domain (`hwkey git`)

| Command | Description |
| :--- | :--- |
| `hwkey git set-remote <git_url>` | Configures or updates the origin remote Git repository URL. |
| `hwkey git show-remotes` | Displays registered Git remotes configured for the ledger. |

---

## Key Recovery & Security Model

* **Hardware Authentication (`ssh-ed25519-sk`):** Private SSH keys never leave the YubiKey secure element. Touch presence and optional PIN are enforced for every connection.
* **Ledger Encryption (SOPS + Age):** The Git repository holds encrypted data (`ledger.enc.yaml`). Server hostnames, username metadata, and public key mappings are unreadable without an authorized Age private key.
* **Workstation Authorization:** Multi-workstation access is managed safely via `hwkey sops add` and `hwkey sops revoke`, allowing seamless onboarding and offboarding without sharing private keys.

---

## File Structure

* `~/.hwkey/repo/` — Local Git working directory.
* `~/.hwkey/repo/.sops.yaml` — SOPS recipient configuration and file-matching regex.
* `~/.hwkey/repo/ledger.enc.yaml` — Decrypted in-memory, stored encrypted on disk and in Git.
* `~/.config/sops/age/keys.txt` — Active local private Age decryption key.

# Existing Alternatives

| Tool / Solution | Approach | Comparison to `hwkey` |
| :--- | :--- | :--- |
| **`ssh-import-id` / GitHub Public Keys** | Pulls public keys directly from GitHub/Launchpad usernames into `authorized_keys`. | Very common, but completely unencrypted, has zero revocation workflows, and doesn't handle remote deployment atomically. |
| **Ansible / Terraform / SaltStack** | Configuration management modules (`authorized_key`). | Solves the automated deployment part, but requires running full playbook runs and setting up external vault pipelines rather than offering an interactive CLI wrapper (`hwkey ssh`). |
| **Teleport** | Identity-aware proxy using short-lived SSH Certificates + SSO/Hardware keys. | The industry standard for enterprise infrastructure. However, Teleport requires heavy server infrastructure, auth proxies, and complex setup. `hwkey` is lightweight, decentralized, and serverless. |
| **Smallstep SSH (`step-ca`)** | Runs an internal Certificate Authority (CA) for short-lived SSH certificates bound to YubiKeys. | Replaces `authorized_keys` completely with signed certificates. It is far more robust for large teams, but requires running an active CA daemon. |
| **SOPS + Chezmoi / Dotfiles** | Syncing SSH key handles via encrypted dotfile managers. | Handles local stub distribution, but does not manage the target host deployment or atomic remote server cleanup upon revocation. |

`hwkey` shoud hit a sweet spot for solo admins, homelabs, or small technical teams who want **SOPS-encrypted GitOps key management with YubiKey enforcement**, without the operational complexity of deploying a full SSH Certificate Authority or Teleport cluster.


