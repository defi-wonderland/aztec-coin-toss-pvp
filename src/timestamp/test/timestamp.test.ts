import {
    AccountWalletWithPrivateKey,
    CheatCodes,
    createPXEClient,
    getSandboxAccountsWallets,
    PXE,
    waitForSandbox
} from "@aztec/aztec.js";
  
  import { initAztecJs } from "@aztec/aztec.js/init";
  
  import { TimestampContract } from "../src/artifacts/Timestamp.js";
  
  const JITTER = 10n*60n; // 10 minutes

  // Global variables
  let pxe: PXE;
  let cc: CheatCodes;
  let timestamp: TimestampContract;
  let user: AccountWalletWithPrivateKey;
  
  // Setup: Set the sandbox up and get the accounts
  beforeAll(async () => {
    const { PXE_URL = "http://localhost:8080", SANDBOX_URL = "http://localhost:8545" } = process.env;
    pxe = createPXEClient(PXE_URL);
    cc = await CheatCodes.create(SANDBOX_URL, pxe);
  
    [, [user]] = await Promise.all([
      waitForSandbox(pxe),
      getSandboxAccountsWallets(pxe),
    ]);
    await initAztecJs();
  }, 120_000);
  
  describe("E2E Timestamp", () => {
  
    // Setup: Deploy the contracts and mint tokens, ready for escrow
    beforeAll(async () => {
      // Deploy the token with the  house as a minter
      timestamp = await TimestampContract.deploy(user)
        .send()
        .deployed();
    }, 200_000);
  
    it('passes when the timestamp provided equals the real one', async () => {
      const time = await nextTimestamp();
      await cc.aztec.warp(time);

      const validateTimestampTx = timestamp.withWallet(user).methods.validate_timestamp(time + 10, JITTER).simulate();
      await expect(validateTimestampTx).resolves.toBeDefined();
    })

    it('passes when the timestamp provided equals the real one with the max jitter', async () => {
      const time = await nextTimestamp();
      await cc.aztec.warp(time);
      
      const validateTimestampTx = timestamp.withWallet(user).methods.validate_timestamp(time + Number(JITTER) - 10, JITTER).simulate();
      await expect(validateTimestampTx).resolves.toBeDefined();
    })

    it('fails when the timestamp provided is in the past', async () => {
      const time = await nextTimestamp();
      await cc.aztec.warp(time);

      const validateTimestampTx = timestamp.withWallet(user).methods.validate_timestamp(time - 100000, JITTER).simulate();
      await expect(validateTimestampTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Past timestamp 'provided_timestamp >= timestamp'"
      );
    });

    it('fails when the timestamp provided is in the future', async () => {
      const time = await nextTimestamp();
      await cc.aztec.warp(time);

      const validateTimestampTx = timestamp.withWallet(user).methods.validate_timestamp(time + Number(JITTER) + 1, JITTER).simulate();
      await expect(validateTimestampTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Future timestamp 'provided_timestamp <= timestamp + jitter'"
      );
    });
  });

  const nextTimestamp = async () => {
    return await cc.eth.timestamp() + 1;
  }