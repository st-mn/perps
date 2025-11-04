@echo off
REM Complete setup script for Solana Perpetuals development environment

echo 🚀 Setting up complete Solana Perpetuals development environment...
echo.

REM Check if we're running as administrator
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ⚠️  Note: Some installations may require administrator privileges
    echo.
)

REM Install Chocolatey if not present (for package management)
where choco >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo 📦 Installing Chocolatey package manager...
    @"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" || echo ⚠️ Chocolatey installation failed, continuing...
    refreshenv
) else (
    echo ✅ Chocolatey already installed
)

REM Install Git if not present
where git >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo 📦 Installing Git...
    choco install git -y || echo ⚠️ Git installation failed, continuing...
) else (
    echo ✅ Git already installed
)

REM Install Rust if not present
where rustc >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo 📦 Installing Rust...
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs -o rustup-init.exe
    rustup-init.exe -y --default-toolchain stable
    del rustup-init.exe
    call "%USERPROFILE%\.cargo\env.bat"
) else (
    echo ✅ Rust already installed
)

REM Install Node.js if not present (for TypeScript examples)
where node >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo 📦 Installing Node.js...
    choco install nodejs -y || echo ⚠️ Node.js installation failed, continuing...
) else (
    echo ✅ Node.js already installed
)

REM Install Python if not present (for Python examples)
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo 📦 Installing Python...
    choco install python -y || echo ⚠️ Python installation failed, continuing...
) else (
    echo ✅ Python already installed
)

REM Install Solana CLI
where solana >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo 📦 Installing Solana CLI...
    curl https://release.solana.com/v1.18.0/solana-install-init-x86_64-pc-windows-msvc.exe --output C:\solana-installer.exe
    C:\solana-installer.exe v1.18.0
    del C:\solana-installer.exe
    set "PATH=%USERPROFILE%\.local\share\solana\install\active_release\bin;%PATH%"
) else (
    echo ✅ Solana CLI already installed
)

echo.
echo 🔧 Setting up Rust and Solana toolchains...

REM Install Rust components
rustup component add rust-src
rustup target add bpf-unknown-unknown
rustup update stable

REM Initialize Solana
solana install init

echo.
echo 📚 Setting up example dependencies...

REM Install TypeScript and dependencies
if exist "examples\package.json" (
    echo 📦 Installing TypeScript dependencies...
    cd examples
    npm install || echo ⚠️ npm install failed, continuing...
    cd ..
) else (
    echo ⚠️ package.json not found, skipping TypeScript dependencies
)

REM Install Python dependencies
if exist "examples\requirements.txt" (
    echo 📦 Installing Python dependencies...
    python -m pip install --upgrade pip || echo ⚠️ pip upgrade failed, continuing...
    pip install -r examples\requirements.txt || echo ⚠️ Python dependencies installation failed, continuing...
) else (
    echo ⚠️ requirements.txt not found, skipping Python dependencies
)

echo.
echo 🏗️ Running initial build...
call scripts\build.bat

echo.
echo ✅ Setup complete! 
echo.
echo 🎯 Next steps:
echo    1. Create a Solana keypair: solana-keygen new
echo    2. Configure Solana for devnet: solana config set --url https://api.devnet.solana.com
echo    3. Get devnet SOL: solana airdrop 2
echo    4. Deploy your program: scripts\deploy.bat devnet
echo.
echo 📚 Documentation:
echo    - Main README: README.md
echo    - Python examples: examples\README.md
echo    - TypeScript client: examples\client.ts
echo    - Interactive tutorial: examples\perpetuals_tutorial.ipynb
echo.