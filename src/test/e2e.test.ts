import {
  AccountWalletWithPrivateKey,
  AztecAddress,
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
  getUnsafeSchnorrAccount,
  Fq
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

const PHASE_BET = 1n;
const PHASE_WAIT_ORACLE_ANSWER = 2n;
const PHASE_CLAIM = 3n;

// Babyjubjub divinity data
const divinityPrivateKey =
  2360067582289791756090345803415031600606727745697750731963540090262281758098n;

// Resulting public key on the BJJ curve when deriving from the DIVINITY_PRIVATE_KEY declared above
// Use https://github.com/jat9292/babyjubjub-utils to generate new ones
const DIVINITY_PUBLIC_KEY_BJJ_X =
  17330617431291011652840919965771789495411317073490913928764661286424537084069n;
const DIVINITY_PUBLIC_KEY_BJJ_Y =
  12743939760321333065626220799160222400501486578575623324257991029865760346009n;
const DIVINITY_PUBLIC_KEY_BJJ = {
  point: { x: DIVINITY_PUBLIC_KEY_BJJ_X, y: DIVINITY_PUBLIC_KEY_BJJ_Y },
};

// Randomness have been generated using a modified babyjubjub-utils that prints the randomness used when encrypting.
const RANDOMNESS_INITIAL_ENCRYPTION =
  2127434375679321579932213798607732554355166199806066497941655719367141499766n;
const RANDOMNESS_USER_1 =
  1438319796528918033583393704730685046956217498280656265812575377511832574392n;
const RANDOMNESS_USER_2 =
  1048079536491508724972388093791272936112538204421938605612284921668780878715n;
const RANDOMNESS_USER_3 =
  2115925703451186072229956066949536779308650088120047035594563780397884741597n;
const RANDOMNESS_ARR = [
  RANDOMNESS_USER_1,
  RANDOMNESS_USER_2,
  RANDOMNESS_USER_3,
];

const FINAL_CUM_SUM_C1_X =
  3919606867997237668040567668233747244452711745206604584349608308343594620673n;
const FINAL_CUM_SUM_C1_Y =
  14742875759735887788510420745824939173336243957508133148437004653480301110834n;
const FINAL_CUM_SUM_C2_X =
  521687571595162779479180406855798846599524023215386831438765875476136529268n;
const FINAL_CUM_SUM_C2_Y =
  6438471728501791047453348744695539915081915500069492754704209849111324891174n;
const ENCRYPTED_TAIL_SUM = {
  C1: {
    point: {
      x: FINAL_CUM_SUM_C1_X,
      y: FINAL_CUM_SUM_C1_Y,
    },
  },
  C2: {
    point: {
      x: FINAL_CUM_SUM_C2_X,
      y: FINAL_CUM_SUM_C2_Y,
    },
  },
};

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
  const {
    PXE_URL = "http://localhost:8080",
    SANDBOX_URL = "http://localhost:8545",
  } = process.env;
  pxe = createPXEClient(PXE_URL);
  cc = await CheatCodes.create(SANDBOX_URL, pxe);

  [, [user, divinity, user2], deployer, user3] = await Promise.all([
    waitForSandbox(pxe),
    getSandboxAccountsWallets(pxe),
    createAccount(pxe),
    createAccount(pxe),
  ]);
  await initAztecJs();

  divinity = await getUnsafeSchnorrAccount(
    pxe,
    new Fq(divinityPrivateKey)
  ).waitDeploy();
}, 120_000);

