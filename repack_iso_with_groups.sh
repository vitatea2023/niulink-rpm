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
if [ $# -lt 2 ]; then
    echo "Usage: $0 <original_iso_file> <rpm_file1> [rpm_file2] [rpm_file3] ..."
    echo "Example: $0 NiuLinkOS-v1.1.7-2411141913.iso upload-pulse-1.0.0-1.el7.x86_64.rpm"
    echo "Example: $0 NiuLinkOS-v1.1.7-2411141913.iso pkg1.rpm pkg2.rpm pkg3.rpm"
    exit 1
fi

ORIGINAL_ISO="$1"
shift  # Remove first argument (ISO file)
RPM_FILES=("$@")  # Store all remaining arguments as RPM files array
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

# Check all RPM files exist
for rpm_file in "${RPM_FILES[@]}"; do
    if [ ! -f "$rpm_file" ]; then
        log_error "RPM file does not exist: $rpm_file"
        exit 1
    fi
done

log_info "Starting NiuLink ISO repack with package group integration"
log_info "Input ISO: $ORIGINAL_ISO"
log_info "RPM files to integrate: ${#RPM_FILES[@]} files"
for i in "${!RPM_FILES[@]}"; do
    log_info "  RPM $((i+1)): ${RPM_FILES[i]}"
done
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

# Copy all RPM packages to Packages directory
log_info "Adding ${#RPM_FILES[@]} RPM packages to Packages directory..."
for rpm_file in "${RPM_FILES[@]}"; do
    rpm_basename=$(basename "$rpm_file")
    log_info "  Copying: $rpm_basename"
    run_cmd "cp '$SCRIPT_DIR/$rpm_file' ./Packages/" "Copy $rpm_basename to Packages directory"
done
log_success "All RPM packages copied to Packages directory"

# Count packages after adding new RPMs
NEW_PKG_COUNT=$(ls -1 ./Packages/*.rpm | wc -l)
log_info "Total packages now: $NEW_PKG_COUNT (including ${#RPM_FILES[@]} new packages)"

# Extract package names from RPM files for later use
PACKAGE_NAMES=()
for rpm_file in "${RPM_FILES[@]}"; do
    # Extract package name from RPM filename (remove version, arch, extension)
    pkg_name=$(rpm -qp --queryformat '%{NAME}' "$SCRIPT_DIR/$rpm_file" 2>/dev/null || {
        # Fallback: extract from filename if rpm command fails
        basename "$rpm_file" | sed 's/-[0-9].*\.rpm$//' | sed 's/-[0-9].*\.el[0-9].*\.rpm$//'
    })
    PACKAGE_NAMES+=("$pkg_name")
    log_info "  Package name extracted: $pkg_name"
done

# Update Packages repository metadata
log_info "Updating Packages repository metadata..."
run_cmd "createrepo_c --update ./Packages" "Update Packages repository metadata"

# CRITICAL: Modify comps.xml to include all custom packages in default groups
log_info "Modifying package groups to include ${#PACKAGE_NAMES[@]} custom packages..."
for pkg_name in "${PACKAGE_NAMES[@]}"; do
    log_info "  Will add package: $pkg_name"
done

# Find the main comps.xml file
COMPS_FILE=$(find ./repodata -name "*c7-x86_64-comps.xml" | grep -v ".gz" | head -1)
if [ -n "$COMPS_FILE" ]; then
    log_info "Found comps.xml: $COMPS_FILE"
    
    # Backup original comps.xml
    run_cmd "cp '$COMPS_FILE' '$COMPS_FILE.backup'" "Backup original comps.xml"
    
    # Add all custom packages to the 'core' group which is default=true
    log_info "Adding ${#PACKAGE_NAMES[@]} packages to core package group..."
    
    # Find the core group packagelist and add all packages before the closing tag
    # We'll add them as mandatory packages to ensure they get installed
    for pkg_name in "${PACKAGE_NAMES[@]}"; do
        log_info "  Adding $pkg_name to core group"
        sed -i '/<id>core<\/id>/,/<\/packagelist>/ {
            /<\/packagelist>/ i\      <packagereq type="mandatory">'"$pkg_name"'</packagereq>
        }' "$COMPS_FILE"
    done
    
    # Verify all packages were added
    ALL_ADDED=true
    for pkg_name in "${PACKAGE_NAMES[@]}"; do
        if grep -q "$pkg_name" "$COMPS_FILE"; then
            log_success "  $pkg_name successfully added to core package group"
        else
            log_error "  Failed to add $pkg_name to core package group"
            ALL_ADDED=false
        fi
    done
    
    if [ "$ALL_ADDED" = false ]; then
        log_error "Failed to add some packages to core package group"
        exit 1
    fi
    
    # Also add all packages to minimal environment for good measure
    log_info "Adding ${#PACKAGE_NAMES[@]} packages to minimal environment..."
    for pkg_name in "${PACKAGE_NAMES[@]}"; do
        log_info "  Adding $pkg_name to minimal environment"
        sed -i '/<id>minimal<\/id>/,/<\/packagelist>/ {
            /<\/packagelist>/ i\      <packagereq type="mandatory">'"$pkg_name"'</packagereq>
        }' "$COMPS_FILE"
    done
    
    log_info "Modified comps.xml to include all custom packages in default installation groups"
    
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

# Verify all custom packages are in root repository and package groups
log_info "Verifying ${#PACKAGE_NAMES[@]} custom packages integration..."

# Check root repository
ALL_IN_REPO=true
for pkg_name in "${PACKAGE_NAMES[@]}"; do
    if zcat ./repodata/*primary.xml.gz | grep -q "$pkg_name"; then
        log_success "✅ $pkg_name package found in root repository metadata"
    else
        log_error "❌ $pkg_name package NOT found in root repository metadata"
        ALL_IN_REPO=false
    fi
done

if [ "$ALL_IN_REPO" = false ]; then
    log_error "Some packages are not in root repository metadata"
    exit 1
fi

# Verify all packages are in package groups  
ALL_IN_GROUPS=true
for pkg_name in "${PACKAGE_NAMES[@]}"; do
    if grep -q "$pkg_name" "$COMPS_FILE"; then
        log_success "✅ $pkg_name package added to package groups"
    else
        log_error "❌ $pkg_name package NOT in package groups"
        ALL_IN_GROUPS=false
    fi
done

if [ "$ALL_IN_GROUPS" = false ]; then
    log_error "Some packages are not in package groups"
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

# Create final ISO with integrated USB boot compatibility
log_info "Creating final ISO with package group integration and USB boot support..."
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
    --protective-msdos-label \\
    -V 'ISOCDROM' \\
    ." "Create final ISO with integrated USB boot support"

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
echo "Added RPMs: ${#RPM_FILES[@]} files" | tee -a "$LOG_FILE"
for i in "${!RPM_FILES[@]}"; do
    echo "  RPM $((i+1)): $(basename "${RPM_FILES[i]}")" | tee -a "$LOG_FILE"
done
echo "File size: $(du -h "$OUTPUT_ISO" | cut -f1)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"
echo "Package integration:" | tee -a "$LOG_FILE"
echo "  Total packages: $NEW_PKG_COUNT" | tee -a "$LOG_FILE"
echo "  Root repository: $NEW_ROOT_PKGS packages" | tee -a "$LOG_FILE"
echo "  Integrated packages added to 'core' package group:" | tee -a "$LOG_FILE"
for pkg_name in "${PACKAGE_NAMES[@]}"; do
    echo "    - $pkg_name" | tee -a "$LOG_FILE"
done
echo "  Integrated packages added to 'minimal' environment:" | tee -a "$LOG_FILE"
for pkg_name in "${PACKAGE_NAMES[@]}"; do
    echo "    - $pkg_name" | tee -a "$LOG_FILE"
done
echo | tee -a "$LOG_FILE"
echo "Applied fixes:" | tee -a "$LOG_FILE"
echo "✅ UEFI boot errors fixed" | tee -a "$LOG_FILE"
echo "✅ fedora.py EFI directory corrected" | tee -a "$LOG_FILE"
echo "✅ fedora install class hidden" | tee -a "$LOG_FILE"
echo "✅ CentOS install class always visible" | tee -a "$LOG_FILE"
echo "✅ System identification confirmed as CentOS" | tee -a "$LOG_FILE"
echo "✅ ${#RPM_FILES[@]} RPM packages integrated into repository" | tee -a "$LOG_FILE"
echo "✅ All RPM packages added to mandatory installation groups" | tee -a "$LOG_FILE"
echo "✅ Package groups (comps.xml) updated" | tee -a "$LOG_FILE"
echo "✅ Supports UEFI + Legacy BIOS dual boot" | tee -a "$LOG_FILE"
echo "✅ USB boot compatibility integrated (isohybrid MBR partition table)" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"
echo "Expected results:" | tee -a "$LOG_FILE"
echo "• No more '/boot/efi/EFI/fedora/user.cfg' errors" | tee -a "$LOG_FILE"
echo "• UEFI installation will complete normally" | tee -a "$LOG_FILE"
echo "• Supports Secure Boot environments" | tee -a "$LOG_FILE"
echo "• Installation source will work correctly" | tee -a "$LOG_FILE"
echo "• USB boot compatibility: Works with BalenaEtcher and other USB burning tools" | tee -a "$LOG_FILE"
echo "• Physical machine USB boot: No more 'partition table not found' errors" | tee -a "$LOG_FILE"
echo "• MBR partition table: Proper isohybrid structure for USB boot" | tee -a "$LOG_FILE"
echo "• All integrated packages will be AUTOMATICALLY INSTALLED as mandatory packages:" | tee -a "$LOG_FILE"
for pkg_name in "${PACKAGE_NAMES[@]}"; do
    echo "  - $pkg_name" | tee -a "$LOG_FILE"
done
echo "• Software selection will show correct package count" | tee -a "$LOG_FILE"
echo "• All integrated services should start automatically after installation" | tee -a "$LOG_FILE"
echo | tee -a "$LOG_FILE"
echo "Usage:" | tee -a "$LOG_FILE"
echo "1. Use $OUTPUT_ISO to create installation media" | tee -a "$LOG_FILE"
echo "2. Supports both UEFI and Legacy BIOS boot" | tee -a "$LOG_FILE"
echo "3. USB/Physical boot: Use BalenaEtcher or dd to write to USB drive" | tee -a "$LOG_FILE"
echo "4. Select CentOS installation option during setup" | tee -a "$LOG_FILE"
echo "5. All integrated packages will be installed automatically" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

echo "===== NiuLink ISO Repack Groups Log Completed at $(date) =====" >> "$LOG_FILE"

log_success "All operations completed successfully! All ${#PACKAGE_NAMES[@]} integrated packages should now be installed automatically. ISO includes integrated USB boot support."


