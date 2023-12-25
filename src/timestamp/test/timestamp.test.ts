import {
    AccountWalletWithPrivateKey,
    createPXEClient,
    getSandboxAccountsWallets,
    PXE,
    waitForSandbox
} from "@aztec/aztec.js";
  
  import { initAztecJs } from "@aztec/aztec.js/init";
  
  import { TimestampContract } from "../src/artifacts/Timestamp.js";
  
  const JITTER = 60n; // 1 minute

  // Global variables
  let pxe: PXE;
  let timestamp: TimestampContract;
  let user: AccountWalletWithPrivateKey;
  
  // Setup: Set the sandbox up and get the accounts
  beforeAll(async () => {
    const { SANDBOX_URL = "http://localhost:8080" } = process.env;
    pxe = createPXEClient(SANDBOX_URL);
  
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
      const validateTimestampTx = timestamp.withWallet(user).methods.validate_timestamp(currentTimestamp(), JITTER).simulate();
      await expect(validateTimestampTx).resolves.toBeDefined();
    })

    it('passes when the timestamp provided equals the real one with the max jitter', async () => {
      const validateTimestampTx = timestamp.withWallet(user).methods.validate_timestamp(currentTimestamp() - Number(JITTER) + 10, JITTER).simulate();
      await expect(validateTimestampTx).resolves.toBeDefined();
    })

    it('fails when the timestamp provided is in the past', async () => {
      const validateTimestampTx = timestamp.withWallet(user).methods.validate_timestamp(currentTimestamp() - 1, JITTER).simulate();
      await expect(validateTimestampTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Future timestamp 'provided_timestamp <= timestamp'"
      );
    });

    it('fails when the timestamp provided is in the future', async () => {
      const validateTimestampTx = timestamp.withWallet(user).methods.validate_timestamp(currentTimestamp() + Number(JITTER) + 1, JITTER).simulate();
      await expect(validateTimestampTx).rejects.toThrow(
        "(JSON-RPC PROPAGATED) Assertion failed: Future timestamp 'provided_timestamp <= timestamp'"
      );
    });
  });

  const currentTimestamp = () => {
    return Math.floor(new Date().getTime() / 1000);
  }