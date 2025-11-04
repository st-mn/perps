@echo off
REM Windows build script for Solana Perpetuals Program with auto-installation

echo [BUILD] Building Solana Perpetuals Program with Dependencies...

REM Check if Rust is installed
where rustc >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [INFO] Rust not found, checking for cargo...
    where cargo >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        echo [INFO] Installing Rust...
        echo Downloading Rust installer...
        
        REM Try PowerShell download first
        powershell -Command "try { Invoke-WebRequest -Uri 'https://win.rustup.rs/x86_64' -OutFile 'rustup-init.exe' -UseBasicParsing } catch { exit 1 }"
        if %ERRORLEVEL% neq 0 (
            echo Trying alternative download method...
            powershell -Command "try { (New-Object System.Net.WebClient).DownloadFile('https://win.rustup.rs/x86_64', 'rustup-init.exe') } catch { exit 1 }"
        )
        if %ERRORLEVEL% neq 0 (
            echo Trying curl...
            curl -L https://win.rustup.rs/x86_64 -o rustup-init.exe
        )
        
        if exist rustup-init.exe (
            echo Running Rust installer...
            rustup-init.exe -y --default-toolchain stable
            del rustup-init.exe
            echo [OK] Rust installed successfully
        ) else (
            echo [WARN] Failed to download Rust installer
            echo [INFO] Please install Rust manually from: https://rustup.rs/
            pause
            exit /b 1
        )
    ) else (
        echo [OK] Cargo found, updating PATH for rustc...
    )
    REM Refresh PATH for Rust tools
    set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
) else (
    echo [OK] Rust already installed
    rustc --version
)

REM Check if Solana CLI is installed
where solana >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [OK] Solana CLI already in PATH
    solana --version
    goto :solana_available
)

REM Check common Solana installation paths if not in PATH
if exist "%USERPROFILE%\.local\share\solana\install\active_release\bin\solana.exe" (
            echo [OK] Solana CLI found in local install, adding to PATH...
    set "PATH=%USERPROFILE%\.local\share\solana\install\active_release\bin;%PATH%"
    goto :solana_available
)

REM Check WSL installation as fallback
where wsl >nul 2>nul
if %ERRORLEVEL% equ 0 (
    wsl which solana >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        echo [OK] Solana CLI found in WSL
        goto :solana_available
    )
)

echo [ERROR] Solana CLI not found!
echo [INFO] Please install Solana CLI using one of these methods:
echo.
echo Method 1 - WSL (Recommended for Windows):
echo    1. Install WSL: wsl --install (run as Administrator)
echo    2. Reboot if prompted
echo    3. In WSL: sudo apt update ^&^& sudo apt install curl git
echo    4. In WSL: sh -c "$(curl -sSfL https://release.solana.com/v1.18.0/install)"
echo    5. In WSL: echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' ^>^> ~/.bashrc
echo.
echo Method 2 - Direct Windows install:
echo    1. Visit: https://docs.solana.com/cli/install-solana-cli-tools
echo    2. Follow Windows installation instructions
echo.
echo Then run this script again.
pause
exit /b 1

:solana_available
echo [OK] Solana CLI is available

REM Refresh PATH to ensure Rust is available
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"

REM Verify Rust is now accessible
where rustc >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Rust still not found in PATH after installation!
    echo [INFO] Please restart your terminal and run this script again.
    pause
    exit /b 1
)

echo [OK] Rust tools now available in PATH
rustc --version
cargo --version

REM Setup proper build environment for Windows
echo [INFO] Setting up build environment...

REM Check if we have a working C compiler
where link.exe >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [OK] Using MSVC toolchain
    rustup default stable-x86_64-pc-windows-msvc
    goto :compiler_ready
)

