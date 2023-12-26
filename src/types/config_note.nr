/////////////////////////////////////////////////////////////////////
//                             Imports                             //
/////////////////////////////////////////////////////////////////////

use dep::aztec::{
    context::PrivateContext,
    note::{
        note_header::NoteHeader,
        note_interface::NoteInterface,
    },
    types::address::AztecAddress
};

/////////////////////////////////////////////////////////////////////
//                              Class                              //
/////////////////////////////////////////////////////////////////////

/// @notice a note containing the (immutable) game configuration
/// @member divinity the address of the divinity used by the oracle
/// @member private_oracle the address of the private oracle contract
/// @member token the address of the token used for betting
/// @member bet_amount the amount of tokens to bet
/// @member header the note header
struct ConfigNote {
    divinity: AztecAddress,
    private_oracle: AztecAddress,
    token: AztecAddress,
    bet_amount: Field,
    header: NoteHeader
}

global CONFIG_NOTE_LEN: Field = 4;

impl ConfigNote {
    
    /////////////////////////////////////////////////////////////////////
    //                         Public methods                          //
    /////////////////////////////////////////////////////////////////////

    /// @notice create a new config note
    /// @param _divinity the address of the divinity used by the oracle
    /// @param _private_oracle the address of the private oracle contract
    /// @param _token the address of the token used for betting
    /// @param _amount the amount of tokens to bet
    pub fn new(_divinity: AztecAddress, _private_oracle: AztecAddress, _token: AztecAddress, _amount: Field) -> Self {
        ConfigNote {
            divinity: _divinity,
            private_oracle: _private_oracle,
            token: _token,
            bet_amount: _amount,
            header: NoteHeader::empty(),
        }
    }

    /////////////////////////////////////////////////////////////////////
    //                        Internal methods                         //
    /////////////////////////////////////////////////////////////////////

    /// @notice serialize the note
    fn serialize(self) -> [Field; CONFIG_NOTE_LEN] {
        [self.divinity.address, self.private_oracle.address, self.token.address, self.bet_amount]
    }

    /// @notice deserialize the note
    fn deserialize(preimage: [Field; CONFIG_NOTE_LEN]) -> Self {
        ConfigNote {
            divinity: AztecAddress::new(preimage[0]),
            private_oracle: AztecAddress::new(preimage[1]),
            token: AztecAddress::new(preimage[2]),
            bet_amount: preimage[3],
            header: NoteHeader::empty(),
        }
    }

    /// @notice compute the note hash
    fn compute_note_hash(self) -> Field {
        dep::std::hash::pedersen_hash([
            self.divinity.address,
            self.private_oracle.address,
            self.token.address,
            self.bet_amount
        ])
    }

    /// @notice this note isn't nullifiable, returns 0
    fn compute_nullifier(self) -> Field {
         let _ = self; // Avoid compiler warning (same # acir opcodes and backend size)
         0
    }

    /// @notice get the note header
    fn set_header(&mut self, header: NoteHeader) {
        self.header = header;
    }

    /// @notice this notes isn't private, no owner to emit to
    fn broadcast(self, context: &mut PrivateContext, slot: Field) {
        // no owner == no broadcast
        let _ = self; // Avoid compiler warning (same # acir opcodes and backend size)
        let __ = context;
        let ___ = slot;
    }
}

/////////////////////////////////////////////////////////////////////
//                         Global methods                          //
/////////////////////////////////////////////////////////////////////

fn deserialize(preimage: [Field; CONFIG_NOTE_LEN]) -> ConfigNote {
    ConfigNote::deserialize(preimage)
}

fn serialize(note: ConfigNote) -> [Field; CONFIG_NOTE_LEN] {
    note.serialize()
}

fn compute_note_hash(note: ConfigNote) -> Field {
    note.compute_note_hash()
}

fn compute_nullifier(note: ConfigNote) -> Field {
    note.compute_nullifier()
}

fn get_header(note: ConfigNote) -> NoteHeader {
    note.header
}

fn set_header(note: &mut ConfigNote, header: NoteHeader) {
    note.set_header(header)
}

fn broadcast(context: &mut PrivateContext, slot: Field, note: ConfigNote) {
    note.broadcast(context, slot);
}

global ConfigNoteMethods = NoteInterface {
    deserialize,
    serialize,
    compute_note_hash,
    compute_nullifier,
    get_header,
    set_header,
    broadcast,
};