#!/usr/bin/env bash

# SketchyBar Configuration Installer
# Enhanced version with better error handling, logging, and user feedback

set -euo pipefail # Stricter error handling

# Configuration
REPO_URL="https://github.com/yourusername/sketchybar-config.git"
CONFIG_DIR="$HOME/.config/sketchybar"
BACKUP_DIR="$HOME/.config/sketchybar_backup_$(date +%Y%m%d_%H%M%S)"
FONT_DIR="$HOME/sketchybar-app-font"
LOG_FILE="/tmp/sketchybar_install.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_FILE"
    echo -e "$1"
}

# Error handling
error_exit() {
    log "${RED}❌ Error: $1${NC}"
    log "${YELLOW}💡 Check the log file: $LOG_FILE${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message
info() {
    log "${CYAN}ℹ️  $1${NC}"
}

# Progress indicator
progress() {
    log "${PURPLE}🔄 $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cleanup function for interrupted installations
cleanup() {
    if [[ $? -ne 0 ]]; then
        warning "Installation was interrupted. Cleaning up..."
        # Restore backup if it exists and installation failed
        if [[ -d "$BACKUP_DIR" && ! -d "$CONFIG_DIR" ]]; then
            mv "$BACKUP_DIR" "$CONFIG_DIR"
            info "Restored previous configuration from backup"
        fi
    fi
}

trap cleanup EXIT

# Header
echo -e "${BLUE}"
cat <<"EOF"
╔══════════════════════════════════════════════════════════════╗
║                    SketchyBar Configuration                  ║
║                         Installer                            ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log "Starting SketchyBar configuration installation..."
log "Log file: $LOG_FILE"

# Pre-installation checks
info "Performing pre-installation checks..."

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    error_exit "This script is designed for macOS only"
fi

# Check for Homebrew
if ! command_exists brew; then
    error_exit "Homebrew is required but not installed. Please install it from https://brew.sh"
fi

# Check for Git
if ! command_exists git; then
    error_exit "Git is required but not installed. Please install it first."
fi

# Check available disk space (at least 500MB)
available_space=$(df -m "$HOME" | awk 'NR==2 {print $4}')
if [[ $available_space -lt 500 ]]; then
    warning "Low disk space detected (${available_space}MB available). Installation may fail."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

success "Pre-installation checks passed"

# Stage 1: Homebrew Dependencies
progress "[1/5] Installing Homebrew dependencies..."

brew_packages=("lua" "switchaudio-osx" "nowplaying-cli" "pnpm")
failed_packages=()

for package in "${brew_packages[@]}"; do
    if brew list "$package" &>/dev/null; then
        info "$package is already installed"
    else
        info "Installing $package..."
        if ! brew install "$package" >>"$LOG_FILE" 2>&1; then
            failed_packages+=("$package")
        fi
    fi
done

# Install SketchyBar
info "Adding FelixKratz tap and installing SketchyBar..."
if ! brew tap FelixKratz/formulae >>"$LOG_FILE" 2>&1; then
    warning "Failed to add FelixKratz tap (might already exist)"
fi

if brew list sketchybar &>/dev/null; then
    info "SketchyBar is already installed"
else
    if ! brew install sketchybar >>"$LOG_FILE" 2>&1; then
        error_exit "Failed to install SketchyBar"
    fi
fi

if [[ ${#failed_packages[@]} -gt 0 ]]; then
    warning "Some packages failed to install: ${failed_packages[*]}"
    log "Check the log file for details: $LOG_FILE"
else
    success "All Homebrew dependencies installed successfully"
fi

# Stage 2: Fonts Installation
progress "[2/5] Installing fonts..."

font_packages=("sf-symbols" "font-sf-mono" "font-sf-pro" "font-victor-mono-nerd-font")
failed_fonts=()

for font in "${font_packages[@]}"; do
    if brew list --cask "$font" &>/dev/null; then
        info "$font is already installed"
    else
        info "Installing $font..."
        if ! brew install --cask "$font" >>"$LOG_FILE" 2>&1; then
            failed_fonts+=("$font")
        fi
    fi
done

if [[ ${#failed_fonts[@]} -gt 0 ]]; then
    warning "Some fonts failed to install: ${failed_fonts[*]}"
fi

# App icons font installation
info "Installing sketchybar-app-font..."
if [[ -d "$FONT_DIR" ]]; then
    warning "Font directory already exists. Updating..."
    cd "$FONT_DIR"
    if ! git pull >>"$LOG_FILE" 2>&1; then
        warning "Failed to update existing font repository"
    fi
else
    info "Cloning sketchybar-app-font repository..."
    if ! git clone https://github.com/kvndrsslr/sketchybar-app-font.git "$FONT_DIR" >>"$LOG_FILE" 2>&1; then
        error_exit "Failed to clone sketchybar-app-font repository"
    fi
    cd "$FONT_DIR"
fi

info "Building and installing app font..."
if ! pnpm install >>"$LOG_FILE" 2>&1; then
    error_exit "Failed to install font dependencies"
fi

# Try to build with custom script path, fallback to default
script_path="$CONFIG_DIR/scripts/app_icons.sh"
if ! pnpm run build:install -- "$script_path" >>"$LOG_FILE" 2>&1; then
    warning "Failed to build with custom script path, trying default..."
    if ! pnpm run build:install >>"$LOG_FILE" 2>&1; then
        error_exit "Failed to build and install app font"
    fi
fi

# Force refresh font cache
info "Refreshing font cache..."
sudo killall -9 fontd 2>/dev/null || true
fc-cache -f 2>/dev/null || true

success "Fonts installation completed"

# Stage 3: SbarLua Framework
progress "[3/5] Installing SbarLua framework..."

info "Cloning and installing SbarLua..."
temp_dir="/tmp/SbarLua_$(date +%s)"
if ! git clone https://github.com/FelixKratz/SbarLua.git "$temp_dir" >>"$LOG_FILE" 2>&1; then
    error_exit "Failed to clone SbarLua repository"
fi

cd "$temp_dir"
if ! make install >>"$LOG_FILE" 2>&1; then
    error_exit "Failed to install SbarLua framework"
fi

# Cleanup
rm -rf "$temp_dir"
success "SbarLua framework installed successfully"

# Stage 4: Configuration
progress "[4/5] Installing configuration..."

# Backup existing configuration
if [[ -d "$CONFIG_DIR" ]]; then
    info "Backing up existing configuration to $BACKUP_DIR"
    if ! mv "$CONFIG_DIR" "$BACKUP_DIR"; then
        error_exit "Failed to backup existing configuration"
    fi
    success "Existing configuration backed up"
fi

# Clone new configuration
info "Cloning new configuration..."
if ! git clone "$REPO_URL" "$CONFIG_DIR" >>"$LOG_FILE" 2>&1; then
    error_exit "Failed to clone configuration repository"
fi

# Set proper permissions
chmod +x "$CONFIG_DIR"/*.sh 2>/dev/null || true
chmod +x "$CONFIG_DIR"/scripts/*.sh 2>/dev/null || true

success "Configuration installed successfully"

# Stage 5: Start SketchyBar
progress "[5/5] Starting SketchyBar..."

# Stop any existing SketchyBar instance
info "Stopping any existing SketchyBar instances..."
brew services stop sketchybar 2>/dev/null || true
pkill -f sketchybar 2>/dev/null || true
sleep 2

# Start SketchyBar service
info "Starting SketchyBar service..."
if ! brew services start sketchybar >>"$LOG_FILE" 2>&1; then
    error_exit "Failed to start SketchyBar service"
fi

# Wait a moment for the service to start
sleep 3

# Verify SketchyBar is running
if pgrep -f sketchybar >/dev/null; then
    success "SketchyBar started successfully"
else
    warning "SketchyBar may not have started correctly. Check the log and try manually: brew services restart sketchybar"
fi

# Final message
echo -e "${GREEN}"
cat <<"EOF"
╔══════════════════════════════════════════════════════════════╗
║                     Installation Complete! 🎉                ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

success "SketchyBar configuration installed successfully!"

echo -e "${CYAN}"
cat <<EOF

📋 Next Steps:
1. Configure your monitor setup in: ~/.config/sketchybar/items/aerospace_workspaces.lua
2. Update WiFi interface in: ~/.config/sketchybar/items/wifi.lua  
3. Set your location in: ~/.config/sketchybar/items/weather.lua
4. Customize media player in: ~/.config/sketchybar/items/media.lua

📝 Backup Location: $BACKUP_DIR (if applicable)
📄 Installation Log: $LOG_FILE

🔧 Troubleshooting:
   - If widgets don't show: brew services restart sketchybar
   - If fonts are missing: sudo killall -9 fontd && fc-cache -f
   - For help: Check the README.md in your config directory

EOF
echo -e "${NC}"

log "Installation completed successfully at $(date)"