where gcc.exe >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [INFO] Found GCC, checking for complete GNU toolchain...
    where dlltool.exe >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        echo [WARN] dlltool.exe missing from MinGW installation
        echo [INFO] Trying to add complete MinGW toolchain to PATH...
        set "PATH=C:\Users\stant\source\ncg-ex\mingw64\bin;%PATH%"
        where dlltool.exe >nul 2>nul
        if %ERRORLEVEL% neq 0 (
            echo [ERROR] Complete MinGW toolchain not found!
            echo [HELP] Please install complete MinGW-w64 toolchain:
            echo        choco install mingw --force
            echo        OR
            echo        winget install msys2.msys2
            echo        Then in MSYS2: pacman -S mingw-w64-x86_64-toolchain
            pause
            exit /b 1
        ) else (
            echo [OK] dlltool.exe found after PATH update
        )
    ) else (
        echo [OK] Complete GNU toolchain found
    )
    echo [INFO] Using GNU toolchain
    rustup default stable-x86_64-pc-windows-gnu
    set "RUSTFLAGS=-C linker=C:\Users\stant\source\ncg-ex\mingw64\bin\gcc.exe"
    goto :compiler_ready
)

echo [ERROR] No C compiler found! 
echo [INFO] For Solana development on Windows, you need either:
echo.
echo Option 1 - Visual Studio Build Tools (Recommended):
echo    winget install Microsoft.VisualStudio.2022.BuildTools
echo    Then select "C++ build tools" workload during installation
echo.
echo Option 2 - Complete MinGW-w64:
echo    winget install msys2.msys2
echo    Then in MSYS2: pacman -S mingw-w64-x86_64-gcc
echo.
echo Option 3 - Use WSL (Alternative):
echo    wsl --install
echo    Then build in Linux environment
echo.
echo Please install one of these options and run this script again.
pause
exit /b 1

:compiler_ready
REM Ensure MinGW toolchain is in PATH for GNU builds
set "PATH=C:\Users\stant\source\ncg-ex\mingw64\bin;%PATH%"

REM Install required Rust components
echo [INFO] Installing Rust components...
rustup component add rust-src
if %ERRORLEVEL% neq 0 (
    echo [WARN] rust-src component installation may have failed, continuing...
)

REM Note: bpf-unknown-unknown is deprecated in favor of sbf-solana-solana
echo [INFO] Adding Solana BPF target...
rustup target add sbf-solana-solana 2>nul
if %ERRORLEVEL% neq 0 (
    echo Trying legacy BPF target...
    rustup target add bpf-unknown-unknown 2>nul
    if %ERRORLEVEL% neq 0 (
        echo [WARN] BPF target installation may have failed, continuing...
    )
)

REM Update Rust toolchain
echo 🔄 Updating Rust toolchain...
rustup update stable

REM Initialize Solana toolchain
echo [INFO] Initializing Solana toolchain...
solana install init 2>nul || wsl bash -l -c "solana install init" 2>nul
if %ERRORLEVEL% neq 0 (
    echo [WARN] Solana init may have failed, continuing...
)

REM Install Solana Platform Tools (includes cargo-build-sbf)
echo [INFO] Installing Solana Platform Tools...
cargo --list | findstr "build-sbf" >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo Installing solana-cli tools via cargo...
    cargo install solana-cli --features=default 2>nul
    if %ERRORLEVEL% neq 0 (
        echo Trying alternative installation method...
        REM Try installing platform-tools which includes build tools
        cargo install --git https://github.com/solana-labs/solana platform-tools --tag v1.18.0 2>nul
        if %ERRORLEVEL% neq 0 (
            echo [WARN] Solana platform tools installation failed, will use alternative build methods...
        )
    )
) else (
    echo [OK] cargo build-sbf already available
)

REM Verify build tools are available
cargo --list | findstr "build" >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [OK] Cargo build tools detected:
    cargo --list | findstr "build"
) else (
    echo [WARN] No cargo build tools found, will try standard methods
)

REM Create target directory if it doesn't exist
if not exist "target\deploy" mkdir target\deploy

REM Build the program
echo � Compiling program...

REM Create target directory if it doesn't exist
if not exist "target\deploy" mkdir target\deploy

REM Ensure PATH includes Rust tools for all build attempts
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"

REM Method 1: Try cargo build-sbf (modern Solana, preferred)
echo Attempting build with cargo build-sbf...
cargo build-sbf --manifest-path Cargo.toml --sbf-out-dir target/deploy 2>nul
if %ERRORLEVEL% equ 0 goto :build_success

