import { AztecAddress } from "@aztec/aztec.js";

export class BetNote {
  owner: AztecAddress;
  round_id: bigint;
  bet: boolean;
  randomness: bigint;

  constructor(note: any) {
    this.owner = AztecAddress.fromBigInt(
      note.owner.address || note.owner.asBigInt
    );
    this.round_id = note.round_id;
    this.bet = note.bet;
    this.randomness = note.randomness;
  }
}

export class RevealNote {
  owner: AztecAddress;
  round_id: bigint;
  randomness: bigint;

  constructor(note: any) {
    this.owner = AztecAddress.fromBigInt(
      note.owner.address || note.owner.asBigInt
    );
    this.round_id = note.round_id;
    this.randomness = note.randomness;
  }
}
