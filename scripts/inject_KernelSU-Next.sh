#!/usr/bin/env bash
# scripts/inject_KernelSU-Next.sh
# Dynamic SuSFS integration module for KernelSU-Next

echo ">>> Executing Integration Module for KernelSU-Next..."

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> [DYNAMIC] Executing Automated Dynamic Transplant for KernelSU-Next..."
    
    echo ">>> 1. Cloning pristine official KernelSU-Next..."
    git clone "https://github.com/${UPSTREAM_REPO}.git" "${MANAGER_DIR}"
    
    # Prevent setup.sh from performing a redundant clone
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    
    echo ">>> Executing native setup.sh to initialize branch..."
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" "${TARGET_BRANCH}"
    cd ..
    
    cd "${MANAGER_DIR}"

    # CAPTURE THIS IMMEDIATELY BEFORE ANY MERGING!
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -i --grep="ci skip" --grep="skip ci" --grep="clippy" --invert-grep -- manager/ kernel/ userspace/ .github/workflows/ ":!*Cargo.lock" ":!*Cargo.toml")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    echo "  -> Target Tag: $CALCULATED_TAG"

    echo ">>> 2. Fetching Pershoot's live laboratory..."
    git remote add pershoot https://github.com/pershoot/KernelSU-Next.git
    git fetch pershoot dev-susfs

    echo ">>> Configuring dummy Git identity for transplant operations..."
    git config --global user.email "runner@github.actions"
    git config --global user.name "GitHub Actions Canary"

    echo ">>> 3. Squashing and merging SuSFS features onto upstream tree..."
    if ! git merge --squash pershoot/dev-susfs; then
        echo "[-] CRITICAL: Merge conflict detected during squash merge!"
        git --no-pager diff --diff-filter=U
        exit 1
    fi
    
    git commit -m "Merge susfs features from pershoot"
    
    # Lock in variables for the Kbuild Gatekeeper
    UPSTREAM_BRANCH="${TARGET_BRANCH}"
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
    
else
    echo ">>> Safe fallback channel detected. Bypassing dynamic squash merge..."
    echo ">>> [STABLE] Cloning custom pipeline branch: ${KSU_VARIANT_REF}..."
    
      # Safest Git syntax: flags before the URL
    if [ "${KSU_VARIANT_REF}" == "main" ]; then
        git clone -b "dev" "${KSU_VARIANT_REPO_URL}" "${MANAGER_DIR}"
    else
        git clone -b "${KSU_VARIANT_REF}" "${KSU_VARIANT_REPO_URL}" "${MANAGER_DIR}"
    fi

    # Prevent setup.sh from performing a redundant clone
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"

    echo ">>> Executing native setup.sh..."
    cd common
    # FIX 1: Pass the dynamic reference
    bash "${MANAGER_DIR}/kernel/setup.sh" "${KSU_VARIANT_REF}"
    cd ..

    cd "${MANAGER_DIR}"
    
    # FIX 2: Lock the upstream tracking variable to the dynamic branch for the Gatekeeper
    UPSTREAM_BRANCH="${KSU_VARIANT_REF}"
    
    # FIX 3: Fetch official upstream branch and calculate pristine Merge-Base
    echo ">>> Locating official upstream sync point for ${UPSTREAM_REPO}..."
    git fetch --quiet "https://github.com/${UPSTREAM_REPO}.git" "${TARGET_BRANCH}"
    RAW_BASE=$(git merge-base HEAD FETCH_HEAD)

    # FIX 4: Walk backward down the pristine mainline branch
    set +o pipefail
    UPSTREAM_HASH=$(git log -n 1 --first-parent "${RAW_BASE}" --format="%H" -i --grep="ci skip" --grep="skip ci" --grep="clippy" --invert-grep -- manager/ kernel/ userspace/ .github/workflows/ ":!*Cargo.lock" ":!*Cargo.toml")
    set -o pipefail
    
    # Calculate exact versions for the Sandbox Gatekeeper
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v3.2.0")
fi

# Step back out to kernel_workspace
cd .. 

# ---------------------------------------------------------
# KernelSU-Next Kbuild Hotfix (Universal)
# ---------------------------------------------------------
KBUILD_FILE="${MANAGER_DIR}/kernel/Kbuild"
if [ -f "$KBUILD_FILE" ]; then
    if grep -q "KernelSU requires either CONFIG_KPROBES" "$KBUILD_FILE"; then
        echo ">>> [HOTFIX] Bypassing strict Kbuild dependency check for the clean phase..."
        sed -i '/KernelSU requires either CONFIG_KPROBES/d' "$KBUILD_FILE"
    else
        echo ">>> [NOTICE] Strict Kbuild check not found! Upstream likely fixed this. You can remove this hotpatch."
    fi
fi

# ---------------------------------------------------------
# KernelSU-Next SELinux Hide LTO Polyfill
# ---------------------------------------------------------
# SuSFS services.c expects a global fake_state on kernels < 6.6.
# KernelSU-Next removed it. We must polyfill it to prevent ld.lld panics.
SELINUX_HIDE_FILE="${MANAGER_DIR}/kernel/feature/selinux_hide.c"
if [ -f "$SELINUX_HIDE_FILE" ]; then
    echo ">>> [HOTFIX] Polyfilling global fake_state definition to survive LTO..."
    # Strip any existing declarations to prevent accidental redefinitions
    sed -i -E 's/^[ \t]*(static )?struct selinux_state fake_state;//g' "$SELINUX_HIDE_FILE"
    # Unconditionally append the polyfill
    echo -e "\nstruct selinux_state fake_state = {0};" >> "$SELINUX_HIDE_FILE"
fi

echo ">>> KernelSU-Next integration complete."
