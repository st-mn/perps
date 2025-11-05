#!/bin/bash

# Complete Solana Perpetuals Build Script with Environment Setup
# This script sets up the development environment and builds the program

set -e

echo "🚀 Setting up Solana Perpetuals development environment and building..."
echo ""

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

echo "Detected OS: $MACHINE"
echo ""

# Install system dependencies based on OS (Linux only for now)
if [[ "$MACHINE" == "Linux" ]]; then
    echo "📦 Installing system dependencies for Linux..."

    # Check if we have apt (Debian/Ubuntu)
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y curl git build-essential pkg-config libudev-dev
    # Check if we have yum (RHEL/CentOS)
    elif command -v yum &> /dev/null; then
        sudo yum install -y curl git gcc make pkgconfig libudev-devel
    # Check if we have pacman (Arch)
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --needed curl git base-devel pkgconf udev
    else
        echo "⚠️  Unknown Linux package manager, please install: curl git build-essential"
    fi

elif [[ "$MACHINE" == "Mac" ]]; then
    echo "📦 Installing system dependencies for macOS..."

    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Install dependencies
    brew install curl git
fi

# Check if running on Windows (WSL detection)
if grep -qE "(Microsoft|WSL)" /proc/version 2>/dev/null; then
    echo "🪟 Windows WSL environment detected"
    echo "✅ WSL environment ready for Solana development"
fi

echo "🏗️  Building Solana Perpetuals Program with Dependencies..."

# Check if Rust is installed
if ! command -v rustc &> /dev/null; then
    echo "📦 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    echo "✅ Rust installed successfully"
else
    echo "✅ Rust already installed"
fi

# Check if Solana CLI is installed
if ! command -v solana &> /dev/null; then
    echo "📦 Installing Solana CLI..."
    curl -sSfL https://release.solana.com/v1.18.0/install | sh
    export PATH="~/.local/share/solana/install/active_release/bin:$PATH"
    echo "✅ Solana CLI installed successfully"
else
    echo "✅ Solana CLI already installed"
fi

# Install required Rust components
echo "📦 Installing Rust components..."
rustup component add rust-src
rustup target add bpf-unknown-unknown || echo "⚠️  BPF target installation may have failed, continuing..."

# Initialize Solana toolchain (skip if already initialized)
echo "📦 Checking Solana toolchain..."
solana --version || echo "⚠️  Solana CLI not properly configured, continuing..."

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "📦 Installing Python3..."
    sudo apt update && sudo apt install -y python3 python3-venv python3-pip
    echo "✅ Python3 installed successfully"
else
    echo "✅ Python3 already installed"
fi

# Set up Python virtual environment for example
echo "🐍 Setting up Python virtual environment..."
cd example
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✅ Virtual environment created"
fi

# Activate virtual environment and install requirements
echo "📦 Installing Python dependencies..."
source venv/bin/activate
# Use virtual environment's pip explicitly to avoid system pip issues
venv/bin/pip install --upgrade --quiet pip
venv/bin/pip install --quiet -r requirements.txt
echo "✅ Python dependencies installed"

# Return to project root
cd ..
echo "✅ Python environment ready"

# Install TypeScript dependencies (if package.json exists)
if [ -f "example/package.json" ]; then
    echo "📦 Installing TypeScript dependencies..."
    cd example
    npm install || echo "⚠️  npm install failed, continuing..."
    cd ..
else
    echo "⚠️  package.json not found, skipping TypeScript dependencies"
fi

# Update Rust toolchain
echo "🔄 Updating Rust toolchain..."
rustup update stable

# Create target directory if it doesn't exist
mkdir -p target/deploy

# Build the program
echo "🔨 Compiling program..."
echo "Attempting build with cargo-build-sbf..."
cargo build-sbf --manifest-path Cargo.toml --sbf-out-dir target/deploy

if [ $? -ne 0 ]; then
    echo "⚠️  cargo build-sbf failed, trying alternative build method..."
    echo "🔨 Attempting standard cargo build..."
    cargo build --release --target bpf-unknown-unknown
    
    if [ $? -ne 0 ]; then
        echo "❌ All build methods failed!"
        echo "💡 Try running these commands manually:"
        echo "   1. rustup update stable"
        echo "   2. rustup component add rust-src"
        echo "   3. cargo build-sbf"
        exit 1
    fi
fi

# Check for successful build output
if [ -f "target/deploy/simple_perps.so" ]; then
    echo "✅ Build successful!"
    echo "📄 Program binary: target/deploy/simple_perps.so"
    SIZE=$(stat -f%z target/deploy/simple_perps.so 2>/dev/null || stat -c%s target/deploy/simple_perps.so 2>/dev/null || echo "unknown")
    echo "📊 Binary size: ${SIZE} bytes"
else
    echo "❌ Build completed but binary not found!"
    echo "🔍 Searching for compiled binaries..."
    find target -name "*.so" -type f 2>/dev/null || echo "No .so files found"
    exit 1
fi

echo ""
echo "✅ Build and setup complete!"
echo ""
echo "🎯 Next steps:"
echo "   1. Create a Solana keypair: solana-keygen new"
echo "   2. Configure Solana for devnet: solana config set --url https://api.devnet.solana.com"
echo "   3. Get devnet SOL: ./scripts/2_getsol.sh"
echo "   4. Deploy your program: ./scripts/3_deploy.sh devnet"
echo "   5. Run example: ./scripts/4_runexample.sh"
echo ""
echo "📚 Documentation:"
echo "   - Main README: README.md"