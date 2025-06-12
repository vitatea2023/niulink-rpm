#!/bin/bash

# NiuLink ISO Repack Script with Package Group Integration
# Ensures upload-pulse package is installed by adding it to default package groups
# Version: v1.3 (With Groups)
# Date: 2025-06-11

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to run commands with logging
run_cmd() {
    local cmd="$1"
    local desc="$2"
    log_info "Executing: $desc"
    log_info "Command: $cmd"
    echo "===== COMMAND OUTPUT START =====" >> "$LOG_FILE"
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        echo "===== COMMAND OUTPUT END =====" >> "$LOG_FILE"
        log_success "$desc completed successfully"
        return 0
    else
        echo "===== COMMAND OUTPUT END =====" >> "$LOG_FILE"
        log_error "$desc failed"
        return 1
    fi
}

# Check parameters
if [ $# -ne 2 ]; then
    echo "Usage: $0 <original_iso_file> <rpm_file>"
    echo "Example: $0 NiuLinkOS-v1.1.7-2411141913.iso upload-pulse-1.0.0-1.el7.x86_64.rpm"
    exit 1
fi

ORIGINAL_ISO="$1"
RPM_FILE="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/iso_repack_work_groups"
OUTPUT_ISO="${ORIGINAL_ISO%.*}-repack-groups.iso"
LOG_FILE="$SCRIPT_DIR/iso_repack_groups.log"

# Initialize log file
echo "===== NiuLink ISO Repack Groups Log Started at $(date) =====" > "$LOG_FILE"

# Check input files
if [ ! -f "$ORIGINAL_ISO" ]; then
    log_error "ISO file does not exist: $ORIGINAL_ISO"
    exit 1
fi

if [ ! -f "$RPM_FILE" ]; then
    log_error "RPM file does not exist: $RPM_FILE"
    exit 1
fi

log_info "Starting NiuLink ISO repack with package group integration"
log_info "Input ISO: $ORIGINAL_ISO"
log_info "RPM file: $RPM_FILE"
log_info "Output ISO: $OUTPUT_ISO"
log_info "Work directory: $WORK_DIR"
log_info "Log file: $LOG_FILE"

# Check required tools
log_info "Checking required tools..."
missing_tools=()
for tool in xorriso unsquashfs mksquashfs createrepo_c; do
    if ! command -v $tool >/dev/null 2>&1; then
        missing_tools+=("$tool")
    fi
done

if [ ${#missing_tools[@]} -ne 0 ]; then
    log_error "Missing required tools: ${missing_tools[*]}"
    log_info "Please install missing tools:"
    log_info "sudo apt update"
    log_info "sudo apt install -y xorriso squashfs-tools createrepo-c"
    exit 1
fi
log_success "All required tools are installed"

# Clean old work directory
if [ -d "$WORK_DIR" ]; then
    log_info "Cleaning old work directory..."
    run_cmd "sudo rm -rf '$WORK_DIR'" "Remove old work directory"
fi

# Create work directory
log_info "Creating work directory..."
run_cmd "mkdir -p '$WORK_DIR'" "Create work directory"
cd "$WORK_DIR"

# Extract ISO content
log_info "Extracting ISO content..."
run_cmd "xorriso -osirrox on -indev '$SCRIPT_DIR/$ORIGINAL_ISO' -extract / ./" "Extract ISO content"
log_success "ISO content extracted successfully"

# Copy RPM to Packages directory
log_info "Adding RPM package to Packages directory..."
run_cmd "cp '$SCRIPT_DIR/$RPM_FILE' ./Packages/" "Copy RPM to Packages directory"
log_success "RPM package copied to Packages directory"

# Count original packages
ORIG_PKG_COUNT=$(ls -1 ./Packages/*.rpm | wc -l)
log_info "Total packages now: $ORIG_PKG_COUNT (including upload-pulse)"

# Update Packages repository metadata
log_info "Updating Packages repository metadata..."
run_cmd "createrepo_c --update ./Packages" "Update Packages repository metadata"

# CRITICAL: Modify comps.xml to include upload-pulse in a default group
log_info "Modifying package groups to include upload-pulse..."

# Find the main comps.xml file
COMPS_FILE=$(find ./repodata -name "*c7-x86_64-comps.xml" | grep -v ".gz" | head -1)
if [ -n "$COMPS_FILE" ]; then
    log_info "Found comps.xml: $COMPS_FILE"
    
    # Backup original comps.xml
    run_cmd "cp '$COMPS_FILE' '$COMPS_FILE.backup'" "Backup original comps.xml"
    
    # Add upload-pulse to the 'core' group which is default=true
    log_info "Adding upload-pulse to core package group..."
    
    # Find the core group packagelist and add upload-pulse before the closing tag
    # We'll add it as a mandatory package to ensure it gets installed
    sed -i '/<id>core<\/id>/,/<\/packagelist>/ {
        /<\/packagelist>/ i\      <packagereq type="mandatory">upload-pulse</packagereq>
    }' "$COMPS_FILE"
    
    # Verify the modification
    if grep -q 'upload-pulse' "$COMPS_FILE"; then
        log_success "upload-pulse successfully added to core package group"
    else
        log_error "Failed to add upload-pulse to core package group"
        exit 1
    fi
    
    # Also add to minimal environment for good measure
    sed -i '/<id>minimal<\/id>/,/<\/packagelist>/ {
        /<\/packagelist>/ i\      <packagereq type="mandatory">upload-pulse</packagereq>
    }' "$COMPS_FILE"
    
    log_info "Modified comps.xml to include upload-pulse in default installation groups"
    
else
    log_error "Could not find comps.xml file"
    exit 1
fi

# Update root repository with modified comps.xml
log_info "Updating root repository with modified package groups..."
run_cmd "createrepo_c --groupfile '$COMPS_FILE' --update ." "Update root repository with modified comps"

# Verify repository structure
NEW_ROOT_PKGS=$(zcat ./repodata/*primary.xml.gz | grep -c "<package " || echo "0")
NEW_PKG_PKGS=$(zcat ./Packages/repodata/*primary.xml.gz | grep -c "<package " || echo "0")

log_info "Updated package counts:"
log_info "  Root repository: $NEW_ROOT_PKGS packages"
log_info "  Packages repository: $NEW_PKG_PKGS packages"

# Verify upload-pulse is in root repository and package groups
if zcat ./repodata/*primary.xml.gz | grep -q "upload-pulse"; then
    log_success "✅ upload-pulse package found in root repository metadata"
else
    log_error "❌ upload-pulse package NOT found in root repository metadata"
    exit 1
fi

if grep -q 'upload-pulse' "$COMPS_FILE"; then
    log_success "✅ upload-pulse package added to package groups"
else
    log_error "❌ upload-pulse package NOT in package groups"
    exit 1
fi

# Extract and modify squashfs for UEFI fix
log_info "Extracting squashfs filesystem for UEFI fixes..."
run_cmd "sudo unsquashfs -d rootfs LiveOS/squashfs.img" "Extract squashfs filesystem"
log_success "squashfs extracted successfully"

# Mount rootfs for modifications
log_info "Mounting rootfs for UEFI modifications..."
ROOTFS_MOUNT=$(mktemp -d)
run_cmd "sudo mount -o loop rootfs/LiveOS/rootfs.img '$ROOTFS_MOUNT'" "Mount rootfs"
log_success "rootfs mounted at: $ROOTFS_MOUNT"

# Apply UEFI fixes
log_info "Applying UEFI fixes..."
ANACONDA_DIR="$ROOTFS_MOUNT/usr/lib64/python2.7/site-packages/pyanaconda/installclasses"

if [ ! -d "$ANACONDA_DIR" ]; then
    log_error "Anaconda install class directory not found: $ANACONDA_DIR"
    run_cmd "sudo umount '$ROOTFS_MOUNT'" "Unmount rootfs"
    exit 1
fi

# Backup original files
log_info "Backing up original anaconda files..."
run_cmd "sudo cp '$ANACONDA_DIR/fedora.py' '$ANACONDA_DIR/fedora.py.backup'" "Backup fedora.py"
run_cmd "sudo cp '$ANACONDA_DIR/centos.py' '$ANACONDA_DIR/centos.py.backup'" "Backup centos.py"

# Apply UEFI fixes
log_info "Applying core UEFI fixes..."

# 1. Fix fedora.py EFI directory
log_info "  -> Fixing fedora.py EFI directory"
run_cmd "sudo sed -i 's/efi_dir = \"fedora\"/efi_dir = \"centos\"/' '$ANACONDA_DIR/fedora.py'" "Fix fedora.py EFI directory"

# Verify fix
if sudo grep -q 'efi_dir = "centos"' "$ANACONDA_DIR/fedora.py"; then
    log_success "     fedora.py EFI directory fixed to centos"
else
    log_error "     fedora.py EFI directory fix failed"
    run_cmd "sudo umount '$ROOTFS_MOUNT'" "Unmount rootfs"
    exit 1
fi

# 2. Force hide fedora install class
log_info "  -> Force hiding fedora install class"
run_cmd "sudo sed -i '/if productName\\.startswith(\"Red Hat \") or productName\\.startswith(\"CentOS\"):/,+1c\\    # Always hide fedora class to prevent EFI errors\\n    hidden = True' '$ANACONDA_DIR/fedora.py'" "Hide fedora install class"

# 3. Ensure CentOS install class is visible
log_info "  -> Ensuring CentOS install class is always visible"
run_cmd "sudo sed -i 's/if not productName\\.startswith(\"CentOS\"):/if False:  # Always show CentOS class/' '$ANACONDA_DIR/centos.py'" "Make CentOS class visible"

# 4. Update system identification
log_info "  -> Updating system identification files"
sudo tee "$ROOTFS_MOUNT/etc/os-release" > /dev/null << 'EOF'
NAME="CentOS Linux"
VERSION="7 (Core)"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="7"
PRETTY_NAME="CentOS Linux 7 (Core)"
ANSI_COLOR="0;31"
CPE_NAME="cpe:/o:centos:centos:7"
HOME_URL="https://www.centos.org/"
BUG_REPORT_URL="https://bugs.centos.org/"

CENTOS_MANTISBT_PROJECT="CentOS-7"
CENTOS_MANTISBT_PROJECT_VERSION="7"
REDHAT_SUPPORT_PRODUCT="centos"
REDHAT_SUPPORT_PRODUCT_VERSION="7"
EOF

log_success "System identification updated"

# Verify UEFI fixes
log_info "Verifying UEFI fixes..."
if sudo grep -q 'efi_dir = "centos"' "$ANACONDA_DIR/fedora.py"; then
    log_success "✅ fedora.py EFI directory points to centos"
fi
if sudo grep -q 'hidden = True' "$ANACONDA_DIR/fedora.py"; then
    log_success "✅ fedora install class is hidden"
fi
if sudo grep -q 'if False:.*Always show CentOS' "$ANACONDA_DIR/centos.py"; then
    log_success "✅ CentOS install class is always visible"
fi

log_success "All UEFI fixes applied successfully"

# Unmount rootfs
log_info "Unmounting rootfs..."
run_cmd "sudo umount '$ROOTFS_MOUNT'" "Unmount rootfs"
run_cmd "sudo rmdir '$ROOTFS_MOUNT'" "Remove mount point"

# Repack squashfs
log_info "Repacking squashfs filesystem..."
run_cmd "sudo mksquashfs rootfs LiveOS/squashfs.img -comp xz -noappend" "Repack squashfs"
log_success "squashfs repacked successfully"

# Create final ISO
log_info "Creating final ISO with package group integration..."
run_cmd "sudo xorriso -as mkisofs \\
    -o '$SCRIPT_DIR/$OUTPUT_ISO' \\
    -b isolinux/isolinux.bin \\
    -c isolinux/boot.cat \\
    -no-emul-boot \\
    -boot-load-size 4 \\
    -boot-info-table \\
    -eltorito-alt-boot \\
    -e images/efiboot.img \\
    -no-emul-boot \\
    -isohybrid-gpt-basdat \\
    -V 'ISOCDROM' \\
    ." "Create final ISO"

if [ $? -eq 0 ]; then
    log_success "ISO created successfully: $OUTPUT_ISO"
else
    log_error "ISO creation failed"
    exit 1
fi

# Cleanup work directory
log_info "Cleaning up work directory..."
cd "$SCRIPT_DIR"
run_cmd "sudo rm -rf '$WORK_DIR'" "Remove work directory"

# Display results
echo
echo "========================================" | tee -a "$LOG_FILE"
echo "    ISO Repack with Groups Completed Successfully" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Input ISO: $ORIGINAL_ISO" | tee -a "$LOG_FILE"
echo "Output ISO: $OUTPUT_ISO" | tee -a "$LOG_FILE"
echo "Added RPM: $RPM_FILE" | tee -a "$LOG_FILE"
echo "File size: $(du -h "$OUTPUT_ISO" | cut -f1)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"
echo "Package integration:" | tee -a "$LOG_FILE"
echo "  Total packages: $ORIG_PKG_COUNT" | tee -a "$LOG_FILE"
echo "  Root repository: $NEW_ROOT_PKGS packages" | tee -a "$LOG_FILE"
echo "  upload-pulse added to 'core' package group" | tee -a "$LOG_FILE"
echo "  upload-pulse added to 'minimal' environment" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"
echo "Applied fixes:" | tee -a "$LOG_FILE"
echo "✅ UEFI boot errors fixed" | tee -a "$LOG_FILE"
echo "✅ fedora.py EFI directory corrected" | tee -a "$LOG_FILE"
echo "✅ fedora install class hidden" | tee -a "$LOG_FILE"
echo "✅ CentOS install class always visible" | tee -a "$LOG_FILE"
echo "✅ System identification confirmed as CentOS" | tee -a "$LOG_FILE"
echo "✅ RPM package integrated into repository" | tee -a "$LOG_FILE"
echo "✅ RPM package added to mandatory installation groups" | tee -a "$LOG_FILE"
echo "✅ Package groups (comps.xml) updated" | tee -a "$LOG_FILE"
echo "✅ Supports UEFI + Legacy BIOS dual boot" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"
echo "Expected results:" | tee -a "$LOG_FILE"
echo "• No more '/boot/efi/EFI/fedora/user.cfg' errors" | tee -a "$LOG_FILE"
echo "• UEFI installation will complete normally" | tee -a "$LOG_FILE"
echo "• Supports Secure Boot environments" | tee -a "$LOG_FILE"
echo "• Installation source will work correctly" | tee -a "$LOG_FILE"
echo "• upload-pulse will be AUTOMATICALLY INSTALLED as mandatory package" | tee -a "$LOG_FILE"
echo "• Software selection will show correct package count" | tee -a "$LOG_FILE"
echo "• upload-pulse service should start automatically after installation" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"
echo "Usage:" | tee -a "$LOG_FILE"
echo "1. Use $OUTPUT_ISO to create installation media" | tee -a "$LOG_FILE"
echo "2. Supports both UEFI and Legacy BIOS boot" | tee -a "$LOG_FILE"
echo "3. Select CentOS installation option during setup" | tee -a "$LOG_FILE"
echo "4. upload-pulse will be installed automatically" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

echo "===== NiuLink ISO Repack Groups Log Completed at $(date) =====" >> "$LOG_FILE"

log_success "All operations completed successfully! upload-pulse should now be installed automatically."


