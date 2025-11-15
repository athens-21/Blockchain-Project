# Blockchain-Project

# TrustLend — Minimal Decentralized Lending dApp

TrustLend is a **minimal decentralized lending dApp** combining front-end dashboards and smart contracts for collateralized lending using ETH as collateral and TDAI tokens for repayments.  

The project includes:
- **borrower11.html** — Borrower dashboard: request loans, view your loans, make payments in TDAI
- **lender12.html** — Lender dashboard: view pending loan requests, approve/fund loans, monitor repayments, liquidate if needed
- **TDAI.sol** — Simple ERC20-like token contract with faucet, approve, and balance features for local testing
- **TrustLend.sol** — Main lending contract: requestLoan, fundLoan, makePayment, liquidate, view payment history

**Key Features**
- Borrowers can request loans with ETH collateral; minimum collateral is auto-calculated
- Lenders can browse pending requests, fund loans using TDAI, and monitor repayments
- Repayments are made in TDAI; lenders can liquidate loans if borrowers default

**Local Development**
- Supports Node.js + npm and Hardhat
- Works with Ganache or any local Ethereum node (`http://127.0.0.1:7545`)
- Front-ends use **web3.js v1.x**
- TDAI includes a faucet for testing

**Typical Workflow**
1. Deploy smart contracts: TDAI and TrustLend
2. Lender mints TDAI using the faucet for testing
3. Borrower opens `borrower11.html`, sets loan amount and collateral, and calls `requestLoan`
4. Lender opens `lender12.html`, views pending loans, approves, and funds the loan (`fundLoan`)
5. Borrower makes repayments in TDAI (`approve` → `makePayment`)
6. Lender monitors repayments and can liquidate if default occurs
