use dep::aztec::types::type_serialization::TypeSerializationInterface;

mod Phase {
    global BETTING: u120 = 1;
    global AWAITING_ANSWER: u120 = 2;
    global CLAIM: u120 = 3;
}

struct RoundData {
    phase: u120, 
    current_phase_end: u120, 
    bettors: u40,
    claim_amount: u120,
}

impl RoundData {
    pub fn new(
        _phase: u120,
        _current_phase_end: u120,
        _bettors: u40,
        _claim_amount: u120,
    ) -> Self {
        Self {
            phase: _phase,
            current_phase_end: _current_phase_end,
            bettors: _bettors,
            claim_amount: _claim_amount,
        }
    }

    pub fn add_bettor(round_data: RoundData) -> Self {
        Self {
            phase: round_data.phase,
            current_phase_end: round_data.current_phase_end,
            bettors: round_data.bettors + 1,
            claim_amount: round_data.claim_amount,
        }
    }

    pub fn increase_reveal_count(round_data: RoundData) -> Self {
        Self {
            phase: round_data.phase,
            current_phase_end: round_data.current_phase_end,
            bettors: round_data.bettors,
            claim_amount: round_data.claim_amount,
        }
    }
}

global ROUND_DATA_SERIALIZED_LEN: Field = 4;

fn deserializeRoundData(fields: [Field; ROUND_DATA_SERIALIZED_LEN]) -> RoundData {
    RoundData{phase: fields[0] as u120, current_phase_end: fields[1] as u120, bettors: fields[2] as u40, claim_amount: fields[3] as u120}
}

fn serializeRoundData(value: RoundData) -> [Field; ROUND_DATA_SERIALIZED_LEN] {
    [value.phase as Field, value.current_phase_end as Field, value.bettors as Field, value.claim_amount as Field]
}

global RoundDataSerializationMethods = TypeSerializationInterface {
    deserialize: deserializeRoundData,
    serialize: serializeRoundData,
};