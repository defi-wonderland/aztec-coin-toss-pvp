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

import { BetNote, RevealNote } from "./Notes.js";
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
  let firstBet: BetNote;
  let answer: number;

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

  describe('bet', () => {
    it("reverts if the round id is not the current one", async () => {
      firstBet = createUserBetNotes(1)[0];
      const unshieldNonce = Fr.random();
      const roundId = await coinToss.withWallet(user).methods.get_round_id().view();
      const wrongRoundId = roundId + 1n

      const unshieldAction = await token.withWallet(user).methods.unshield(user.getAddress(), coinToss.address, BET_AMOUNT, unshieldNonce);
      await createAuth(unshieldAction, user, coinToss.address);

      // Simulate the transaction
      const betTx = coinToss.withWallet(user).methods.bet(firstBet.bet, wrongRoundId, firstBet.randomness, unshieldNonce).simulate();
      await expect(betTx).rejects.toThrow("(JSON-RPC PROPAGATED) Assertion failed: Round id mismatch 'current_round_id == round_id'");    
    })

    it.skip("reverts if the betting phase is over", async () => {
      // TODO: Test after functions that advance phases are introduced
    })

    it("mines the transaction", async () => {
      const unshieldNonce = Fr.random();

      // Create authwit so that cointoss can call unshield as the recipient
      const unshieldAction = await token.withWallet(user).methods.unshield(user.getAddress(), coinToss.address, BET_AMOUNT, unshieldNonce);
      await createAuth(unshieldAction, user, coinToss.address);
      
      // Send the transaction
      const receipt = await coinToss.withWallet(user).methods.bet(firstBet.bet, firstBet.round_id, firstBet.randomness, unshieldNonce).send().wait()
      expect(receipt.status).toBe("mined");
    })

    it("nullifies randomness", async () => {
      const result = await coinToss.withWallet(user).methods.is_round_randomness_nullified(firstBet.round_id, firstBet.randomness).view({from: user.getAddress()});
      expect(result).toBe(true);
    })

    it("increases public balance of coin toss by bet amount", async () => {
      const coinTossBalance = await token.methods.balance_of_public(coinToss.address).view();
      // Because this is the first bet, the cointoss public balance previous to the bet is assumed to be 0.
      expect(coinTossBalance).toBe(BET_AMOUNT);
    })

    it("reduces private balance of the user by bet amount", async () => {
      const userPrivateBalance = await token.methods.balance_of_private(user.getAddress()).view();
      expect(userPrivateBalance).toBe(MINT_TOKENS - BET_AMOUNT);
    })

    it("increases the amount of bettors", async () => {
      const roundData = await coinToss.withWallet(user).methods.get_round_data(firstBet.round_id).view();
      expect(roundData.bettors).toBe(1n);
    })

    it("creates a bet note for the user with the correct parameters", async () => {
      const bet: BetNote = new BetNote(
        (
          await coinToss
            .withWallet(user)
            .methods.get_user_bets_unconstrained(0n)
            .view({ from: user.getAddress() })
        )[0]._value
      );

      // Check: Compare the note's data with the expected values
      const betNote: BetNote = {
        owner: firstBet.owner,
        round_id: firstBet.round_id,
        bet: firstBet.bet,
        randomness: firstBet.randomness
      };

      expect(bet).toEqual(expect.objectContaining(betNote));
    })
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

  describe('oracle_callback', () => {
    let currentTime: number;

    it('tx gets mined', async () => {
      answer = Number(firstBet.bet);

      currentTime = await cc.eth.timestamp() + 1;
      await cc.aztec.warp(currentTime);

      const receipt = await oracle.withWallet(divinity).methods.submit_answer(roundId, user.getAddress(), answer).send().wait();
      expect(receipt.status).toBe(TxStatus.MINED);
    });

    it('updates the round data', async () => {
      const currentRound = await coinToss.methods.get_round_data(roundId).view();
      expect(currentRound.phase).toBe(3n);
      expect(currentRound.bettors).toBe(1n);
      expect(Number(currentRound.current_phase_end)).toBe(currentTime + PHASE_LENGTH);
    });

    it('updates the answer', async () => {
      const currentAnswer = await coinToss.methods.get_result(roundId).view();
      expect(Number(currentAnswer)).toBe(answer);
    });

    it('reverts when called by someone else', async () => {
      const callbackTx = coinToss.withWallet(user).methods.oracle_callback(0n, [0n,0n,0n,0n,0n]).simulate();
      await expect(callbackTx)
        .rejects
        .toThrow("(JSON-RPC PROPAGATED) Assertion failed: Caller is not the oracle 'caller == oracle.address'");
    });
  });

  describe('reveal', () => {
    it('tx gets mined', async () => {
      const receipt = await coinToss.withWallet(user).methods.reveal(roundId, firstBet.randomness).send().wait();
      expect(receipt.status).toBe(TxStatus.MINED);
    });

    it('nullifies bet note', async () => {
      const betNote = (
        await coinToss
          .withWallet(user)
          .methods.get_user_bets_unconstrained(0n)
          .view({ from: user.getAddress() })
      ).find((noteObj: any) => noteObj._value.randomness == firstBet.randomness && noteObj._value.round_id == firstBet.round_id);

      expect(betNote).toBeUndefined();
    });

    it('creates reveal note for the user', async () => {
      const revealNote = new RevealNote(
        (
          await coinToss
            .withWallet(user)
            .methods.get_reveal_notes_unconstrained(0n)
            .view({ from: user.getAddress() })
        )[0]._value
      );

      // Check: Compare the note's data with the expected values
      const expectedRevealNote: RevealNote = {
        owner: firstBet.owner,
        round_id: roundId,
        randomness: firstBet.randomness
      };

      expect(expectedRevealNote).toEqual(expect.objectContaining(revealNote));
    });

    it('increases reveal count in the round data', async () => {
      const currentRound = await coinToss.methods.get_round_data(roundId).view();
      expect(currentRound.reveals_count).toBe(1n);
    });

    it('reverts if there is no matching bet note', async () => {
      const revealTx = coinToss.withWallet(user).methods.reveal(roundId, firstBet.randomness).simulate();
      await expect(revealTx)
      .rejects
      .toThrow("(JSON-RPC PROPAGATED) Assertion failed: Bet note not found 'false'");
    });

    it.skip('reverts if the round id is incorrect', async () => {
    });

    it.skip('reverts if the phase is not reveal', async () => {
    });

    it.skip('reverts if the user bet doesnt match the reported result', async () => {
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
      round_id: 1n,
      bet: !!(i % 2), // 0: Heads, 1: Tails
      randomness: Fr.random().toBigInt(),
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