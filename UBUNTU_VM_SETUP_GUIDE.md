# Complete Guide: Running SkillSpector & OpenClaw inside an Ubuntu 24.04 ARM VM on Apple Silicon (M4)

This guide provides step-by-step instructions to set up an isolated **Ubuntu 24.04 ARM Virtual Machine** on your MacBook Air M4 to safely execute untrusted AI agent skills, run OpenClaw, and perform security analysis.

---

## 1. Download & Install Hypervisor on macOS

Choose one of the following hypervisors:

* **Option A: UTM (Recommended & Free)**
  * Download from: [https://mac.getutm.app](https://mac.getutm.app)
  * Free, open-source, and optimized for Apple Silicon (ARM64).

* **Option B: VMware Fusion Pro (Free for Personal Use)**
  * Download from: [Broadcom / VMware Fusion Portal](https://www.vmware.com/products/fusion.html)

---

## 2. Download Ubuntu 24.04 LTS ARM64 ISO

Download the **ARM64** version of Ubuntu for Apple Silicon:
* **Ubuntu 24.04 LTS Desktop ARM64**: [https://cdimage.ubuntu.com/daily-live/current/](https://cdimage.ubuntu.com/daily-live/current/) or official Ubuntu ARM server ISO.

---

## 3. Create the Virtual Machine in UTM

1. Open **UTM** and click **Create a New Virtual Machine**.
2. Select **Virtualize** (Native ARM64 speed).
3. Select **Linux** and browse to your downloaded `ubuntu-24.04-arm64.iso`.
4. Configure Hardware Settings:
   * **RAM**: 8 GB (8192 MB)
   * **CPU Cores**: 4 Cores
   * **Storage**: 40 GB
5. Click **Save** and start the VM to complete the standard Ubuntu installation wizard.

---

## 4. One-Click Provisioning Inside Ubuntu VM

Once your Ubuntu VM boots up and you log in:

1. Open the Terminal inside Ubuntu.
2. Clone or copy your `prompt-engineering` project folder into the VM:
   ```bash
   git clone <your-github-repo-url> ~/prompt-engineering
   # OR transfer folder via shared network folder / scp
   cd ~/prompt-engineering
   ```
3. Run the automated provisioning script:
   ```bash
   ./setup_ubuntu_vm.sh
   ```
4. Reload your environment:
   ```bash
   source ~/.bashrc
   ```

---

## 5. Verify Installation inside Ubuntu VM

Run the following verification commands inside the VM terminal:

```bash
# 1. Check OpenClaw
openclaw --version
openclaw status

# 2. Test SkillSpector Security Scan
skillspector scan ~/.openclaw/workspace/skills/hello-world

# 3. Test Malicious Skill Block
skillspector scan ~/.openclaw/workspace/skills/unsafe-test-skill

# 4. Ingest Skill into Dataset Pipeline
skillspector collect ~/.openclaw/workspace/skills/unsafe-test-skill
```

---

## 6. Why This Keeps Your Mac 100% Safe

* **Isolated Sandbox**: Destructive commands (`rm -rf`, file encryption attempts) run by untrusted test skills are constrained inside the VM filesystem.
* **Native Linux Paths**: Uses native `/home/user/...` Linux paths without path translation edits.
* **Network Inspection**: You can monitor or restrict network calls safely within Ubuntu.
