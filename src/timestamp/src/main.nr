contract Timestamp {

    use dep::aztec::context::Context;

    #[aztec(private)]
    fn constructor() {
    }

    #[aztec(public)]
    fn validate_timestamp(provided_timestamp: u120, jitter: u120) {
        let timestamp = context.timestamp() as u120;
        assert(provided_timestamp <= timestamp, "Future timestamp");
        assert(provided_timestamp >= timestamp - jitter, "Past timestamp");
    }

    unconstrained fn compute_note_hash_and_nullifier(contract_address: Field, nonce: Field, storage_slot: Field, serialized_note: [Field; 0]) -> [Field; 4] {
        [0,0,0,0]
    }
}