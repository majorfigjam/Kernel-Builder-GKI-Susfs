#!/usr/bin/env bash
# scripts/inject_SukiSU-Ultra.sh

echo ">>> Executing Integration Module for SukiSU-Ultra..."

OFFICIAL_REPO_URL="https://github.com/SukiSU-Ultra/SukiSU-Ultra.git"
CUSTOM_REPO_URL="${KSU_VARIANT_REPO_URL:-https://github.com/shoey63/SukiSU-Ultra.git}"
CUSTOM_REF="${KSU_VARIANT_REF:-stable}"

echo ">>> 1. Cloning custom branch (${CUSTOM_REF}) from ${CUSTOM_REPO_URL}..."
git clone -b "${CUSTOM_REF}" "${CUSTOM_REPO_URL}" "${MANAGER_DIR}"

ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
cd common
# Run setup.sh BEFORE rebasing so it links common/drivers/kernelsu without clobbering git history
bash "${MANAGER_DIR}/kernel/setup.sh" "${CUSTOM_REF}"
cd ..

cd "${MANAGER_DIR}"

echo ">>> 2. Fetching latest official upstream (main + tags)..."
git fetch --tags --force "${OFFICIAL_REPO_URL}" main

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 3. Dynamic mode active: Rebasing '${CUSTOM_REF}' onto bleeding-edge upstream/main..."
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"

    if git rebase FETCH_HEAD; then
        echo "  -> On-the-fly rebase succeeded cleanly!"
        UPSTREAM_BRANCH="main"
    else
        echo "  -> [WARNING] Rebase conflict detected with latest upstream!"
        git rebase --abort
        echo "  -> Aborted rebase and fell back to last known-good '${CUSTOM_REF}' state."
        UPSTREAM_BRANCH="${CUSTOM_REF}"
    fi
else
    echo ">>> 3. Safe fallback channel active: Using pinned '${CUSTOM_REF}' state without rebasing."
    UPSTREAM_BRANCH="${CUSTOM_REF}"
fi

# 4. Calculate the official upstream sync point for version count and Manager APK matching
RAW_BASE=$(git merge-base HEAD FETCH_HEAD)

set +o pipefail
UPSTREAM_HASH=$(git log -n 1 --first-parent "${RAW_BASE}" --format="%H" -i --grep="ci skip" --grep="skip ci" --invert-grep -- manager/ kernel/ userspace/ ":!*Cargo.lock" ":!*Cargo.toml")
set -o pipefail

CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v0.0.0")

cd ..

# ---------------------------------------------------------
# SukiSU-Ultra 6.12+ LSM Hook API Fix
# ---------------------------------------------------------
echo ">>> Checking for Linux 6.12+ LSM API Mismatch in SukiSU-Ultra..."
K_VER=$(grep "^VERSION =" common/Makefile | tr -d ' ' | cut -d'=' -f2)
K_PATCH=$(grep "^PATCHLEVEL =" common/Makefile | tr -d ' ' | cut -d'=' -f2)

if [ "$K_VER" = "6" ] && [ "$K_PATCH" -ge "12" ]; then
    LSM_HOOK_FILE="common/drivers/kernelsu/hook/lsm_hook.c"

    if [ -f "$LSM_HOOK_FILE" ] && grep -q 'security_add_hooks' "$LSM_HOOK_FILE"; then
        echo "  -> Kernel 6.12+ detected. Disarming deprecated LSM hook registration..."
        sed -i 's/security_add_hooks.*/(void)ksu_hooks;/g' "$LSM_HOOK_FILE"
        echo "  -> lsm_hook.c runtime panic trap bypassed!"
    else
        echo "  -> LSM hook is already updated or file missing. Skipping."
    fi
else
    echo "  -> Kernel $K_VER.$K_PATCH detected. Legacy LSM string hook is perfectly valid."
fi

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"
echo ">>> SukiSU-Ultra integration complete."
