#!/usr/bin/env bash
set -euo pipefail

# Configuration: Toggle custom Kconfig integration via ENV (Defaults to false)
WITH_CUSTOM=${WITH_CUSTOM:-false}

# Define the source fragment relative to the script execution point
FRAGMENT_SRC="$(pwd)/tools/custom.fragment"

echo "=== Configuring Kconfigs & Fragments ==="

cd kernel_workspace

echo ">>> Neutralizing ABI protected exports lists..."
for f in common/android/abi_gki_protected_exports*; do
  [ -f "$f" ] && > "$f"
done

if [ "$WITH_CUSTOM" = "true" ]; then
    if [ ! -f "$FRAGMENT_SRC" ]; then
        echo "[-] Error: Fragment file not found at $FRAGMENT_SRC"
        exit 1
    fi

    echo ">>> Integrating Kconfig Configurations from $FRAGMENT_SRC..."
    cd common
    
    # Check if we are in a modern Bazel ecosystem
    if [ -f "BUILD.bazel" ]; then
        echo ">>> Modern Bazel detected: Injecting via post_defconfig_fragments..."
        
        # Copy the static fragment into the Bazel package boundary
        cp "$FRAGMENT_SRC" custom_fragment
        
        # Inject fragment targeting into the Bazel build rules
        echo 'exports_files(["custom_fragment"])' >> BUILD.bazel
        sed -i 's/"trim_nonlisted_kmi": True,/"trim_nonlisted_kmi": False,/g' BUILD.bazel
        sed -i '/"kernel_aarch64": {/a \        "defconfig_fragments": ["custom_fragment"],' BUILD.bazel
        
        # Exclude the untracked fragment from standard git tracking status
        echo "custom_fragment" >> .git/info/exclude
        
            # --- THE FINAL BOSS BYPASS ---
    if [ -f "modules.bzl" ]; then
        echo ">>> Syncing Kleaf's expected module list with monolithic payloads..."
        
        # Define the exact modules we baked into vmlinux
        BAKED_MODULES=(
            "btbcm.ko" "btqca.ko" "hci_uart.ko" "mii.ko" 
            "cdc_eem.ko" "cdc_ether.ko" "cdc_ncm.ko" 
            "usbnet.ko" "bluetooth.ko" "rfkill.ko"
        )
        
         # Dynamically erase only our baked modules from the attendance sheet
        for mod in "${BAKED_MODULES[@]}"; do
            sed -i "/$mod/d" modules.bzl
        done

    fi        
        
    else
        echo ">>> Legacy Make detected (5.10 or older): Copying fragment..."
        cp "$FRAGMENT_SRC" arch/arm64/configs/custom_legacy.fragment
    fi
    
    cd ..
else
    echo ">>> Skipping custom Kconfig configuration..."
fi

cd ..
echo ">>> Kconfig configuration phase complete."
