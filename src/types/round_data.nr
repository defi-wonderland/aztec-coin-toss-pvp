use dep::aztec::types::type_serialization::TypeSerializationInterface;

/// @notice Module containing the phases composing each round
/// @dev Hacky way to imitate an Enum type
/// @member BETTING: The phase during which users can bet
/// @member AWAITING_ANSWER: The phase during which the contract is waiting for the answer of the divinity
/// @member CLAIM: The phase during winners can claim their winnings
mod Phase {
    global BETTING: u120 = 1;
    global AWAITING_ANSWER: u120 = 2;
    global CLAIM: u120 = 3;
}

/// @notice Struct containing all the data of a round
/// @member phase: The current phase of the round
/// @member current_phase_end: The timestamp at which the current phase ends
/// @member bettors: The number of bettors in the round
/// @member claim_amount: The amount winners can claim
struct RoundData {
    phase: u120, 
    current_phase_end: u120, 
    bettors: u40,
    claim_amount: u120,
}

impl RoundData {

    /// @notice Creates a new RoundData struct
    /// @param _phase: The current phase of the round
    /// @param _current_phase_end: The timestamp at which the current phase ends
    /// @param _bettors: The number of bettors in the round
    /// @param _claim_amount: The amount winners can claim
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

    /// @notice Updates the number of bettors of a given round
    /// @param round_data: The RoundData struct to update
    pub fn add_bettor(round_data: RoundData) -> Self {
        Self {
            phase: round_data.phase,
            current_phase_end: round_data.current_phase_end,
            bettors: round_data.bettors + 1,
            claim_amount: round_data.claim_amount,
        }
    }
}

global ROUND_DATA_SERIALIZED_LEN: Field = 4;

/// @notice Deserializes a slice of Field elements into a RoundData struct
/// @param fields: The slice of Field elements to deserialize
fn deserializeRoundData(fields: [Field; ROUND_DATA_SERIALIZED_LEN]) -> RoundData {
    RoundData{phase: fields[0] as u120, current_phase_end: fields[1] as u120, bettors: fields[2] as u40, claim_amount: fields[3] as u120}
}

/// @notice Serializes a RoundData struct into a slice of Field elements
/// @param value: The RoundData struct to serialize
fn serializeRoundData(value: RoundData) -> [Field; ROUND_DATA_SERIALIZED_LEN] {
    [value.phase as Field, value.current_phase_end as Field, value.bettors as Field, value.claim_amount as Field]
}

global RoundDataSerializationMethods = TypeSerializationInterface {
    deserialize: deserializeRoundData,
    serialize: serializeRoundData,
};