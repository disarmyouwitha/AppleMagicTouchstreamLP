#!/usr/bin/env bash

# GitHub Release Script for Swift Package Manager
# This script builds the XCFramework, creates a GitHub release, and updates Package.swift

set -e  # Exit on any error

# Configuration - UPDATE THESE VALUES
GITHUB_USERNAME="krishkrosh"        # Replace with your GitHub username
REPO_NAME="OpenMultitouchSupport"            # Replace with your repository name
RELEASE_VERSION=""                     # Will be prompted or passed as argument

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if required tools are installed
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed. Install it with: brew install gh"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed"
        exit 1
    fi
    
    if ! command -v swift &> /dev/null; then
        log_error "Swift is not installed"
        exit 1
    fi
    
    # Check if logged into GitHub CLI
    if ! gh auth status &> /dev/null; then
        log_error "Not logged into GitHub CLI. Run: gh auth login"
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# Get version from user input or command line argument
get_version() {
    if [ -n "$1" ]; then
        RELEASE_VERSION="$1"
    else
        echo -n "Enter the release version (e.g., 1.0.0): "
        read RELEASE_VERSION
    fi
    
    if [ -z "$RELEASE_VERSION" ]; then
        log_error "Version is required"
        exit 1
    fi
    
    # Add 'v' prefix if not present
    if [[ ! $RELEASE_VERSION =~ ^v ]]; then
        RELEASE_VERSION="v${RELEASE_VERSION}"
    fi
    
    log_info "Release version: $RELEASE_VERSION"
}

