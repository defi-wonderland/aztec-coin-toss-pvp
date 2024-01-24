/////////////////////////////////////////////////////////////////////
//                             Imports                             //
/////////////////////////////////////////////////////////////////////

use dep::aztec::{
    context::PrivateContext,
    note::{
        note_header::NoteHeader,
        note_interface::NoteInterface,
    },
    protocol_types::address::AztecAddress
};

use dep::std::ec::tecurve::affine::Point;

use crate::types::{
    affine_point::AffinePoint,
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
    divinity_bjj_public_key: AffinePoint,
    private_oracle: AztecAddress,
    token: AztecAddress,
    bet_amount: Field,
    header: NoteHeader
}

global CONFIG_NOTE_LEN: Field = 6;

impl ConfigNote {
    
    /////////////////////////////////////////////////////////////////////
    //                         Public methods                          //
    /////////////////////////////////////////////////////////////////////

    /// @notice create a new config note
    /// @param _divinity the address of the divinity used by the oracle
    /// @param _private_oracle the address of the private oracle contract
    /// @param _token the address of the token used for betting
    /// @param _amount the amount of tokens to bet
    pub fn new(_divinity: AztecAddress, _divinity_bjj_public_key: AffinePoint, _private_oracle: AztecAddress, _token: AztecAddress, _amount: Field) -> Self {
        ConfigNote {
            divinity: _divinity,
            divinity_bjj_public_key: _divinity_bjj_public_key,
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
        [self.divinity.to_field(), self.divinity_bjj_public_key.point.x, self.divinity_bjj_public_key.point.y, self.private_oracle.to_field(), self.token.to_field(), self.bet_amount]
    }

    /// @notice deserialize the note
    fn deserialize(preimage: [Field; CONFIG_NOTE_LEN]) -> Self {
        ConfigNote {
            divinity: AztecAddress::from_field(preimage[0]),
            divinity_bjj_public_key: AffinePoint::new(Point::new(preimage[1], preimage[2])),
            private_oracle: AztecAddress::from_field(preimage[3]),
            token: AztecAddress::from_field(preimage[4]),
            bet_amount: preimage[5],
            header: NoteHeader::empty(),
        }
    }

    /// @notice compute the note hash
    fn compute_note_hash(self) -> Field {
        dep::std::hash::pedersen_hash([
            self.divinity.to_field(),
            self.divinity_bjj_public_key.point.x,
            self.divinity_bjj_public_key.point.y,
            self.private_oracle.to_field(),
            self.token.to_field(),
            self.bet_amount
        ])
    }

    /// @notice this note isn't nullifiable, returns 0
    fn compute_nullifier(self, _context: &mut PrivateContext) -> Field {
        self.compute_nullifier_without_context()
    }

    /// @notice this note isn't nullifiable, returns 0
    fn compute_nullifier_without_context(self) -> Field {
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

fn compute_nullifier(note: ConfigNote, context: &mut PrivateContext) -> Field {
    note.compute_nullifier(context)
}

fn compute_nullifier_without_context(note: ConfigNote) -> Field {
    note.compute_nullifier_without_context()
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
    compute_nullifier_without_context,
    get_header,
    set_header,
    broadcast,
};