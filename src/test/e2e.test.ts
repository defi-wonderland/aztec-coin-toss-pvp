import {
  AccountWalletWithPrivateKey,
  AztecAddress,
  BatchCall,
  computeAuthWitMessageHash,
  computeMessageSecretHash,
  ContractFunctionInteraction,
  createAccount,
  createPXEClient,
  ExtendedNote,
  Fr,
  getSandboxAccountsWallets,
  Note,
  PXE,
  TxHash,
  waitForSandbox,
} from "@aztec/aztec.js";

import { initAztecJs } from "@aztec/aztec.js/init";

import { BetNote, ResultNote } from "./Notes.js";
import { CoinTossContract } from "../artifacts/CoinToss.js";
import { TokenContract } from "../artifacts/token/Token.js";
import { PrivateOracleContract } from "../artifacts/oracle/PrivateOracle.js";

// Constants
const CONFIG_SLOT: Fr = new Fr(1);

// Oracle storage layout
const TOKEN_SLOT: Fr = new Fr(1);
const FEE_SLOT: Fr = new Fr(2);

const MINT_TOKENS = 100000n;

const ORACLE_FEE = 100n;
const BET_AMOUNT = 1337n;

// Global variables
let pxe: PXE;
let coinToss: CoinTossContract;
let token: TokenContract;
let oracle: PrivateOracleContract;

let user: AccountWalletWithPrivateKey;
let user2: AccountWalletWithPrivateKey;
let user3: AccountWalletWithPrivateKey;
let divinity: AccountWalletWithPrivateKey;
let deployer: AccountWalletWithPrivateKey;

// Setup: Set the sandbox up and get the accounts
beforeAll(async () => {
  const { SANDBOX_URL = "http://localhost:8080" } = process.env;
  pxe = createPXEClient(SANDBOX_URL);

  [, [user, divinity, user2], deployer, user3] = await Promise.all([
    waitForSandbox(pxe),
    getSandboxAccountsWallets(pxe),
    createAccount(pxe),
    createAccount(pxe),
  ]);
  await initAztecJs();
}, 120_000);

describe("E2E Coin Toss", () => {

  // Setup: Deploy the contracts and mint tokens, ready for escrow
  beforeAll(async () => {
    // Deploy the token with the  house as a minter
    token = await TokenContract.deploy(deployer, deployer.getAddress())
      .send()
      .deployed();

    // Deploy the oracle
    const oracleReceipt = await PrivateOracleContract.deploy(deployer, token.address, ORACLE_FEE)
    .send()
    .wait();

    oracle = oracleReceipt.contract;

    // Mint the tokens
    await mintTokenFor(user, deployer, MINT_TOKENS);

    // Deploy Coin Toss
    const coinTossReceipt = await CoinTossContract.deploy(
      deployer,
      divinity.getAddress(),
      oracle.address,
      token.address,
      BET_AMOUNT
    )
      .send()
      .wait();

    coinToss = coinTossReceipt.contract;

    // Add the contract public key to the PXE
    await pxe.registerRecipient(coinToss.completeAddress);
    await pxe.registerRecipient(oracle.completeAddress);

    await addFeeAndTokenNotesToPxe(user.getAddress(), oracleReceipt.txHash);

    // Add all address notes to pxe
    await addConfigNotesToPxe(
      user.getAddress(),
      coinToss.address,
      coinTossReceipt.txHash
    );
  }, 200_000);

  it('works', () => {
    expect(true).toBe(true);
  })
});

// Create an array of mock bet notes
function createUserBetNotes(number: number = 3): BetNote[] {
  let betNote: BetNote;
  let betNotes: BetNote[] = [];

  for (let i = 0; i < number; i++) {
    betNote = new BetNote({
      owner: user.getAddress(),
      bet_id: Fr.random().toBigInt(),
      bet: !!(i % 2), // 0: Heads, 1: Tails
    });

    betNotes.push(betNote);
  }

  return betNotes;
}

// Add the config notes to the PXE
const addFeeAndTokenNotesToPxe = async (
  user: AztecAddress,
  txHash: TxHash
) => {
  await pxe.addNote(
    new ExtendedNote(
      new Note([new Fr(ORACLE_FEE)]),
      user,
      oracle.address,
      FEE_SLOT,
      txHash
    )
  );

  await pxe.addNote(
    new ExtendedNote(
      new Note([new Fr(token.address.toBigInt())]),
      user,
      oracle.address,
      TOKEN_SLOT,
      txHash
    )
  );
};

// Add the config notes to the PXE
const addConfigNotesToPxe = async (
  user: AztecAddress,
  contract: AztecAddress,
  txHash: TxHash
) => {
  const divinityAsFr = divinity.getAddress().toField();
  const privateOracleAsFr = oracle.address.toField();
  const tokenAsFr = token.address.toField();
  const betAmountAsFr = new Fr(BET_AMOUNT);

  await pxe.addNote(
    new ExtendedNote(
      new Note([
        divinityAsFr,
        privateOracleAsFr,
        tokenAsFr,
        betAmountAsFr,
      ]),
      user,
      contract,
      CONFIG_SLOT,
      txHash
    )
  );
};

// Add the pending shield note to the PXE
const addPendingShieldNoteToPXE = async (
  account: AccountWalletWithPrivateKey,
  amount: bigint,
  secretHash: Fr,
  txHash: TxHash
) => {
  const storageSlot = new Fr(5); // The storage slot of `pending_shields` is 5.

  await pxe.addNote(
    new ExtendedNote(
      new Note([new Fr(amount), secretHash]),
      account.getAddress(),
      token.address,
      storageSlot,
      txHash
    )
  );
};

// Mint tokens for an account
const mintTokenFor = async (
  account: AccountWalletWithPrivateKey,
  minter: AccountWalletWithPrivateKey,
  amount: bigint
) => {
  // Mint private tokens
  const secret = Fr.random();
  const secretHash = await computeMessageSecretHash(secret);

  const recipt = await token
    .withWallet(minter)
    .methods.mint_private(amount, secretHash)
    .send()
    .wait();

  await addPendingShieldNoteToPXE(minter, amount, secretHash, recipt.txHash);

  await token
    .withWallet(minter)
    .methods.redeem_shield(account.getAddress(), amount, secret)
    .send()
    .wait();
};

// Create an authWitness for a specific action
const createAuth = async (
  action: ContractFunctionInteraction,
  approver: AccountWalletWithPrivateKey,
  caller: AztecAddress
) => {
  // We need to compute the message we want to sign and add it to the wallet as approved
  const messageHash = computeAuthWitMessageHash(caller, action.request());

  // Both wallets are connected to same node and PXE so we could just insert directly using
  // await wallet.signAndAddAuthWitness(messageHash, );
  // But doing it in two actions to show the flow.
  const witness = await approver.createAuthWitness(messageHash);
  await approver.addAuthWitness(witness);
};