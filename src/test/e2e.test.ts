import {
  AccountWalletWithPrivateKey,
  AztecAddress,
  BatchCall,
  CheatCodes,
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
  TxStatus,
  waitForSandbox,
} from "@aztec/aztec.js";

import { initAztecJs } from "@aztec/aztec.js/init";

import { BetNote } from "./Notes.js";
import { CoinTossContract } from "../artifacts/CoinToss.js";
import { TokenContract } from "../artifacts/token/Token.js";
import { PrivateOracleContract } from "../artifacts/oracle/PrivateOracle.js";

// Constants
const CONFIG_SLOT: Fr = new Fr(9);

// Oracle storage layout
const TOKEN_SLOT: Fr = new Fr(1);
const FEE_SLOT: Fr = new Fr(2);

const MINT_TOKENS = 100000n;

const ORACLE_FEE = 100n;
const BET_AMOUNT = 1337n;

const PHASE_LENGTH = 10 * 60; // 10 minutes

// Global variables
let pxe: PXE;
let cc: CheatCodes;
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
  const { PXE_URL = "http://localhost:8080", SANDBOX_URL = "http://localhost:8545" } = process.env;
  pxe = createPXEClient(PXE_URL);
  cc = await CheatCodes.create(SANDBOX_URL, pxe);

  [, [user, divinity, user2], deployer, user3] = await Promise.all([
    waitForSandbox(pxe),
    getSandboxAccountsWallets(pxe),
    createAccount(pxe),
    createAccount(pxe),
  ]);
  await initAztecJs();
}, 120_000);

describe("E2E Coin Toss", () => {

  let roundId = 0n;

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
      BET_AMOUNT,
      PHASE_LENGTH
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

  it('saves the public variables correctly', async () => {
    const _phaseLength = await coinToss.methods.get_phase_length_unconstrained().view();
    const _betAmount = await coinToss.methods.get_bet_amount_unconstrained().view();
    const _oracle = await coinToss.methods.get_oracle_address_unconstrained().view();
    const _divinity = await coinToss.methods.get_divinity_address_unconstrained().view();
    const _token = await coinToss.methods.get_token_address_unconstrained().view();
    
    expect(new Fr(_token.address)).toStrictEqual(token.address);
    expect(new Fr(_oracle.address)).toStrictEqual(oracle.address);
    expect(AztecAddress.fromBigInt(_divinity.address)).toStrictEqual(divinity.getAddress());
    expect(_betAmount).toBe(BET_AMOUNT);
    expect(Number(_phaseLength)).toBe(PHASE_LENGTH);
  })

  describe('start_next_round', () => {

    let currentTime: number;

    it('goes to the next round when called', async () => {
      // Get the current round id. It should be 0
      const currentRoundId = await coinToss.methods.get_round_id().view();
      expect(currentRoundId).toBe(roundId);

      currentTime = await cc.eth.timestamp() + 1;
      await cc.aztec.warp(currentTime);

      // Advance the round
      await coinToss.methods.start_next_round().send().wait();
      roundId++;

      // Get the current round id. It should be 0
      const nextRoundId = await coinToss.methods.get_round_id().view();
      expect(nextRoundId).toBe(roundId);
    });

    it('updates the phase end timestamp', async () => {
      const expectedTimestamp = currentTime + PHASE_LENGTH;
      const currentRound = await coinToss.methods.get_round_data(roundId).view();
      expect(Number(currentRound.current_phase_end)).toBe(expectedTimestamp)
    });

    it('reverts when trying to advance a round and the previous one did not finish', async () => {
      let startNextRoundTx = coinToss.methods.start_next_round().simulate();
      await expect(startNextRoundTx)
        .rejects
        .toThrow("(JSON-RPC PROPAGATED) Assertion failed: Current round not finished 'current_round_data.phase >= Phase::REVEAL'");
    });
  });

  describe('roll', () => {
    let nonce = Fr.random();
    let callback;
    let betPhaseEnd: number;
    
    beforeAll(async () => {
      callback = [coinToss.address, roundId, 0, 0, 0, 0];

      // Create auth for user to escrow tokens to the oracle
      const escrowAction = token.methods.escrow(user.getAddress(), oracle.address, ORACLE_FEE, nonce);
      await createAuth(escrowAction, user, oracle.address);

      // Create auth for coin toss to create a question for the user
      const submitQuestionAction = oracle.methods.submit_question(user.getAddress(), roundId, divinity.getAddress(), nonce, callback);
      await createAuth(submitQuestionAction, user, coinToss.address);
    });

    it('reverts if the betting phase did not end', async () => {
      const rollTx = coinToss.withWallet(user).methods.roll(roundId, nonce).simulate();
      await expect(rollTx).rejects.toThrow("(JSON-RPC PROPAGATED) Assertion failed: Bet phase not finished 'timestamp >= current_round_data.current_phase_end'");
    });
    
    it('tx is mined', async () => {
      // Advance time
      const currentRound = await coinToss.methods.get_round_data(roundId).view();
      betPhaseEnd = Number(currentRound.current_phase_end);
      await cc.aztec.warp(betPhaseEnd + 1);

      // Roll
      const rollReceipt = await coinToss.withWallet(user).methods.roll(roundId, nonce).send().wait();
      expect(rollReceipt.status).toBe(TxStatus.MINED);
    })

    it('updated the round data', async () => {
      const currentRound = await coinToss.methods.get_round_data(roundId).view();
      expect(currentRound.phase).toBe(2n);
      expect(Number(currentRound.current_phase_end)).toBe(betPhaseEnd + 1 + PHASE_LENGTH);
    });
  });
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