describe("E2E Coin Toss", () => {
  let roundId = 0n;
  let bets: BetNote[];
  let betResult: number;
  let bettors: number = 0;
  let winners: number = 0;
  let claimAmount: bigint = 0n;

  // Setup: Deploy the contracts and mint tokens, ready for escrow
  beforeAll(async () => {
    // Deploy the token with the  house as a minter
    token = await TokenContract.deploy(deployer, deployer.getAddress())
      .send()
      .deployed();

    // Deploy the oracle
    const oracleReceipt = await PrivateOracleContract.deploy(
      deployer,
      token.address,
      ORACLE_FEE
    )
      .send()
      .wait();

    oracle = oracleReceipt.contract;

    // Mint the tokens
    await Promise.all(
      [deployer, user, user2, user3].map((account) =>
        mintTokenFor(account, deployer, MINT_TOKENS)
      )
    );

    // Deploy Coin Toss
    const coinTossReceipt = await CoinTossContract.deploy(
      deployer,
      divinity.getAddress(),
      DIVINITY_PUBLIC_KEY_BJJ,
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

  it("saves the public variables correctly", async () => {
    const _phaseLength = await coinToss.methods
      .get_phase_length_unconstrained()
      .view();
    const _betAmount = await coinToss.methods
      .get_bet_amount_unconstrained()
      .view();
    const _oracle = await coinToss.methods
      .get_oracle_address_unconstrained()
      .view();
    const _divinity = await coinToss.methods
      .get_divinity_address_unconstrained()
      .view();
    const _token = await coinToss.methods
      .get_token_address_unconstrained()
      .view();

    expect(new Fr(_token.address)).toStrictEqual(token.address);
    expect(new Fr(_oracle.address)).toStrictEqual(oracle.address);
    expect(AztecAddress.fromBigInt(_divinity.address)).toStrictEqual(
      divinity.getAddress()
    );
    expect(_betAmount).toBe(BET_AMOUNT);
    expect(Number(_phaseLength)).toBe(PHASE_LENGTH);
  });

  describe("start_next_round", () => {
    let currentTime: number;

    it("goes to the next round when called", async () => {
      // Get the current round id. It should be 0
      const currentRoundId = await coinToss.methods.get_round_id().view();
      expect(currentRoundId).toBe(roundId);

      currentTime = (await cc.eth.timestamp()) + 1;
      await cc.aztec.warp(currentTime);

      // Advance the round
      await coinToss.methods
        .start_next_round(RANDOMNESS_INITIAL_ENCRYPTION)
        .send()
        .wait();
      roundId++;

      // Get the current round id. It should be 0
      const nextRoundId = await coinToss.methods.get_round_id().view();
      expect(nextRoundId).toBe(roundId);
    });

    it("updates the phase end timestamp", async () => {
      const expectedTimestamp = currentTime + PHASE_LENGTH;
      const currentRound = await coinToss.methods
        .get_round_data(roundId)
        .view();
      expect(Number(currentRound.current_phase_end)).toBe(expectedTimestamp);
    });

    it("reverts when trying to advance a round and the previous one did not finish", async () => {
      let startNextRoundTx = coinToss.methods
        .start_next_round(RANDOMNESS_INITIAL_ENCRYPTION)
        .simulate();
      await expect(startNextRoundTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Current round not finished 'current_round_data.phase == Phase::CLAIM'"
      );
    });
  });

  describe("bet", () => {
    it("reverts if the round id is not the current one", async () => {
      bets = createThreeBetNotes();
      const unshieldNonce = Fr.random();
      const roundId = await coinToss
        .withWallet(user)
        .methods.get_round_id()
        .view();
      const wrongRoundId = roundId + 1n;

      const unshieldAction = await token
        .withWallet(user)
        .methods.unshield(
          user.getAddress(),
          coinToss.address,
          BET_AMOUNT,
          unshieldNonce
        );
      await createAuth(unshieldAction, user, coinToss.address);

      // Simulate the transaction
      const betTx = coinToss
        .withWallet(user)
        .methods.bet(
          bets[0].bet,
          wrongRoundId,
          bets[0].randomness,
          unshieldNonce
        )
        .simulate();
      await expect(betTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Round id mismatch 'current_round_id == round_id'"
      );
    });

    it.skip("reverts if the betting phase is over", async () => {
      // TODO: Test after functions that advance phases are introduced
    });

    it("mines the transaction", async () => {
      const unshieldNonce = Fr.random();

      // Create authwit so that cointoss can call unshield as the recipient
      const unshieldAction = await token
        .withWallet(user)
        .methods.unshield(
          user.getAddress(),
          coinToss.address,
          BET_AMOUNT,
          unshieldNonce
        );
      await createAuth(unshieldAction, user, coinToss.address);

      // Send the transaction
      const receipt = await coinToss
        .withWallet(user)
        .methods.bet(
          bets[0].bet,
          bets[0].round_id,
          bets[0].randomness,
          unshieldNonce
        )
        .send()
        .wait();
      expect(receipt.status).toBe("mined");
      winners++; // update only if bet == answer
      bettors++;
    });

    it("allows multiple users to bet", async () => {
      const unshieldNonce = Fr.random();

      // Create authwit so that cointoss can call unshield as the recipient
      const unshieldAction2 = await token
        .withWallet(user2)
        .methods.unshield(
          user2.getAddress(),
          coinToss.address,
          BET_AMOUNT,
          unshieldNonce
        );
      await createAuth(unshieldAction2, user2, coinToss.address);

      // Send the transaction
      const receipt2 = await coinToss
        .withWallet(user2)
        .methods.bet(
          bets[1].bet,
          bets[1].round_id,
          bets[1].randomness,
          unshieldNonce
        )
        .send()
        .wait();
      expect(receipt2.status).toBe("mined");
      winners++;
      bettors++;

      // Create authwit so that cointoss can call unshield as the recipient
      const unshieldAction3 = await token
        .withWallet(user3)
        .methods.unshield(
          user3.getAddress(),
          coinToss.address,
          BET_AMOUNT,
          unshieldNonce
        );
      await createAuth(unshieldAction3, user3, coinToss.address);

      // Send the transaction
      const receipt3 = await coinToss
        .withWallet(user3)
        .methods.bet(
          !bets[2].bet,
          bets[2].round_id,
          bets[2].randomness,
          unshieldNonce
        )
        .send()
        .wait();
      expect(receipt3.status).toBe("mined");
      bettors++;
    });

    it("nullifies randomness", async () => {
      const result = await coinToss
        .withWallet(user)
        .methods.is_round_randomness_nullified(
          bets[0].round_id,
          bets[0].randomness
        )
        .view({ from: user.getAddress() });
      expect(result).toBe(true);
    });

    it("increases public balance of coin toss by bet amount", async () => {
      const coinTossBalance = await token.methods
        .balance_of_public(coinToss.address)
        .view();
      // Because this is the first bet, the cointoss public balance previous to the bet is assumed to be 0.
      expect(coinTossBalance).toBe(BET_AMOUNT * BigInt(bettors));
    });

    it("reduces private balance of the user by bet amount", async () => {
      const userPrivateBalance = await token.methods
        .balance_of_private(user.getAddress())
        .view();
      expect(userPrivateBalance).toBe(MINT_TOKENS - BET_AMOUNT);
    });

    it("increases the amount of bettors", async () => {
      const roundData = await coinToss
        .withWallet(user)
        .methods.get_round_data(bets[0].round_id)
        .view();
      expect(roundData.bettors).toBe(BigInt(bettors));
    });

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
        owner: bets[0].owner,
        round_id: bets[0].round_id,
        bet: bets[0].bet,
        randomness: bets[0].randomness,
      };

      expect(bet).toEqual(expect.objectContaining(betNote));
    });
  });

  describe("roll", () => {
    let nonce = Fr.random();
    let callback;
    let betPhaseEnd: number;

    beforeAll(async () => {
      callback = [
        coinToss.address,
        roundId,
        FINAL_CUM_SUM_C1_X,
        FINAL_CUM_SUM_C1_Y,
        FINAL_CUM_SUM_C2_X,
        FINAL_CUM_SUM_C2_Y,
      ];
      claimAmount = (BigInt(bettors) * BET_AMOUNT) / BigInt(winners);

      // Create auth for deployer to escrow tokens to the oracle
      const escrowAction = token.methods.escrow(
        deployer.getAddress(),
        oracle.address,
        ORACLE_FEE,
        nonce
      );
      await createAuth(escrowAction, deployer, oracle.address);

      // Create auth for coin toss to create a question for the deployer
      const submitQuestionAction = oracle.methods.submit_question(
        deployer.getAddress(),
        roundId,
        divinity.getAddress(),
        nonce,
        callback
      );
      await createAuth(submitQuestionAction, deployer, coinToss.address);
    });

    it("reverts if the betting phase did not end", async () => {
      const rollTx = coinToss
        .withWallet(deployer)
        .methods.roll(roundId, nonce, ENCRYPTED_TAIL_SUM)
        .simulate();

      await expect(rollTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Bet phase not finished 'timestamp >= current_round_data.current_phase_end'"
      );
    });

    it("tx is mined", async () => {
      // Advance time
      const currentRound = await coinToss.methods
        .get_round_data(roundId)
        .view();
      betPhaseEnd = Number(currentRound.current_phase_end);
      await cc.aztec.warp(betPhaseEnd + 1);

      // Roll
      const rollReceipt = await coinToss
        .withWallet(deployer)
        .methods.roll(roundId, nonce, ENCRYPTED_TAIL_SUM)
        .send()
        .wait();

      expect(rollReceipt.status).toBe(TxStatus.MINED);
    });

    it("updates the round data correctly", async () => {
      const currentRoundId = await coinToss.methods.get_round_id().view();

      const phaseEnd = betPhaseEnd + 1 + PHASE_LENGTH;
      const storedRoundData = await coinToss.methods
        .get_round_data(currentRoundId)
        .view();

      expect(currentRoundId).toBe(roundId);
      expect(storedRoundData.phase).toEqual(PHASE_WAIT_ORACLE_ANSWER);
      expect(storedRoundData.current_phase_end).toEqual(BigInt(phaseEnd));
      expect(storedRoundData.bettors).toEqual(BigInt(bettors));
      expect(storedRoundData.claim_amount).toEqual(0n); // not initialized yet
    });
  });

  describe("oracle_callback", () => {
    let currentTime: number;

    it("tx gets mined", async () => {
      betResult = Number(bets[0].bet);

      currentTime = (await cc.eth.timestamp()) + 1;
      await cc.aztec.warp(currentTime);

      // Using winners parameter here as the bet result will be 1, therefore the plaintext will be those that bet TAILS (1).
      const receipt = await oracle
        .withWallet(divinity)
        .methods.submit_answer(roundId, deployer.getAddress(), [
          betResult,
          winners,
          divinityPrivateKey,
        ])
        .send()
        .wait();
      expect(receipt.status).toBe(TxStatus.MINED);
    });

    it("updates the round data", async () => {
      const currentRound = await coinToss.methods
        .get_round_data(roundId)
        .view();
      expect(currentRound.phase).toBe(PHASE_CLAIM);
      expect(currentRound.bettors).toBe(BigInt(bettors));
      expect(Number(currentRound.current_phase_end)).toBe(
        currentTime + PHASE_LENGTH
      );
      expect(currentRound.claim_amount).toBe(claimAmount);
    });

    it("updates the answer", async () => {
      const currentAnswer = await coinToss.methods.get_result(roundId).view();
      expect(Number(currentAnswer)).toBe(betResult);
    });

    it("reverts when called by someone else", async () => {
      const callbackTx = coinToss
        .withWallet(user)
        .methods.oracle_callback(
          [0n, 0n, 0n],
          [0n, 0n, 0n, 0n, 0n],
          divinity.getAddress()
        )
        .simulate();
      await expect(callbackTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Caller is not the oracle 'caller == oracle.address'"
      );
    });
  });

  describe.skip("claim", () => {
    let coinTossPublicBalanceBefore: bigint;
    let userPrivateBalanceBefore: bigint;

    it("tx gets mined", async () => {
      coinTossPublicBalanceBefore = await token.methods
        .balance_of_public(coinToss.address)
        .view();
      userPrivateBalanceBefore = await token.methods
        .balance_of_private(user.getAddress())
        .view();

      const receipt = await coinToss
        .withWallet(user)
        .methods.claim(roundId, claimAmount, bets[0].randomness)
        .send()
        .wait();
      expect(receipt.status).toBe(TxStatus.MINED);
    });

    it("nullifies bet note", async () => {
      const betNote = (
        await coinToss
          .withWallet(user)
          .methods.get_user_bets_unconstrained(0n)
          .view({ from: user.getAddress() })
      ).find(
        (noteObj: any) =>
          noteObj._value.randomness == bets[0].randomness &&
          noteObj._value.round_id == bets[0].round_id
      );

      expect(betNote).toBeUndefined();
    });

    it("reduces the public balance of the coin toss", async () => {
      const coinTossBalance = await token.methods
        .balance_of_public(coinToss.address)
        .view();
      expect(coinTossBalance).toBe(coinTossPublicBalanceBefore - claimAmount);
    });

    it("user can then claim the pending shield with the secret", async () => {
      const privateBalanceAfter = await token.methods
        .balance_of_private(user.getAddress())
        .view();
      expect(privateBalanceAfter).toBe(userPrivateBalanceBefore + claimAmount);
    });

    it("reverts when trying to claim without a bet note", async () => {
      const randomUser = await createAccount(pxe);
      const claimTx = coinToss
        .withWallet(randomUser)
        .methods.claim(roundId, claimAmount, bets[0].randomness)
        .simulate();
      await expect(claimTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: bet note not found 'false'"
      );
    });

    it("reverts when a user tries to claim more than claimAmount", async () => {
      const claimTx = coinToss
        .withWallet(user2)
        .methods.claim(roundId, claimAmount + 1n, bets[0].randomness)
        .simulate();
      await expect(claimTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Claim amount mismatch 'claimAmount == amount as u120'"
      );
    });

    it.skip("reverts if the phase is not claim", async () => {});

    it.skip("reverts if the user bet doesnt match the reported result", async () => {});

    it("allows all the winners to claim", async () => {
      const receipt = await coinToss
        .withWallet(user2)
        .methods.claim(roundId, claimAmount, bets[0].randomness)
        .send()
        .wait();
      expect(receipt.status).toBe(TxStatus.MINED);
    });
  });
});

// Create an array of mock bet notes
// TODO: allow for arbitrary notes when the different randomness dont have to be hardcoded
function createThreeBetNotes(): BetNote[] {
  let betNote: BetNote;
  let betNotes: BetNote[] = [];

  for (let i = 0; i < 3; i++) {
    betNote = new BetNote({
      owner: user.getAddress(),
      round_id: 1n,
      bet: true,
      randomness: RANDOMNESS_ARR[i],
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
        new Fr(DIVINITY_PUBLIC_KEY_BJJ.point.x),
        new Fr(DIVINITY_PUBLIC_KEY_BJJ.point.y),
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