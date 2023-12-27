/////////////////////////////////////////////////////////////////////
//                             Imports                             //
/////////////////////////////////////////////////////////////////////

use dep::aztec::{
    context::PrivateContext,
    log::emit_encrypted_log,
    note::{
        note_header::NoteHeader,
        note_interface::NoteInterface,
        utils::compute_note_hash_for_read_or_nullify,
    },
    oracle::{
        get_public_key::get_public_key,
        get_secret_key::get_secret_key,
        notes::check_nullifier_exists,
        notes::check_nullifier_exists_oracle,
        rand::rand,
    },
    types::address::AztecAddress
};

use dep::protocol_types::{
    constants::EMPTY_NULLIFIED_COMMITMENT,
};

use dep::std::option::Option;


/////////////////////////////////////////////////////////////////////
//                              Class                              //
/////////////////////////////////////////////////////////////////////

/// @notice A note that represents a given bet, of a given user
/// @member owner The owner of the note
/// @member round_id The id of the round this bet is placed on
/// @member bet The bet outcome given by the user (true or false)
/// @member header The note header
struct BetNote {
    owner: AztecAddress,
    round_id: Field,
    bet: bool, // Heads is 0 (False). Tails is 1 (True).
    randomness: Field,
    header: NoteHeader
}

global BET_NOTE_LEN: Field = 4;

impl BetNote {
    /////////////////////////////////////////////////////////////////////
    //                         Public methods                          //
    /////////////////////////////////////////////////////////////////////

    /// @notice Bet note constructor
    /// @param _context The currenct context, used to push the round_id nullifier in order to ensure uniqueness
    /// @param _owner The owner of the note
    /// @param _bet The bet outcome given by the user (true or false, representing head or tail)
    /// @param _round_id The id of the bet (randomly generated, by reusing the escrow randomness)
    /// @param _randomness An extra randomness field, often generated during the function execution and not known beforehand.
    ///                    Used for linking to other notes, identifaction and nullification.
    pub fn new(_context: &mut PrivateContext, _owner: AztecAddress, _round_id: Field, _bet: bool, _randomness: Field) -> Self {
        // Nullify round id and randomness combination
        let compute_initialization_nullifier = BetNote::generate_round_randomness_nullifier;
        let nullifier = compute_initialization_nullifier(_round_id, _randomness);
        _context.push_new_nullifier(nullifier, EMPTY_NULLIFIED_COMMITMENT);

        BetNote {
            owner: _owner,
            round_id: _round_id,
            bet: _bet,
            randomness: _randomness,
            header: NoteHeader::empty(),
        }
    }

    /// @notice Bet note round_id nullifying generator
    /// @param _round_id The id of the bet to nullify
    /// @param _randomness User defined randomness for a given bet
    pub fn generate_round_randomness_nullifier(_round_id: Field, _randomness: Field) -> Field {
        dep::std::hash::pedersen_hash([_round_id, _randomness])
    }

    /// @notice Bet note round_id initialization checker. Checks whether the round_id and randomness combination was added to the nullifying tree
    /// @param _round_id The round id of the bet to check for nullification status
    /// @param _randomness The randomness of the bet to check for nullification status
    unconstrained pub fn is_round_randomness_nullified(_round_id: Field, _randomness: Field) -> bool {
        let compute_initialization_nullifier = BetNote::generate_round_randomness_nullifier;
        let nullifier = compute_initialization_nullifier(_round_id, _randomness);
        check_nullifier_exists(nullifier)
    }

    /////////////////////////////////////////////////////////////////////
    //                        Internal methods                         //
    /////////////////////////////////////////////////////////////////////

    /// @notice Serializes the note
    fn serialize(self) -> [Field; BET_NOTE_LEN] {
        [self.owner.address, self.round_id, self.bet as Field, self.randomness]
    }

    /// @notice Deserializes the note
    fn deserialize(preimage: [Field; BET_NOTE_LEN]) -> Self {
        BetNote {
            owner: AztecAddress::new(preimage[0]),
            round_id: preimage[1],
            bet: preimage[2] as bool,
            randomness: preimage[3],
            header: NoteHeader::empty(),
        }
    }

    /// @notice Computes the note hash of the note
    fn compute_note_hash(self) -> Field {
        dep::std::hash::pedersen_hash([
            self.owner.address,
            self.round_id,
            self.bet as Field,
            self.randomness
        ])
    }

    /// @notice Computes the nullifier of the note
    /// @dev    This is a pretty standard nullifier computation, using the round_id as the key
    fn compute_nullifier(self) -> Field {
        let note_hash_for_nullify = compute_note_hash_for_read_or_nullify(BetNoteMethods, self);
        let nullifier_key = self.round_id;

        dep::std::hash::pedersen_hash([
            note_hash_for_nullify,
            nullifier_key,
        ])
    }

    /// @notice Sets the note header
    fn set_header(&mut self, header: NoteHeader) {
        self.header = header;
    }

    /// @notice Emit the note creation event using the owner public key
    fn broadcast(self, context: &mut PrivateContext, slot: Field) {
        let encryption_pub_key = get_public_key(self.owner.address);
        emit_encrypted_log(
            context,
            (*context).this_address(),
            slot,
            encryption_pub_key,
            self.serialize(),
        );
    }
}

/////////////////////////////////////////////////////////////////////
//                         Global methods                          //
/////////////////////////////////////////////////////////////////////

fn deserialize(preimage: [Field; BET_NOTE_LEN]) -> BetNote {
    BetNote::deserialize(preimage)
}

fn serialize(note: BetNote) -> [Field; BET_NOTE_LEN] {
    note.serialize()
}

fn compute_note_hash(note: BetNote) -> Field {
    note.compute_note_hash()
}

fn compute_nullifier(note: BetNote) -> Field {
    note.compute_nullifier()
}

fn get_header(note: BetNote) -> NoteHeader {
    note.header
}

fn set_header(note: &mut BetNote, header: NoteHeader) {
    note.set_header(header)
}

fn broadcast(context: &mut PrivateContext, slot: Field, note: BetNote) {
    note.broadcast(context, slot);
}

global BetNoteMethods = NoteInterface {
    deserialize,
    serialize,
    compute_note_hash,
    compute_nullifier,
    get_header,
    set_header,
    broadcast,
};