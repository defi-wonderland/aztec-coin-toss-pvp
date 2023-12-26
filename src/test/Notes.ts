import { AztecAddress } from "@aztec/aztec.js";

export class BetNote {
  owner: AztecAddress;
  bet_id: bigint;
  bet: boolean;
  escrow_randomness: bigint;

  constructor(note: any) {
    this.owner = AztecAddress.fromBigInt(
      note.owner.address || note.owner.asBigInt
    );
    this.bet_id = note.bet_id;
    this.bet = note.bet;
    this.escrow_randomness = note.escrow_randomness;
  }
}
