#!/usr/bin/env bash

set -euo pipefail

# Colors for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
log_info() {
    echo -e "${GREEN}INFO:${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}WARN:${NC} $1"
}

log_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed"
        exit 1
    fi
}

# Check required commands
check_command flatpak
check_command gh
check_command git
check_command curl
check_command jq

# Check if we're in the right directory
if [[ ! -f "com.gooseberrydevelopment.pinepods.yml" ]]; then
    log_error "Please run this script from the flatpak directory containing the manifest"
    exit 1
fi

# Get version number
read -p "Enter the version number (e.g., 0.7.1): " VERSION
if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid version format. Must be in format X.Y.Z"
    exit 1
fi

log_info "Setting up for version $VERSION"

# Setup shared-modules if not present
if [[ ! -d "shared-modules" ]]; then
    log_info "Setting up shared-modules..."
    git submodule add https://github.com/flathub/shared-modules.git
    git submodule update --init --recursive
fi

# Download the deb file and get its sha256
log_info "Downloading deb file..."
DEB_URL="https://github.com/madeofpendletonwool/PinePods/releases/download/${VERSION}/Pinepods_${VERSION}_amd64.deb"
curl -LO "$DEB_URL"
DEB_SHA256=$(sha256sum "Pinepods_${VERSION}_amd64.deb" | cut -d' ' -f1)

# Update manifest with new version and sha256
log_info "Updating manifest..."
sed -i "s|url: .*/pinepods_.*_amd64.deb|url: $DEB_URL|" com.gooseberrydevelopment.pinepods.yml
sed -i "s|sha256: [a-f0-9]*|sha256: $DEB_SHA256|" com.gooseberrydevelopment.pinepods.yml

# Create flathub.json if it doesn't exist
if [[ ! -f "flathub.json" ]]; then
    log_info "Creating flathub.json..."
    cat > flathub.json << EOF
{
  "only-arches": ["x86_64"]
}
EOF
fi

# Validate files
log_info "Validating files..."
MISSING_FILES=0

for file in "com.gooseberrydevelopment.pinepods.yml" "com.gooseberrydevelopment.pinepods.metainfo.xml" "flathub.json"; do
    if [[ ! -f "$file" ]]; then
        log_error "Missing required file: $file"
        MISSING_FILES=1
    fi
done

if [[ $MISSING_FILES -eq 1 ]]; then
    log_error "Please provide all required files"
    exit 1
fi

# Run flatpak-builder-lint
log_info "Running linter..."
flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest com.gooseberrydevelopment.pinepods.yml
flatpak run --command=flatpak-builder-lint org.flatpak.Builder appstream com.gooseberrydevelopment.pinepods.metainfo.xml

# Local build test
log_info "Running local build test..."
flatpak-builder --force-clean --sandbox --user --install-deps-from=flathub --ccache \
    --mirror-screenshots-url=https://dl.flathub.org/media/ --repo=repo builddir \
    com.gooseberrydevelopment.pinepods.yml

# Show status and ask for confirmation
echo
log_info "Current status:"
echo "- Version: $VERSION"
echo "- Deb SHA256: $DEB_SHA256"
echo "- Files present:"
ls -l

# Test installation
log_info "Testing local installation..."
# Remove old remote if it exists
flatpak remote-delete --user my-pinepods-repo 2>/dev/null || true
# Add the new remote
flatpak remote-add --user --no-gpg-verify my-pinepods-repo "$(pwd)/repo"
# Install the package
flatpak install --user -y my-pinepods-repo com.gooseberrydevelopment.pinepods

# Test run
log_info "Testing application launch. Press Ctrl+C to continue if it works..."
flatpak run com.gooseberrydevelopment.pinepods

# Clean up test remote
log_info "Cleaning up test remote..."
flatpak remote-delete --user my-pinepods-repo

# Now proceed with "Ready to submit" question

read -p "Ready to submit to Flathub? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Submitting to Flathub..."
    
    # Navigate to parent directory to clone flathub
    cd ..
   
    # Remove existing flathub directory if it exists
    if [[ -d "flathub" ]]; then
        log_info "Removing existing flathub directory..."
        rm -rf flathub
    fi


    # Clone Flathub repo if not already present
    if [[ ! -d "flathub" ]]; then
        gh repo fork --clone flathub/flathub
    fi
    
    cd flathub
    git checkout --track origin/new-pr 2>/dev/null || git checkout new-pr
    git checkout -b "pinepods-submission-${VERSION}" new-pr

    # Clean any existing files
    rm -f com.gooseberrydevelopment.pinepods.* flathub.json
    rm -rf icons shared-modules

    # Copy files
    cp ../flatpak/com.gooseberrydevelopment.pinepods.* .
    cp ../flatpak/flathub.json .
    cp -r ../flatpak/icons .

    # Setup shared-modules
    if [[ ! -d "shared-modules" ]]; then
        git submodule add https://github.com/flathub/shared-modules.git
        git submodule update --init --recursive
    fi


    # Show files to be submitted
    log_info "Files to be submitted to Flathub:"
    ls -l

    read -p "Verify these are the correct files for Flathub submission. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Submission cancelled"
        exit 1
    fi

    
    # Commit and push
    git add com.gooseberrydevelopment.pinepods.* flathub.json shared-modules icons
    git commit -m "Add com.gooseberrydevelopment.pinepods $VERSION"
    git push -u origin "pinepods-submission-${VERSION}"
    
	gh pr create --base new-pr --title "Add com.gooseberrydevelopment.pinepods" \
    	--body "Please confirm your submission meets all the criteria

	* Application builds and functions properly when built and installed locally

	* Please describe the application briefly. \`PinePods is a self-hosted podcast management server written in Rust/Tauri that allows you to play, download, and manage podcasts. This flatpak is the client to connect to the server\`

	* The domain used for the application ID is controlled by the application developer(s) and the application id guidelines are followed.

	* I have read and followed all the Submission requirements and the Submission guide.

	* I have built and tested the submission locally.

	* I am an author/developer/upstream contributor to the project. If not, I contacted upstream developers about this submission."

    log_info "Submission complete! PR created on Flathub"
else
    log_info "Submission cancelled"
fi
