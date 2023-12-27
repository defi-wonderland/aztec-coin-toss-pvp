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
/// @member header The note header
struct RevealNote {
    owner: AztecAddress,
    round_id: Field,
    randomness: Field,
    header: NoteHeader
}

global REVEAL_NOTE_LEN: Field = 3;

impl RevealNote {
    /////////////////////////////////////////////////////////////////////
    //                         Public methods                          //
    /////////////////////////////////////////////////////////////////////

    /// @notice Reveal note constructor
    /// @param _owner The owner of the note
    /// @param _round_id The round id of the bet
    /// @param _randomness An extra randomness field. Used for linking to other notes, identifaction and nullification.
    pub fn new(_owner: AztecAddress, _round_id: Field, _randomness: Field) -> Self {
        RevealNote {
            owner: _owner,
            round_id: _round_id,
            randomness: _randomness,
            header: NoteHeader::empty(),
        }
    }

    /////////////////////////////////////////////////////////////////////
    //                        Internal methods                         //
    /////////////////////////////////////////////////////////////////////

    /// @notice Serializes the note
    fn serialize(self) -> [Field; REVEAL_NOTE_LEN] {
        [self.owner.address, self.round_id, self.randomness]
    }

    /// @notice Deserializes the note
    fn deserialize(preimage: [Field; REVEAL_NOTE_LEN]) -> Self {
        RevealNote {
            owner: AztecAddress::new(preimage[0]),
            round_id: preimage[1],
            randomness: preimage[2],
            header: NoteHeader::empty(),
        }
    }

    /// @notice Computes the note hash of the note
    fn compute_note_hash(self) -> Field {
        dep::std::hash::pedersen_hash([
            self.owner.address,
            self.round_id,
            self.randomness
        ])
    }

    /// @notice Computes the nullifier of the note
    fn compute_nullifier(self) -> Field {
        let note_hash_for_nullify = compute_note_hash_for_read_or_nullify(RevealNoteMethods, self);
        let nullifier_key = self.randomness;

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

fn deserialize(preimage: [Field; REVEAL_NOTE_LEN]) -> RevealNote {
    RevealNote::deserialize(preimage)
}

fn serialize(note: RevealNote) -> [Field; REVEAL_NOTE_LEN] {
    note.serialize()
}

fn compute_note_hash(note: RevealNote) -> Field {
    note.compute_note_hash()
}

fn compute_nullifier(note: RevealNote) -> Field {
    note.compute_nullifier()
}

fn get_header(note: RevealNote) -> NoteHeader {
    note.header
}

fn set_header(note: &mut RevealNote, header: NoteHeader) {
    note.set_header(header)
}

fn broadcast(context: &mut PrivateContext, slot: Field, note: RevealNote) {
    note.broadcast(context, slot);
}

global RevealNoteMethods = NoteInterface {
    deserialize,
    serialize,
    compute_note_hash,
    compute_nullifier,
    get_header,
    set_header,
    broadcast,
};