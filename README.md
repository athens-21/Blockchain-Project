# Blockchain-Project
TrustLend — Minimal Decentralized Lending dApp

A minimal decentralized lending dApp front-end + smart contracts. Provides borrower and lender dashboards and supports a simple collateralized lending flow using TDAI token and ETH collateral.

Included Files

borrower11.html — Borrower dashboard
(Request loans, view own loans, make TDAI payments)

lender12.html — Lender dashboard
(View pending requests, fund loans, liquidations)

TDAI.sol — ERC20-like TDAI token contract (with faucet, approve, balance)

TrustLend.sol — Lending contract (requestLoan, fundLoan, makePayment, liquidate, payment history)

Features
Borrower

Request loans with ETH collateral

Auto-calculated minimum collateral (LTV logic inside UI)

Make loan payments in TDAI

Lender

Browse pending loan requests

Fund loans using TDAI

Monitor repayments and liquidations

Local Development Ready

Front-ends expect a local JSON-RPC (Ganache) at http://127.0.0.1:7545

Uses web3.js v1.x

TDAI faucet available for testing

Prerequisites

Node.js + npm

Hardhat or Truffle

Ganache (or other local Ethereum node) running at 127.0.0.1:7545

Git + GitHub account (optional)

Quick Local Setup (Hardhat)

Create project folder and initialize:

mkdir trustlend && cd trustlend
git init


Copy files (borrower11.html, lender12.html, TDAI.sol, TrustLend.sol) into project.

Install Hardhat:

npm init -y
npm install --save-dev hardhat
npx hardhat # choose "Create a basic sample project"


Add contracts under contracts/. Create a deploy script scripts/deploy.js:

const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  const TDAI = await hre.ethers.getContractFactory("TDAI");
  const tdai = await TDAI.deploy();
  await tdai.deployed();

  const TrustLend = await hre.ethers.getContractFactory("TrustLend");
  const trustlend = await TrustLend.deploy(tdai.address);
  await trustlend.deployed();

  console.log("TDAI:", tdai.address);
  console.log("TrustLend:", trustlend.address);
}

main().catch(e => { console.error(e); process.exit(1); });


Start Ganache at http://127.0.0.1:7545.

Deploy contracts:

npx hardhat run --network localhost scripts/deploy.js


Update HTML UIs with deployed addresses:

const TDAI_ADDRESS = "<deployed_tdai_address>";
const TRUSTLEND_ADDRESS = "<deployed_trustlend_address>";


Serve HTML locally:

npx http-server . -p 8080
# open http://localhost:8080/borrower11.html or lender12.html

Typical Flow (Local Testing)

Deploy TDAI and TrustLend.

Mint TDAI to lender account using TDAI.faucet.

Borrower opens borrower11.html, sets amount/collateral, and sends requestLoan (ETH collateral).

Lender opens lender12.html, views pending loans, approves & calls fundLoan (transfers TDAI to contract).

Borrower makes payments using TDAI (approve then makePayment).

Lender monitors payments and can liquidate if borrower defaults.
