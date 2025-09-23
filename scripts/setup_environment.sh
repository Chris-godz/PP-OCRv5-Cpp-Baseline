#!/bin/bash
# PP-OCRv5 Environment Setup Script
# This script automates the environment setup process

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if script is run with sufficient privileges
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
    
    # Check if user can sudo
    if ! sudo -v; then
        log_error "This script requires sudo privileges"
        exit 1
    fi
}

# System information check
check_system() {
    log_info "Checking system information..."
    
    echo "System: $(uname -a)"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"')"
    echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
    echo "Storage: $(df -h . | tail -1 | awk '{print $4}') available"
    echo "CPU Cores: $(nproc)"
    
    # Check minimum requirements
    local mem_gb=$(free -g | grep Mem | awk '{print $2}')
    if [ "$mem_gb" -lt 8 ]; then
        log_warning "Less than 8GB RAM detected. Consider adding swap space."
    fi
    
    local arch=$(uname -m)
    echo "Architecture: $arch"
    
    log_success "System check completed"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    
    sudo apt update
    sudo apt upgrade -y
    
    log_success "System packages updated"
}

# Install GCC-8 from PPA if needed (for Paddle compatibility)
install_gcc8_from_ppa() {
    log_info "Attempting to install GCC-8 from PPA for better Paddle compatibility..."
    
    # Add toolchain PPA
    if ! grep -q "ubuntu-toolchain-r/test" /etc/apt/sources.list.d/* 2>/dev/null; then
        log_info "Adding Ubuntu toolchain PPA..."
        sudo apt install -y software-properties-common
        sudo add-apt-repository ppa:ubuntu-toolchain-r/test -y
        sudo apt update
    else
        log_info "Ubuntu toolchain PPA already added"
    fi
    
    # Try to install GCC-8
    if sudo apt install -y gcc-8 g++-8; then
        log_success "GCC-8 installed successfully from PPA"
        
        # Set up alternative with higher priority
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 100 \
            --slave /usr/bin/g++ g++ /usr/bin/g++-8
        
        # Set as default
        sudo update-alternatives --set gcc /usr/bin/gcc-8
        
        log_success "GCC-8 set as default compiler"
        return 0
    else
        log_warning "Could not install GCC-8 from PPA"
        return 1
    fi
}

# Install basic development tools
install_basic_tools() {
    log_info "Installing basic development tools..."
    
    # Install basic tools first
    sudo apt install -y \
        build-essential \
        ccache \
        cmake \
        git \
        wget \
        curl \
        vim \
        htop \
        python3-dev \
        python3-pip \
        python-is-python3
    
    # Install binutils-gold (try different package names)
    if apt-cache show binutils-gold &>/dev/null; then
        sudo apt install -y binutils-gold
    elif apt-cache show binutils &>/dev/null; then
        sudo apt install -y binutils
        log_warning "binutils-gold not available, installed binutils instead"
    fi
    
    # Check available GCC versions and install appropriate ones
    log_info "Checking available GCC versions..."
    
    # Check Ubuntu/Debian version to determine available GCC versions
    local ubuntu_version=""
    if [ -f /etc/os-release ]; then
        ubuntu_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    fi
    
    # Available GCC versions based on Ubuntu version (in order of preference - GCC 11 as default)
    local gcc_versions=()
    case "$ubuntu_version" in
        "20.04")
            gcc_versions=("gcc-11" "gcc-10" "gcc-9")  # Prefer 11, fallback to 10, then 9
            ;;
        "22.04")
            gcc_versions=("gcc-11" "gcc-10" "gcc-9")  # Prefer 11, fallback to 10, then 9
            ;;
        "24.04")
            gcc_versions=("gcc-11" "gcc-10" "gcc-9")  # Prefer 11, fallback to 10, then 9
            ;;
        *)
            # For unknown versions, prioritize GCC 11 first
            local available_versions=($(apt-cache search "^gcc-[0-9]+$" | awk '{print $1}' | sort -V))
            # First try GCC 11, then other compatible versions
            if echo "${available_versions[@]}" | grep -q "gcc-11"; then
                gcc_versions+=("gcc-11")
            fi
            # Then add other versions 8-12 (excluding 11 if already added)
            for version in "${available_versions[@]}"; do
                local ver_num="${version#gcc-}"
                if [ "$ver_num" -ge 8 ] && [ "$ver_num" -le 12 ] && [ "$version" != "gcc-11" ]; then
                    gcc_versions+=("$version")
                fi
            done
            # If no compatible versions found, use what's available
            if [ ${#gcc_versions[@]} -eq 0 ]; then
                gcc_versions=("${available_versions[@]}")
            fi
            ;;
    esac
    
    log_info "Ubuntu version: $ubuntu_version"
    log_info "Will try to install GCC versions (in order of preference): ${gcc_versions[*]}"
    
    # Install ONLY the first available/compatible GCC version
    local installed_gcc=""
    for gcc_pkg in "${gcc_versions[@]}"; do
        local gpp_pkg="${gcc_pkg/gcc/g++}"
        local version="${gcc_pkg#gcc-}"
        
        if apt-cache show "$gcc_pkg" &>/dev/null && apt-cache show "$gpp_pkg" &>/dev/null; then
            log_info "Installing $gcc_pkg and $gpp_pkg (version $version)..."
            if sudo apt install -y "$gcc_pkg" "$gpp_pkg"; then
                installed_gcc="$gcc_pkg"
                log_success "$gcc_pkg and $gpp_pkg installed successfully"
                break  # Stop after first successful installation
            else
                log_warning "Failed to install $gcc_pkg and $gpp_pkg, trying next version..."
            fi
        else
            log_warning "$gcc_pkg or $gpp_pkg not available in repositories"
        fi
    done
    
    # Setup GCC alternatives if we have an installed version
    if [ -n "$installed_gcc" ]; then
        local version="${installed_gcc#gcc-}"
        log_info "Setting up GCC-$version as default compiler..."
        
        # Set up alternative
        sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-$version 100 \
            --slave /usr/bin/g++ g++ /usr/bin/g++-$version
        
        # Set as default
        sudo update-alternatives --set gcc /usr/bin/gcc-$version
        
        # Verify current GCC version
        local current_gcc=$(gcc --version | head -1)
        log_success "Current GCC version: $current_gcc"
        
        # Check compatibility with Paddle
        local gcc_major=$(gcc -dumpversion | cut -d. -f1)
        if [ "$gcc_major" -eq 11 ]; then
            log_success "GCC version $gcc_major is the preferred version for this build"
        elif [ "$gcc_major" -ge 8 ] && [ "$gcc_major" -le 12 ]; then
            log_success "GCC version $gcc_major is compatible for Paddle Inference"
        else
            log_warning "GCC version $gcc_major may have compatibility issues with Paddle Inference"
            log_warning "Consider using GCC 11 for optimal compatibility"
        fi
    else
        log_error "No compatible GCC versions could be installed."
        log_info "Will try to use system default GCC or offer PPA installation"
        
        # Check if system GCC exists
        if command -v gcc &> /dev/null; then
            local system_gcc=$(gcc --version | head -1)
            log_warning "Using system default GCC: $system_gcc"
        fi
    fi
    
    log_success "Basic development tools installation completed"
}

# Install Miniconda
install_miniconda() {
    log_info "Checking for existing conda installation..."
    
    # Check if conda command is available in PATH
    if command -v conda &> /dev/null; then
        local conda_version=$(conda --version 2>/dev/null || echo "unknown")
        local conda_path=$(which conda)
        log_success "Conda is already installed and available in PATH"
        echo "  Version: $conda_version"
        echo "  Location: $conda_path"
        return
    fi
    
    # Check common conda installation paths
    local conda_paths=(
        "$HOME/miniconda3/bin/conda"
        "$HOME/anaconda3/bin/conda"
        "$HOME/miniforge3/bin/conda"
        "$HOME/mambaforge/bin/conda"
        "/opt/miniconda3/bin/conda"
        "/opt/anaconda3/bin/conda"
        "/usr/local/miniconda3/bin/conda"
        "/usr/local/anaconda3/bin/conda"
    )
    
    for conda_path in "${conda_paths[@]}"; do
        if [ -f "$conda_path" ]; then
            log_success "Found existing conda installation at: $conda_path"
            local conda_version=$("$conda_path" --version 2>/dev/null || echo "unknown")
            echo "  Version: $conda_version"
            
            # Add to PATH for current session
            export PATH="$(dirname "$conda_path"):$PATH"
            
            # Initialize conda if not already done
            if ! grep -q "conda initialize" ~/.bashrc 2>/dev/null; then
                log_info "Initializing conda for bash..."
                "$conda_path" init bash
            else
                log_info "Conda already initialized in ~/.bashrc"
            fi
            
            log_success "Using existing conda installation"
            return
        fi
    done
    
    # Check if conda is installed via package manager
    if dpkg -l | grep -q conda 2>/dev/null; then
        log_warning "Conda appears to be installed via package manager but not found in standard locations"
        log_info "You may need to manually activate it or add it to PATH"
    fi
    
    log_info "No existing conda installation found. Installing Miniconda..."
    
    # Determine architecture and download URL
    local arch=$(uname -m)
    local miniconda_url=""
    
    if [ "$arch" = "x86_64" ]; then
        miniconda_url="https://repo.anaconda.com/miniconda/Miniconda3-py312_25.5.1-1-Linux-x86_64.sh"
    elif [ "$arch" = "aarch64" ]; then
        miniconda_url="https://repo.anaconda.com/miniconda/Miniconda3-py312_25.5.1-1-Linux-aarch64.sh"
    else
        log_error "Unsupported architecture: $arch"
        exit 1
    fi
    
    local installer="Miniconda3-py312_25.5.1-1-Linux-${arch}.sh"
    
    # Check if installer already exists
    if [ -f "$installer" ]; then
        log_info "Installer $installer already exists, using it..."
    else
        log_info "Downloading Miniconda installer..."
        if ! wget "$miniconda_url" -O "$installer"; then
            log_error "Failed to download Miniconda installer"
            exit 1
        fi
    fi
    
    chmod +x "$installer"
    
    # Check available space before installation
    local available_space=$(df -BM . | tail -1 | awk '{print $4}' | sed 's/M//')
    if [ "$available_space" -lt 500 ]; then
        log_error "Insufficient disk space. Need at least 500MB, available: ${available_space}MB"
        exit 1
    fi
    
    # Install silently
    log_info "Installing Miniconda to $HOME/miniconda3..."
    if bash "$installer" -b -p "$HOME/miniconda3"; then
        log_success "Miniconda installation completed"
    else
        log_error "Miniconda installation failed"
        exit 1
    fi
    
    # Initialize conda
    log_info "Initializing conda..."
    if "$HOME/miniconda3/bin/conda" init bash; then
        log_success "Conda initialized successfully"
    else
        log_warning "Conda initialization may have failed"
    fi
    
    # Add to current session PATH
    export PATH="$HOME/miniconda3/bin:$PATH"
    
    # Clean up installer
    rm "$installer"
    
    log_success "Miniconda installed successfully"
    log_warning "Please restart your shell or run 'source ~/.bashrc' to use conda"
}

# Create conda environment
create_conda_env() {
    log_info "Creating conda environment 'deepx'..."
    
    # Check if conda is available in multiple ways
    local conda_cmd=""
    
    if command -v conda &> /dev/null; then
        conda_cmd="conda"
    elif [ -f "$HOME/miniconda3/bin/conda" ]; then
        conda_cmd="$HOME/miniconda3/bin/conda"
        export PATH="$HOME/miniconda3/bin:$PATH"
    elif [ -f "$HOME/anaconda3/bin/conda" ]; then
        conda_cmd="$HOME/anaconda3/bin/conda"
        export PATH="$HOME/anaconda3/bin:$PATH"
    else
        log_error "Conda not found. Please install Miniconda first or check your installation."
        exit 1
    fi
    
    log_info "Using conda at: $(which $conda_cmd 2>/dev/null || echo $conda_cmd)"
    
    # Check if environment already exists
    if $conda_cmd env list | grep -q "deepx"; then
        log_warning "Environment 'deepx' already exists, skipping creation..."
        local existing_python=$($conda_cmd run -n deepx python --version 2>/dev/null || echo "unknown")
        echo "  Existing environment Python version: $existing_python"
        return
    fi
    
    # Create environment with error checking
    log_info "Creating new conda environment 'deepx' with Python 3.12..."
    if $conda_cmd create -n deepx python=3.12 -y; then
        log_success "Conda environment 'deepx' created successfully"
        
        # Verify the environment was created
        if $conda_cmd env list | grep -q "deepx"; then
            local python_version=$($conda_cmd run -n deepx python --version 2>/dev/null || echo "unknown")
            echo "  Python version in new environment: $python_version"
        else
            log_warning "Environment created but verification failed"
        fi
    else
        log_error "Failed to create conda environment 'deepx'"
        exit 1
    fi
}

# Configure pip
configure_pip() {
    log_info "Configuring pip..."
    
    # Backup existing config
    [ -f /etc/pip.conf ] && sudo cp /etc/pip.conf /etc/pip.conf.backup 2>/dev/null || true
    
    # Remove old config
    sudo rm -f /etc/pip.conf
    
    # Find and activate conda environment if available
    local conda_cmd=""
    if command -v conda &> /dev/null; then
        conda_cmd="conda"
    elif [ -f "$HOME/miniconda3/bin/conda" ]; then
        conda_cmd="$HOME/miniconda3/bin/conda"
        export PATH="$HOME/miniconda3/bin:$PATH"
    elif [ -f "$HOME/anaconda3/bin/conda" ]; then
        conda_cmd="$HOME/anaconda3/bin/conda"
        export PATH="$HOME/anaconda3/bin:$PATH"
    fi
    
    if [ -n "$conda_cmd" ]; then
        # Try to activate deepx environment
        if $conda_cmd env list | grep -q "deepx"; then
            log_info "Activating 'deepx' environment for pip configuration..."
            eval "$($conda_cmd shell.bash hook)" 2>/dev/null || true
            $conda_cmd activate deepx 2>/dev/null || log_warning "Could not activate deepx environment"
        fi
    fi
    
    # Configure pip (using USTC mirror for faster downloads in China)
    # Check if we're in the right environment
    local current_python=$(which python 2>/dev/null || which python3 2>/dev/null || echo "not found")
    log_info "Using Python at: $current_python"
    
    if command -v pip &> /dev/null; then
        log_info "Upgrading pip..."
        pip install -i https://mirrors.ustc.edu.cn/pypi/simple pip -U
        
        log_info "Setting pip global index URL..."
        pip config set global.index-url https://mirrors.ustc.edu.cn/pypi/simple
        
        # Verify configuration
        local pip_index=$(pip config get global.index-url 2>/dev/null || echo "not configured")
        echo "  Pip index URL: $pip_index"
        
        log_success "Pip configured successfully"
        
        # Install required Python packages for OCR accuracy calculation
        log_info "Installing required Python packages..."
        local required_packages=(
            "jiwer"
            "numpy"
            "opencv-python"
        )
        
        for package in "${required_packages[@]}"; do
            log_info "Installing $package..."
            if pip install -i https://mirrors.ustc.edu.cn/pypi/simple "$package"; then
                log_success "$package installed successfully"
            else
                log_warning "Failed to install $package, it may already be installed or will be installed later"
            fi
        done
        
        log_success "Python packages installation completed"
    else
        log_error "Pip not found. Please check Python installation."
        exit 1
    fi
}

# Setup swap if needed
setup_swap() {
    local mem_gb=$(free -g | grep Mem | awk '{print $2}')
    
    if [ "$mem_gb" -lt 16 ]; then
        log_info "Setting up swap file (detected ${mem_gb}GB RAM)..."
        
        if [ -f /swapfile ]; then
            log_warning "Swap file already exists, skipping..."
            return
        fi
        
        sudo fallocate -l 4G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        
        # Add to fstab for persistence
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
        fi
        
        log_success "Swap file created and activated"
    else
        log_info "Sufficient RAM detected (${mem_gb}GB), skipping swap setup"
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    echo "=== Installation Verification ==="
    echo "GCC Version: $(gcc --version | head -1)"
    echo "CMake Version: $(cmake --version | head -1)"
    echo "Python Version: $(python --version 2>/dev/null || python3 --version 2>/dev/null || echo "Not available in current shell")"
    
    # Check conda in multiple ways
    local conda_found=false
    if command -v conda &> /dev/null; then
        echo "Conda Version: $(conda --version)"
        echo "Conda Location: $(which conda)"
        conda_found=true
    elif [ -f "$HOME/miniconda3/bin/conda" ]; then
        echo "Conda Version: $($HOME/miniconda3/bin/conda --version)"
        echo "Conda Location: $HOME/miniconda3/bin/conda"
        conda_found=true
    elif [ -f "$HOME/anaconda3/bin/conda" ]; then
        echo "Conda Version: $($HOME/anaconda3/bin/conda --version)"
        echo "Conda Location: $HOME/anaconda3/bin/conda"
        conda_found=true
    else
        echo "Conda: Not found in standard locations"
    fi
    
    if [ "$conda_found" = true ]; then
        echo "Conda Environments:"
        local conda_cmd="conda"
        [ ! command -v conda &> /dev/null ] && [ -f "$HOME/miniconda3/bin/conda" ] && conda_cmd="$HOME/miniconda3/bin/conda"
        [ ! command -v conda &> /dev/null ] && [ -f "$HOME/anaconda3/bin/conda" ] && conda_cmd="$HOME/anaconda3/bin/conda"
        
        $conda_cmd env list | grep -E "deepx|^#" || echo "  No environments found"
        
        # Check if deepx environment exists and is functional
        if $conda_cmd env list | grep -q "deepx"; then
            local deepx_python=$($conda_cmd run -n deepx python --version 2>/dev/null || echo "Error")
            echo "DeepX Environment Python: $deepx_python"
        fi
    else
        echo "Conda: Will be available after shell restart"
    fi
    
    echo "Available Memory: $(free -h | grep Mem | awk '{print $7}')"
    echo "Available Storage: $(df -h . | tail -1 | awk '{print $4}')"
    
    if [ -f /swapfile ]; then
        echo "Swap: $(free -h | grep Swap | awk '{print $2}')"
    fi
    
    # Check if bash profile was modified
    if grep -q "conda initialize" ~/.bashrc 2>/dev/null; then
        echo "Conda Initialization: Added to ~/.bashrc"
    else
        echo "Conda Initialization: Not found in ~/.bashrc"
    fi
    
    log_success "Installation verification completed"
}

# Main execution
main() {
    echo "=================================="
    echo "  PP-OCRv5 Environment Setup"
    echo "=================================="
    echo
    
    check_privileges
    check_system
    
    echo
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
    
    update_system
    install_basic_tools    
    install_miniconda
    create_conda_env
    configure_pip
    setup_swap
    verify_installation
    
    echo
    log_success "Environment setup completed!"
    echo
    echo "Next steps:"
    echo "1. Restart your shell or run: source ~/.bashrc"
    echo "2. Activate conda environment: conda activate deepx"
    echo "3. Run the dependency installation script: ./compile_dependencies.sh"
}

# Run main function
main "$@"