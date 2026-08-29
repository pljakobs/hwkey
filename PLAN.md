# Security Hardening Plan: Git Transport & Commit Signatures via Hardware Keys

## Objective
Eliminate reliance on host-bound SSH keys by migrating Git repository authentication and commit signing to hardware-backed FIDO2/OpenPGP tokens (YubiKey). This prevents automated ledger tampering, exfiltration of key material, and unauthenticated git operations.

---

## Phase 1: Key Generation & Migration

### Step 1.1: Generate FIDO2 Resident SSH Key
Generate a hardware-backed SSH key for Git transport. Using a resident key allows recovery of public key stubs across systems if needed.

```bash
# Generate FIDO2 resident key with PIN verification enforced
ssh-keygen -t ed25519-sk -O resident -O verify-required -C "yubikey-git-transport-$(date +%Y%m%d)" -f ~/.ssh/id_ed25519_sk
```

### Step 1.2: Register Hardware Key with Git Provider
1. Retrieve the public key stub:
   ```bash
   cat ~/.ssh/id_ed25519_sk.pub
   ```
2. Add the public key to your Git remote account (GitHub / GitLab / Gitea) under **SSH and GPG Keys**.
3. Verify connection:
   ```bash
   ssh -T git@github.com
   ```
   *(Ensure system prompts for YubiKey PIN and touch).*

### Step 1.3: Deprecate Host-Bound Keys
1. Remove old host-stored public keys from Git provider settings.
2. Archive and remove local host-bound SSH private key files:
   ```bash
   rm ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
   ```

---

## Phase 2: Git Commit Signing Configuration

### Step 2.1: Configure Git to Use SSH Signature Format
Modern Git supports signing commits directly using SSH keys, eliminating the need for separate GPG setup.

```bash
# Set SSH as the signing format globally
git config --global gpg.format ssh

# Specify the YubiKey SSH key for signing
git config --global user.signingkey ~/.ssh/id_ed25519_sk.pub

# Enforce commit signing by default
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```

### Step 2.2: Register Allowed Signers
Configure local verification for repository commits:

```bash
# Set allowed signers file
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers

# Add identity to allowed signers
echo "$(git config user.email) $(cat ~/.ssh/id_ed25519_sk.pub)" >> ~/.ssh/allowed_signers
```

### Step 2.3: Register Signing Key on Git Provider
1. Upload `~/.ssh/id_ed25519_sk.pub` to the Git provider specifically as a **Signing Key** (if separate from Authentication Keys).
2. Confirm commits render as "Verified" on the web interface after pushing.

---

## Phase 3: Remote Repository & Branch Protection Rules

### Step 3.1: Restrict Direct Pushes
In the repository host settings (GitHub/GitLab/Gitea):
- Enable branch protection on default branches (`main`/`master`).
- Block force pushes (`--force` and `--force-with-lease`).
- Restrict branch deletion.

### Step 3.2: Require Signed Commits
- Enable **Require Signed Commits** under repository security settings.
- Rejects any push containing unsigned commits, neutralizing potential automated pushes from compromised endpoints lacking physical key access.

---

## Verification & Audit Checklist

- [ ] `ssh -T git@<provider>` requires both YubiKey PIN and physical touch.
- [ ] Attempting to commit without YubiKey attached triggers a signature failure error.
- [ ] `git log --show-signature` shows valid SSH signatures for local commits.
- [ ] Commits pushed to remote display the `Verified` status badge.
- [ ] Old host-bound SSH keys are completely revoked from remote account access lists.

