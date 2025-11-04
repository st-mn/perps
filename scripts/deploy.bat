@echo off
REM Windows deployment script for Solana Perpetuals Program

setlocal EnableDelayedExpansion

REM Ensure Rust tools are in PATH
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"

set NETWORK=%1
set KEYPAIR_PATH=%2

if "%NETWORK%"=="" set NETWORK=devnet
if "%KEYPAIR_PATH%"=="" set KEYPAIR_PATH=%USERPROFILE%\.config\solana\id.json

echo [DEPLOY] Deploying Solana Perpetuals Program to %NETWORK%...

REM Check if program is built
if not exist "target\deploy\simple_perps.so" (
    echo [ERROR] Program not built. Building now...
    
    REM Try to build using cargo build-sbf
    echo Attempting to build with cargo build-sbf...
    set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
    cargo build-sbf --manifest-path Cargo.toml --sbf-out-dir target/deploy 2>nul
    if exist "target\deploy\simple_perps.so" (
        echo [OK] Program built successfully with cargo build-sbf
        goto :program_ready
    ) else (
        echo [ERROR] cargo build-sbf failed
    )
    
    REM Try to build using WSL where Solana CLI is available
    echo Attempting to build with WSL Solana CLI...
    wsl sh -c "cd /c/Users/stant/source/perps && solana program build --output target/deploy" 2>nul
    echo Build exit code: %ERRORLEVEL%
    if exist "target\deploy\simple_perps.so" (
        echo [OK] Program built successfully with WSL
        goto :program_ready
    ) else (
        echo [ERROR] WSL build failed or file not found
    )
    
    REM Fallback: Try native cargo build-sbf
    echo Attempting native cargo build-sbf...
    set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
    cargo build-sbf --manifest-path Cargo.toml --sbf-out-dir target/deploy 2>nul
    if %ERRORLEVEL% equ 0 (
        echo [OK] Program built successfully with cargo build-sbf
        goto :program_ready
    )
    
    REM Final fallback: Try standard cargo build
    echo Attempting standard cargo build...
    cargo build --release --target sbf-solana-solana 2>nul
    if %ERRORLEVEL% equ 0 (
        if exist "target\sbf-solana-solana\release\simple_perps.so" (
            copy "target\sbf-solana-solana\release\simple_perps.so" "target\deploy\simple_perps.so" >nul
            echo [OK] Program built successfully with standard cargo build
            goto :program_ready
        )
    )
    
    echo [ERROR] Failed to build program. Please run scripts\build.bat first.
    exit /b 1
)

:program_ready
echo [OK] Program ready for deployment

REM Check if keypair exists, create if not
if not exist "%KEYPAIR_PATH%" (
    echo [KEYPAIR] Keypair not found at %KEYPAIR_PATH%
    echo [TOOL] Creating new keypair...
    
    REM Create the config directory if it doesn't exist
    if not exist "%USERPROFILE%\.config\solana" mkdir "%USERPROFILE%\.config\solana"
    
    REM Create a basic test keypair for development
    echo [174,47,154,16,202,193,206,113,199,190,53,133,169,175,31,56,222,53,138,189,224,216,117,173,10,149,53,45,73,46,49,10,163,52,169,70,54,145,163,28,168,104,9,64,3,96,125,177,120,25,67,171,76,19,7,156,2,73,118,29,183,7,89,47] > "%KEYPAIR_PATH%"
    
    echo [OK] Test keypair created successfully
    echo [WARNING] WARNING: This is a test keypair for development only!
    echo [WARNING] Do not use this keypair for mainnet or with real funds!
) else (
    echo [OK] Keypair found at %KEYPAIR_PATH%
)

REM Set Solana config using extracted Solana CLI directly
echo [CONFIG] Configuring Solana CLI...
set "SOLANA_BIN=%CD%\solana-release\bin"
%SOLANA_BIN%\solana.exe config set --keypair "%KEYPAIR_PATH%"

if "%NETWORK%"=="devnet" (
    %SOLANA_BIN%\solana.exe config set --url https://api.devnet.solana.com
    echo [AIRDROP] Airdropping SOL for deployment devnet only...
    %SOLANA_BIN%\solana.exe airdrop 2 --commitment finalized 2>nul && echo [OK] Airdrop successful || echo [WARNING] Airdrop may have failed, continuing...
) else if "%NETWORK%"=="testnet" (
    %SOLANA_BIN%\solana.exe config set --url https://api.testnet.solana.com
) else if "%NETWORK%"=="mainnet" (
    %SOLANA_BIN%\solana.exe config set --url https://api.mainnet-beta.solana.com
    echo [WARNING] DEPLOYING TO MAINNET! Make sure you have enough SOL for deployment.
) else (
    echo [ERROR] Invalid network: %NETWORK%. Use 'devnet', 'testnet', or 'mainnet'
    exit /b 1
)

REM Check balance
echo [BALANCE] Checking wallet balance...
for /f "tokens=*" %%a in ('%SOLANA_BIN%\solana.exe balance --commitment finalized 2^>nul') do set BALANCE=%%a
echo [BALANCE] Wallet balance: %BALANCE% SOL

REM Deploy the program
echo [DEPLOY] Deploying program...
for /f "tokens=*" %%a in ('%SOLANA_BIN%\solana.exe program deploy target/deploy/simple_perps.so --commitment finalized --output json 2^>nul') do set DEPLOY_OUTPUT=%%a

REM Extract Program ID (simplified - in practice you'd use a JSON parser)
echo %DEPLOY_OUTPUT% | findstr /C:"programId" >nul
if %ERRORLEVEL% equ 0 (
    REM Save a simple success indicator
    echo Deployment appears successful > program_deployed.txt
    echo [OK] Deployment successful!
    echo [NETWORK] Network: %NETWORK%
    echo [SAVE] Check program_deployed.txt for confirmation
    
    echo.
    echo [SUCCESS] Your perpetuals program is now live!
    echo [NEXT] Next steps:
    echo    1. Create token accounts for collateral USDC/USDT
    echo    2. Initialize market state and positions
    echo    3. Test opening positions with your client application
) else (
    echo [ERROR] Automatic deployment failed due to Solana CLI issues
    echo [INFO] To deploy manually, you can use one of these methods:
    echo.
    echo Method 1 - Install Solana CLI:
    echo    1. Download from: https://docs.solana.com/cli/install-solana-cli-tools
    echo    2. Run: solana program deploy target/deploy/simple_perps.so
    echo.
    echo Method 2 - Use Solana Explorer:
    echo    1. Go to: https://explorer.solana.com
    echo    2. Connect wallet and upload target/deploy/simple_perps.so
    echo.
    echo Method 3 - Use third-party deployment service
    echo.
    exit /b 1
)