# Update configuration from git remote
update_config_from_git() {
    local remote_url=$(git config --get remote.origin.url)
    
    if [[ $remote_url =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
        GITHUB_USERNAME="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]%.git}"
        log_info "Auto-detected GitHub repo: $GITHUB_USERNAME/$REPO_NAME"
    else
        log_warning "Could not auto-detect GitHub repository from git remote"
        echo -n "Enter GitHub username: "
        read GITHUB_USERNAME
        echo -n "Enter repository name: "
        read REPO_NAME
    fi
}

# Build the XCFramework
build_framework() {
    log_info "Building XCFramework..."
    
    # Clear caches and build
    ./build_framework.sh --release
    
    if [ ! -f "OpenMultitouchSupportXCF.xcframework.zip" ]; then
        log_error "XCFramework build failed - zip file not found"
        exit 1
    fi
    
    log_success "XCFramework built successfully"
}

# Update Package.swift with release information
update_package_swift() {
    local checksum=$(swift package compute-checksum OpenMultitouchSupportXCF.xcframework.zip)
    local url="https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/releases/download/${RELEASE_VERSION}/OpenMultitouchSupportXCF.xcframework.zip"
    
    log_info "Updating Package.swift..."
    log_info "URL: $url"
    log_info "Checksum: $checksum"
    
    # Check if template exists, otherwise use current Package.swift
    log_info "Using Package.swift.template"
    source_file="Package.swift.template"
    
    # Create a temporary Package.swift for release
    sed -e "s|YOUR_USERNAME|${GITHUB_USERNAME}|g" \
        -e "s|YOUR_REPO_NAME|${REPO_NAME}|g" \
        -e "s|VERSION|${RELEASE_VERSION}|g" \
        -e "s|CHECKSUM_PLACEHOLDER|${checksum}|g" \
        "$source_file" > Package.swift.release
    
    log_success "Package.swift updated for release"
}

# Create GitHub release
create_github_release() {
    log_info "Creating GitHub release..."
    
    # Create release notes
    local release_notes="## OpenMultitouchSupport ${RELEASE_VERSION}

### Changes
- XCFramework build for macOS
- Swift Package Manager support

### Installation
Add this package to your project using Swift Package Manager:

\`\`\`
https://github.com/${GITHUB_USERNAME}/${REPO_NAME}
\`\`\`

### Checksum
\`$(swift package compute-checksum OpenMultitouchSupportXCF.xcframework.zip)\`"
    
    # Create the release
    gh release create "$RELEASE_VERSION" \
        "OpenMultitouchSupportXCF.xcframework.zip" \
        --title "OpenMultitouchSupport $RELEASE_VERSION" \
        --notes "$release_notes"
    
    log_success "GitHub release created: $RELEASE_VERSION"
}

# Commit and push the updated Package.swift
update_repository() {
    log_info "Updating repository with release Package.swift..."
    
    # Replace Package.swift with release version
    cp Package.swift.release Package.swift
    rm Package.swift.release
    
    # Commit and push
    git add Package.swift
    git commit -m "Update Package.swift for release $RELEASE_VERSION"
    git push origin main
    
    log_success "Repository updated"
}

# Revert Package.swift to development version
revert_to_development() {
    log_info "Reverting Package.swift to development version..."
    
    # Revert to local development version
    git checkout HEAD~1 -- Package.swift
    
    # Update for local development
    sed -i.bak 's|url: "https://github.com/.*/releases/download/.*/OpenMultitouchSupportXCF.xcframework.zip",|path: "OpenMultitouchSupportXCF.xcframework.zip"|g; /checksum:/d' Package.swift
    rm Package.swift.bak
    
    git add Package.swift
    git commit -m "Revert Package.swift to development version"
    git push origin main
    
    log_success "Reverted to development version"
}

# Test function to verify update_package_swift works
test_update_package_swift() {
    log_info "Testing update_package_swift function..."
    
    # Set test values
    GITHUB_USERNAME="krishkrosh"
    REPO_NAME="OpenMultitouchSupport"
    RELEASE_VERSION="v1.0.9-test"
    
    # Create a dummy zip file for checksum calculation
    echo "dummy content for testing" > dummy.zip
    
    # Override checksum calculation for testing
    local checksum="abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
    local url="https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/releases/download/${RELEASE_VERSION}/OpenMultitouchSupportXCF.xcframework.zip"
    
    log_info "Test parameters:"
    log_info "URL: $url"
    log_info "Checksum: $checksum"
    
    # Check if template exists, otherwise use current Package.swift
    if [ -f "Package.swift.template" ]; then
        log_info "Using Package.swift.template"
        source_file="Package.swift.template"
    else
        log_warning "Package.swift.template not found, using current Package.swift"
        source_file="Package.swift"
    fi
    
    # Create a test Package.swift
    sed -e "s|YOUR_USERNAME|${GITHUB_USERNAME}|g" \
        -e "s|YOUR_REPO_NAME|${REPO_NAME}|g" \
        -e "s|VERSION|${RELEASE_VERSION}|g" \
        -e "s|CHECKSUM_PLACEHOLDER|${checksum}|g" \
        "$source_file" > Package.swift.test
    
    log_success "Test Package.swift created as Package.swift.test"
    echo ""
    echo "Generated content:"
    echo "=================="
    cat Package.swift.test
    echo "=================="
    echo ""
    
    # Verify the replacements worked
    if grep -q "YOUR_USERNAME\|YOUR_REPO_NAME\|VERSION\|CHECKSUM_PLACEHOLDER" Package.swift.test; then
        log_error "Some placeholders were not replaced!"
        grep "YOUR_USERNAME\|YOUR_REPO_NAME\|VERSION\|CHECKSUM_PLACEHOLDER" Package.swift.test
    else
        log_success "All placeholders were successfully replaced!"
    fi
    
    # Cleanup
    rm -f dummy.zip
    echo -n "Remove test file Package.swift.test? (y/N): "
    read cleanup_choice
    if [[ $cleanup_choice =~ ^[Yy]$ ]]; then
        rm Package.swift.test
        log_info "Test file removed"
    else
        log_info "Test file kept as Package.swift.test"
    fi
}

# Main execution
main() {
    echo "🚀 GitHub Release Script for OpenMultitouchSupport"
    echo "=================================================="
    
    check_dependencies
    update_config_from_git
    get_version "$1"
    
    log_info "Starting release process for version $RELEASE_VERSION"
    
    # Build framework
    build_framework
    
    # Update Package.swift for release
    update_package_swift
    
    # Create GitHub release
    create_github_release
    
    # Update repository with release Package.swift
    update_repository
    
    # Optional: Revert to development version (NOT RECOMMENDED for SPM)
    log_warning "IMPORTANT: For Swift Package Manager to work, keep the release version in GitHub!"
    log_warning "Only revert if you understand this breaks SPM for other developers."
    echo -n "Do you want to revert Package.swift to development version? (y/N): "
    read revert_choice
    if [[ $revert_choice =~ ^[Yy]$ ]]; then
        log_warning "This will break Swift Package Manager for other developers!"
        echo -n "Are you sure? (y/N): "
        read confirm_choice
        if [[ $confirm_choice =~ ^[Yy]$ ]]; then
            revert_to_development
        else
            log_info "Keeping release version (recommended)"
        fi
    else
        log_success "Keeping release version (recommended for SPM)"
    fi
    
    echo ""
    log_success "Release complete! 🎉"
    echo ""
    echo "Next steps:"
    echo "1. Other developers can now add your package using:"
    echo "   https://github.com/${GITHUB_USERNAME}/${REPO_NAME}"
    echo "2. The release is available at:"
    echo "   https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/releases/tag/${RELEASE_VERSION}"
}

# Check for test flag
if [[ "$1" == "--test" || "$1" == "test" ]]; then
    test_update_package_swift
else
    # Run main function with all arguments
    main "$@"
fi
