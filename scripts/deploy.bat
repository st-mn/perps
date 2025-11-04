@echo off
REM Windows deployment script for Solana Perpetuals Program

setlocal EnableDelayedExpansion

set NETWORK=%1
set KEYPAIR_PATH=%2

if "%NETWORK%"=="" set NETWORK=devnet
if "%KEYPAIR_PATH%"=="" set KEYPAIR_PATH=%USERPROFILE%\.config\solana\id.json

echo 🚀 Deploying Solana Perpetuals Program to %NETWORK%...

REM Check if program is built
if not exist "target\deploy\simple_perps.so" (
    echo ❌ Program not built. Run scripts\build.bat first.
    exit /b 1
)

REM Check if keypair exists
if not exist "%KEYPAIR_PATH%" (
    echo ❌ Keypair not found at %KEYPAIR_PATH%
    echo 💡 Create a keypair with: solana-keygen new --outfile "%KEYPAIR_PATH%"
    exit /b 1
)

REM Set Solana config
echo ⚙️  Configuring Solana CLI...
solana config set --keypair "%KEYPAIR_PATH%"

if "%NETWORK%"=="devnet" (
    solana config set --url https://api.devnet.solana.com
    echo 💰 Airdropping SOL for deployment devnet only...
    solana airdrop 2 --commitment finalized || echo ⚠️  Airdrop may have failed, continuing...
) else if "%NETWORK%"=="testnet" (
    solana config set --url https://api.testnet.solana.com
) else if "%NETWORK%"=="mainnet" (
    solana config set --url https://api.mainnet-beta.solana.com
    echo ⚠️  DEPLOYING TO MAINNET! Make sure you have enough SOL for deployment.
) else (
    echo ❌ Invalid network: %NETWORK%. Use 'devnet', 'testnet', or 'mainnet'
    exit /b 1
)

REM Check balance
for /f "tokens=1" %%a in ('solana balance --commitment finalized') do set BALANCE=%%a
echo 💳 Wallet balance: %BALANCE% SOL

REM Deploy the program
echo 📤 Deploying program...
for /f "tokens=*" %%a in ('solana program deploy target/deploy/simple_perps.so --commitment finalized --output json') do set DEPLOY_OUTPUT=%%a

REM Extract Program ID (simplified - in practice you'd use a JSON parser)
echo %DEPLOY_OUTPUT% | findstr /C:"programId" >nul
if %ERRORLEVEL% equ 0 (
    REM Save a simple success indicator
    echo Deployment appears successful > program_deployed.txt
    echo ✅ Deployment successful!
    echo 🌐 Network: %NETWORK%
    echo 💾 Check program_deployed.txt for confirmation
    
    echo.
    echo 🎉 Your perpetuals program is now live!
    echo 📚 Next steps:
    echo    1. Create token accounts for collateral USDC/USDT
    echo    2. Initialize market state and positions
    echo    3. Test opening positions with your client application
) else (
    echo ❌ Deployment failed!
    exit /b 1
)