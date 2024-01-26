import { AztecAddress } from "@aztec/aztec.js";

export class BetNote {
  owner: AztecAddress;
  round_id: bigint;
  bet: boolean;
  randomness: bigint;

  constructor(note: any) {
    this.owner = note.owner;
    this.round_id = note.round_id;
    this.bet = note.bet;
    this.randomness = note.randomness;
  }
}