REM Method 2: Try cargo-build-bpf (legacy, if available)
echo Attempting build with cargo-build-bpf...
cargo build-bpf --manifest-path Cargo.toml --bpf-out-dir target/deploy 2>nul
if %ERRORLEVEL% equ 0 goto :build_success

REM Method 3: Try standard cargo build for Solana BPF target
echo Attempting standard cargo build for Solana target...
cargo build --release --target sbf-solana-solana 2>nul
if %ERRORLEVEL% equ 0 (
    REM Copy the binary to the expected location
    if exist "target\sbf-solana-solana\release\simple_perps.so" (
        copy "target\sbf-solana-solana\release\simple_perps.so" "target\deploy\simple_perps.so" >nul
        if %ERRORLEVEL% equ 0 goto :build_success
    )
)

REM Method 4: Try legacy BPF target
echo Attempting build with legacy BPF target...
cargo build --release --target bpf-unknown-unknown 2>nul
if %ERRORLEVEL% equ 0 (
    REM Copy the binary to the expected location
    if exist "target\bpf-unknown-unknown\release\simple_perps.so" (
        copy "target\bpf-unknown-unknown\release\simple_perps.so" "target\deploy\simple_perps.so" >nul
        if %ERRORLEVEL% equ 0 goto :build_success
    )
)

REM Method 5: Try regular release build (fallback)
echo Attempting regular release build...
cargo build --release

if %ERRORLEVEL% equ 0 (
    echo [WARN] Regular build succeeded, but may not be suitable for Solana deployment
    echo [INFO] You may need to install Solana CLI tools for proper BPF compilation
) else (
    echo [ERROR] All build methods failed!
    echo [INFO] Try these steps manually:
    echo    1. Verify Rust PATH: echo %%PATH%% ^| findstr cargo
    echo    2. Test cargo: %USERPROFILE%\.cargo\bin\cargo --version
    echo    3. Add required components: rustup component add rust-src
    echo    4. Add Solana target: rustup target add sbf-solana-solana
    echo    5. Install Solana CLI tools via WSL or direct installation
    echo    6. Try manual build: cargo build --release --target sbf-solana-solana
    echo.
    echo Debug information:
    echo    Rust location: %USERPROFILE%\.cargo\bin
    echo    Current PATH: %PATH%
    exit /b 1
)

goto :end

:build_success
REM Check for successful build output
if exist "target\deploy\simple_perps.so" (
    echo [SUCCESS] Build successful!
    echo [INFO] Program binary: target\deploy\simple_perps.so
    for %%A in (target\deploy\simple_perps.so) do echo [INFO] Binary size: %%~zA bytes
) else if exist "target\sbf-solana-solana\release\simple_perps.so" (
    echo [SUCCESS] Build successful!
    echo [INFO] Program binary: target\sbf-solana-solana\release\simple_perps.so
    if not exist "target\deploy" mkdir target\deploy
    copy "target\sbf-solana-solana\release\simple_perps.so" "target\deploy\simple_perps.so"
    for %%A in (target\deploy\simple_perps.so) do echo [INFO] Binary size: %%~zA bytes
) else if exist "target\bpf-unknown-unknown\release\simple_perps.so" (
    echo [SUCCESS] Build successful!
    echo [INFO] Program binary: target\bpf-unknown-unknown\release\simple_perps.so
    if not exist "target\deploy" mkdir target\deploy
    copy "target\bpf-unknown-unknown\release\simple_perps.so" "target\deploy\simple_perps.so"
    for %%A in (target\deploy\simple_perps.so) do echo [INFO] Binary size: %%~zA bytes
) else (
    echo [ERROR] Build completed but binary not found!
    echo [INFO] Searching for compiled binaries...
    powershell -Command "Get-ChildItem -Path . -Filter *.so -Recurse | Select-Object FullName, Length"
    exit /b 1
)

echo.
echo [SUCCESS] Ready to deploy! Run scripts\deploy.bat to deploy to Solana.

:end