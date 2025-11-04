#!/bin/bash

# Complete setup script for Solana Perpetuals development environment

set -e

echo "🚀 Setting up complete Solana Perpetuals development environment..."
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

# Install system dependencies based on OS
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

# Install Rust if not present
if ! command -v rustc &> /dev/null; then
    echo "📦 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    echo "✅ Rust installed successfully"
else
    echo "✅ Rust already installed"
fi

# Install Node.js if not present (for TypeScript examples)
if ! command -v node &> /dev/null; then
    echo "📦 Installing Node.js..."
    
    if [[ "$MACHINE" == "Mac" ]]; then
        brew install node
    elif [[ "$MACHINE" == "Linux" ]]; then
        # Install Node.js via NodeSource repository
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs || echo "⚠️  Node.js installation failed, continuing..."
    fi
else
    echo "✅ Node.js already installed"
fi

# Install Python3 if not present (for Python examples)
if ! command -v python3 &> /dev/null; then
    echo "📦 Installing Python3..."
    
    if [[ "$MACHINE" == "Mac" ]]; then
        brew install python3
    elif [[ "$MACHINE" == "Linux" ]]; then
        sudo apt-get install -y python3 python3-pip || echo "⚠️  Python3 installation failed, continuing..."
    fi
else
    echo "✅ Python3 already installed"
fi

# Install Solana CLI if not present
if ! command -v solana &> /dev/null; then
    echo "📦 Installing Solana CLI..."
    curl -sSfL https://release.solana.com/v1.18.0/install | sh
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    echo "✅ Solana CLI installed successfully"
else
    echo "✅ Solana CLI already installed"
fi

echo ""
echo "🔧 Setting up Rust and Solana toolchains..."

# Install Rust components
rustup component add rust-src
rustup target add bpf-unknown-unknown
rustup update stable

# Initialize Solana
solana install init

echo ""
echo "📚 Setting up example dependencies..."

# Install TypeScript dependencies
if [ -f "examples/package.json" ]; then
    echo "📦 Installing TypeScript dependencies..."
    cd examples
    npm install || echo "⚠️  npm install failed, continuing..."
    cd ..
else
    echo "⚠️  package.json not found, skipping TypeScript dependencies"
fi

# Install Python dependencies
if [ -f "examples/requirements.txt" ]; then
    echo "📦 Installing Python dependencies..."
    python3 -m pip install --upgrade pip || echo "⚠️  pip upgrade failed, continuing..."
    pip3 install -r examples/requirements.txt || echo "⚠️  Python dependencies installation failed, continuing..."
else
    echo "⚠️  requirements.txt not found, skipping Python dependencies"
fi

echo ""
echo "🏗️ Running initial build..."
chmod +x scripts/build.sh
./scripts/build.sh

echo ""
echo "✅ Setup complete!"
echo ""
echo "🎯 Next steps:"
echo "   1. Create a Solana keypair: solana-keygen new"
echo "   2. Configure Solana for devnet: solana config set --url https://api.devnet.solana.com"
echo "   3. Get devnet SOL: solana airdrop 2"
echo "   4. Deploy your program: ./scripts/deploy.sh devnet"
echo ""
echo "📚 Documentation:"
echo "   - Main README: README.md"
echo "   - Python examples: examples/README.md"
echo "   - TypeScript client: examples/client.ts"
echo "   - Interactive tutorial: examples/perpetuals_tutorial.ipynb"
echo ""