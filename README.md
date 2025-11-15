# Blockchain-Project
TrustLend — Minimal dApp (Borrower + Lender UIs)

Short description
A minimal decentralized lending dApp front-end + smart contract sources. Includes two front-end dashboards (borrower and lender) and smart contracts for a simple collateralized lending flow using TDAI token and ETH collateral.

What’s included

borrower11.html — Borrower dashboard (request loan, view own loans, make TDAI payments). 

borrower11

lender12.html — Lender dashboard (view pending requests, fund loans, liquidations). 

lender12

TDAI.sol — ERC20-like TDAI token contract (faucet, approve, balance). (uploaded)

TrustLend.sol — Main lending contract (requestLoan, fundLoan, makePayment, liquidate, payment history). (uploaded)

Quick features

Borrower: request loan with ETH collateral, auto-calculated minimum collateral (example LTV logic inside UI).

Lender: browse pending loan requests, approve/fund loan using TDAI.

Local development ready: UIs expect a local JSON-RPC (Ganache) at http://127.0.0.1:7545 and use web3 v1.x.

Example token faucet available in TDAI.sol for local testing.

Prerequisites (local dev)

Node.js + npm

Hardhat or Truffle (example steps below use Hardhat)

Ganache (or any local Ethereum node) running on 127.0.0.1:7545

Basic Git + GitHub account

Quick local setup (recommended using Hardhat)

Create project folder and initialize:

mkdir trustlend && cd trustlend
git init


Copy the provided files (borrower11.html, lender12.html, TDAI.sol, TrustLend.sol) into the repository.

Install Hardhat:

npm init -y
npm install --save-dev hardhat
npx hardhat # choose "Create a basic sample project"


Put the .sol files under contracts/ and update sample scripts or create a deploy script scripts/deploy.js to deploy TDAI then TrustLend. Example (very short outline):

// scripts/deploy.js (outline)
const hre = require("hardhat");
async function main(){
  const [deployer] = await hre.ethers.getSigners();
  const TDAI = await hre.ethers.getContractFactory("TDAI");
  const tdai = await TDAI.deploy(); await tdai.deployed();
  const TrustLend = await hre.ethers.getContractFactory("TrustLend");
  const trustlend = await TrustLend.deploy(tdai.address); await trustlend.deployed();
  console.log("TDAI:", tdai.address, "TrustLend:", trustlend.address);
}
main().catch(e=>{console.error(e);process.exit(1)});


Start Ganache (GUI or CLI) so chain is available at http://127.0.0.1:7545. Use same accounts from Ganache in your UIs.

Deploy:

npx hardhat run --network localhost scripts/deploy.js


Update borrower11.html / lender12.html constants TDAI_ADDRESS and TRUSTLEND_ADDRESS with the deployed addresses.

Serve the HTML locally (simple static server), e.g.:

npx http-server . -p 8080
# open http://localhost:8080/borrower11.html or lender12.html

Typical flow (local testing)

Deploy TDAI and TrustLend.

Use TDAI.faucet (if available) to mint TDAI to lender account.

Borrower opens borrower11.html, sets amount/collateral and sends requestLoan (pays ETH collateral).

Lender opens lender12.html, sees pending loans, approves & calls fundLoan (which transfers TDAI to the contract).

Borrower makes payments using TDAI (approve then makePayment), lender monitors and can liquidate if default.
