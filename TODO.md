# hwkey Remediation & Improvement Plan

## 1. Security & Critical Vulnerability Fixes
- [ ] **Enforce Strict Host Key Verification**
  - Remove `paramiko.AutoAddPolicy()` from `update_remote_authorized_keys` and `scan_host_keys`.
  - Replace with explicit host key verification against local `known_hosts` or strict user approval to prevent Man-in-the-Middle (MitM) vectors.
- [ ] **Eliminate Transient Private Key Disk Writes**
  - Refactor `hwkey ssh` execution flow to avoid calling `ssh-keygen -K -N ""` into temporary directories (`/tmp`).
  - Keep resident key handle extraction strictly in-memory or leverage native `ssh-agent` interfaces.
- [ ] **Harden Git Ledger Operations**
  - Add optional GPG/SSH signature verification for ledger commits.
  - Implement checks to ensure remote repository identity before performing automatic git pushes/pulls.

## 2. Concurrency & State Management
- [ ] **Prevent Git Ledger Race Conditions**
  - Replace the imperative `git pull --rebase` / `git push` logic in `load()` and `save()` with explicit transaction locking or conflict detection.
  - Handle binary/encrypted (`ledger.enc.yaml`) merge conflicts gracefully to prevent corrupting the encrypted state.
- [ ] **Atomic Key Rotation & Revocation**
  - Refactor `rotate_key` to require all target hosts to successfully update before modifying or deleting keys from the ledger state (`del ledger["keys"][old_key_id]`).
  - Introduce rollback state handling if an intermediate remote node update fails, preventing state drift on unreachable servers.
- [ ] **Sanitize Path Management**
  - Remove global `ENV_PATH` string prepending (`f"{Path.home()}/go/bin:..."`).
  - Standardize on `shutil.which` or explicit configurable binary paths for external execution dependencies.

## 3. Architecture & Feature Enhancements
- [ ] **Implement Access Control / Group Mappings**
  - Expand the data model beyond an all-or-nothing key distribution strategy.
  - Add tag-based or host-group mapping (e.g., target specific environments like dev, staging, prod) to restrict key deployment per host.
- [ ] **Add Pre-Flight Operations**
  - Implement a `--dry-run` flag across key, host, and sync commands to display planned modifications before executing remote SFTP/SSH writes.
  - Implement backup snapshotting of `ledger.enc.yaml` prior to SOPS re-keying or structural mutations.
- [ ] **Evaluate Paradigm Pivot**
  - Assessment: Consider refactoring the underlying execution engine into an Ansible inventory generator or migrating the architecture toward short-lived OpenSSH Certificates (`TrustedUserCAKeys`).


