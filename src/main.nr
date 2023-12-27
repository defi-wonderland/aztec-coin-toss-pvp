mod types;

/// @notice This contract implements a private coin toss game between users.
/// @dev The contract is deployed with a bet_amount and a private oracle.
///      The user can create a bet note with a bet (true or false) which is later settled by the private oracle.
///      The users that betted for the winner receive (in equal parts) the bets made by the users that lost.
contract CoinToss {

    /////////////////////////////////////////////////////////////////////
    //                             Imports                             //
    /////////////////////////////////////////////////////////////////////

    use crate::types::oracle::{
        DivinityAddressSubmitQuestionStruct, 
        FromSubmitQuestionStruct, 
        PrivateOraclePrivateContextInterface, 
    };

    use crate::types::{
        bet_note::{BetNote, BetNoteMethods, BET_NOTE_LEN},
        config_note::{ConfigNote, ConfigNoteMethods, CONFIG_NOTE_LEN},
        round_data::{RoundData, RoundDataSerializationMethods, ROUND_DATA_SERIALIZED_LEN, Phase},
        token::{
            AccountsBroadcastEscrowNoteForStruct,
            FromEscrowStruct,
            FromTransferStruct, 
            OwnerEscrowStruct,
            OwnerSettleEscrowStruct,
            RecipientSettleEscrowStruct,
            TokenPrivateContextInterface, 
            ToTransferStruct,
            FromUnshieldStruct,
            ToUnshieldStruct,
        }
    };

    use dep::aztec::{
        context::Context,
        types::type_serialization::{
            field_serialization::{FieldSerializationMethods, FIELD_SERIALIZED_LEN},
            bool_serialization::{BoolSerializationMethods, BOOL_SERIALIZED_LEN},
            aztec_address_serialization::{AztecAddressSerializationMethods, AZTEC_ADDRESS_SERIALIZED_LEN},
        },
        note::{
            note_getter_options::NoteGetterOptions,
            note_header::NoteHeader,
            note_viewer_options::NoteViewerOptions,
            utils as note_utils
        },
        oracle::{
            get_public_key::get_public_key,
            rand::rand
        },
        selector::compute_selector,
        state_vars::{
            immutable_singleton::ImmutableSingleton,
            set::Set,
            map::Map, 
            public_state::PublicState
        },
        types::address::AztecAddress,
    };

    use dep::std::option::Option;

    /////////////////////////////////////////////////////////////////////
    //                             Storage                             //
    /////////////////////////////////////////////////////////////////////

    global ROUND_ID_SLOT = 1;
    global PHASE_LENGTH_SLOT = 2;
    global BET_AMOUNT_SLOT = 3;
    global ORACLE_ADDRESS_SLOT = 4;
    global DIVINITY_ADDRESS_SLOT = 5;
    global TOKEN_ADDRESS_SLOT = 6;
    global RESULTS_SLOT = 7;
    global ROUND_DATA_SLOT = 8;
    global CONFIG_NOTE_SLOT = 9;
    global BETS_SLOT = 10;

    /// @member config The config note, containing the divinity address, the private oracle address, the token address and the bet amount
    /// @member bets The set of bet notes (ie active bets)
    struct Storage {
        ////////////////////////////// public //////////////////////////
        round_id: PublicState<Field, FIELD_SERIALIZED_LEN>,
        phase_length: PublicState<Field, FIELD_SERIALIZED_LEN>,
        bet_amount: PublicState<Field, FIELD_SERIALIZED_LEN>,
        oracle_address: PublicState<AztecAddress, AZTEC_ADDRESS_SERIALIZED_LEN>,
        divinity_address: PublicState<AztecAddress, AZTEC_ADDRESS_SERIALIZED_LEN>,
        token_address: PublicState<AztecAddress, AZTEC_ADDRESS_SERIALIZED_LEN>,
        results: Map<PublicState<bool, BOOL_SERIALIZED_LEN>>,
        rounds: Map<PublicState<RoundData, ROUND_DATA_SERIALIZED_LEN>>,

        ///////////////////////////// private //////////////////////////
        config: ImmutableSingleton<ConfigNote, CONFIG_NOTE_LEN>,
        bets: Set<BetNote, BET_NOTE_LEN>,
    }

    impl Storage {
        fn init(context: Context) -> Self {
            Storage {
                ////////////////////////////// public //////////////////////////
                round_id: PublicState::new(context, ROUND_ID_SLOT, FieldSerializationMethods),
                phase_length: PublicState::new(context, PHASE_LENGTH_SLOT, FieldSerializationMethods),
                bet_amount: PublicState::new(context, BET_AMOUNT_SLOT, FieldSerializationMethods),
                oracle_address: PublicState::new(context, ORACLE_ADDRESS_SLOT, AztecAddressSerializationMethods),
                divinity_address: PublicState::new(context, DIVINITY_ADDRESS_SLOT, AztecAddressSerializationMethods),
                token_address: PublicState::new(context, TOKEN_ADDRESS_SLOT, AztecAddressSerializationMethods),
                results: Map::new(
                    context,
                    RESULTS_SLOT,
                    |context, slot| {
                        PublicState::new(
                            context,
                            slot,
                            BoolSerializationMethods,
                        )
                    },
                ),
                 rounds: Map::new(
                    context,
                    ROUND_DATA_SLOT,
                    |context, slot| {
                        PublicState::new(
                            context,
                            slot,
                            RoundDataSerializationMethods,
                        )
                    },
                ),

                ////////////////////////////// private //////////////////////////
                config: ImmutableSingleton::new(
                    context,
                    CONFIG_NOTE_SLOT,
                    ConfigNoteMethods,
                ),
                bets: Set::new(context, BETS_SLOT, BetNoteMethods),
            }
        }
    }

    /////////////////////////////////////////////////////////////////////
    //                           Constructor                           //
    /////////////////////////////////////////////////////////////////////

    /// @notice         Constructor for the contract, setting the config note
    /// @custom:privacy private
    /// @param          divinity The divinity address, invoked by the oracle
    /// @param          private_oracle The private oracle contract address
    /// @param          token The token used to bet
    /// @param          bet_amount The bet amount
    /// @param          phase_length The phase length
    #[aztec(private)]
    fn constructor(divinity: AztecAddress, private_oracle: AztecAddress, token: AztecAddress, bet_amount: Field, phase_length: Field) {
        let mut config_note = ConfigNote::new(divinity, private_oracle, token, bet_amount);
        storage.config.initialize(&mut config_note, Option::none(), false);

        let selector = compute_selector("initialize(Field,Field,(Field),(Field),(Field))");
        context.call_public_function(context.this_address(), selector, [phase_length, bet_amount, private_oracle.address, divinity.address, token.address]);
    }

    // Update the payment token and fee getters
    #[aztec(public)]
    fn initialize(phase_length: Field, bet_amount: Field, oracle_address: AztecAddress, divinity_address: AztecAddress, token_address: AztecAddress) {
        assert(context.msg_sender() == context.this_address());

        storage.phase_length.write(phase_length);
        storage.bet_amount.write(bet_amount);
        storage.oracle_address.write(oracle_address);
        storage.divinity_address.write(divinity_address);
        storage.token_address.write(token_address);
    }

    /////////////////////////////////////////////////////////////////////
    //                   Public external functions                    //
    /////////////////////////////////////////////////////////////////////

    #[aztec(public)]
    fn start_next_round() {
        let timestamp = context.timestamp();
        let phase_length = storage.phase_length.read();

        let current_round_id = storage.round_id.read();
        if(current_round_id != 0) {
            let current_round_data = storage.rounds.at(storage.round_id.read()).read();
            assert(current_round_data.phase >= Phase::REVEAL, "Current round not finished");
        }
        let next_round_id = current_round_id + 1;
        storage.round_id.write(next_round_id);
        storage.rounds.at(next_round_id).write(RoundData::new(1, (timestamp + phase_length) as u120, 0, 0));
    }

    /////////////////////////////////////////////////////////////////////
    //                   Private external functions                    //
    /////////////////////////////////////////////////////////////////////
    #[aztec(private)]
    fn bet(bet: bool, round_id: Field, bet_randomness: Field, unshield_nonce: Field) {
        let config_note = storage.config.get_note();
        let token = config_note.token;
        let bet_amount = config_note.bet_amount;
        let bettor = AztecAddress::new(context.msg_sender());
        let address_this = AztecAddress::new(context.this_address());
        let token = TokenPrivateContextInterface::at(token.address);

        // Unshield private balance from the user to the coin toss. This requires an authwit.
        let _ = token.unshield(
            &mut context,
            FromUnshieldStruct { address: bettor.address }, 
            ToUnshieldStruct {address: address_this.address }, 
            bet_amount, 
            unshield_nonce
        );

        // Create a bet note for the user. This method nullifies the randomness and round_id combinarion.
        let mut user_bet: BetNote = BetNote::new(&mut context, bettor, round_id, bet, bet_randomness);
        storage.bets.insert(&mut user_bet, true);

        let selector = compute_selector("_increase_bettors(Field)");
        context.call_public_function(context.this_address(), selector, [round_id]);
    }

    /////////////////////////////////////////////////////////////////////
    //                   Public internal functions                    //
    /////////////////////////////////////////////////////////////////////
    #[aztec(public)]
    internal fn _increase_bettors(
        round_id: Field,
    ) {
        let current_round_id = storage.round_id.read();
        assert(current_round_id == round_id, "Round id does not match current round id");

        let current_round_data = storage.rounds.at(current_round_id).read();
        assert(current_round_data.phase >= Phase::BETTING, "Betting phase over");

        let updated_round_data = current_round_data.add_bettor();
        storage.rounds.at(round_id).write(updated_round_data);
    }

    /////////////////////////////////////////////////////////////////////
    //                   Private internal functions                    //
    /////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////
    //             Public unconstrained external functions             //
    /////////////////////////////////////////////////////////////////////

    /// @notice         Gets the config note
    /// @custom:privacy unconstrained
    /// @return         The config note (divinity, private oracle, token, bet_amount)
    unconstrained fn get_config_unconstrained() -> ConfigNote {
        storage.config.view_note()
    }

    /// @notice         Gets the bet notes for an user
    /// @custom:privacy unconstrained
    /// @param          start_offset The offset to start from
    /// @return         The bet notes (padded with empty notes, up to 10)
    unconstrained fn get_user_bets_unconstrained(start_offset: u32) -> [Option<BetNote>; 10] {
        let user_bets_getter_option = NoteViewerOptions::new().set_offset(start_offset);
        storage.bets.view_notes(user_bets_getter_option)
    }

    /// @notice         Compute the note hash and nullifier for a note
    /// @custom:privacy unconstrained
    /// @param          contract_address The contract address (this)
    /// @param          nonce The nonce
    /// @param          storage_slot The storage slot of the note
    /// @param          preimage The preimage of the note
    /// @return         The note hash and nullifier
    unconstrained fn compute_note_hash_and_nullifier(contract_address: Field, nonce: Field, storage_slot: Field, preimage: [Field; CONFIG_NOTE_LEN]) -> [Field; 4] {
        let note_header = NoteHeader::new(contract_address, nonce, storage_slot);
        note_utils::compute_note_hash_and_nullifier(ConfigNoteMethods, note_header, preimage)
    }

    unconstrained fn get_phase_length_unconstrained() -> Field {
        storage.phase_length.read()
    }

    unconstrained fn get_bet_amount_unconstrained() -> Field {
        storage.bet_amount.read()
    }

    unconstrained fn get_oracle_address_unconstrained() -> AztecAddress {
        storage.oracle_address.read()
    }

    unconstrained fn get_divinity_address_unconstrained() -> AztecAddress {
        storage.divinity_address.read()
    }

    unconstrained fn get_token_address_unconstrained() -> AztecAddress {
        storage.token_address.read()
    }

    unconstrained fn get_round_id() -> Field {
        storage.round_id.read()
    }

    unconstrained fn get_round_data(round_id: Field) -> RoundData {
        storage.rounds.at(round_id).read()
    }

    /// @notice         Gets a bet note by its round id and randomness combination and checks whether these params were nullified
    /// @custom:privacy unconstrained
    /// @param          round_id The id of the round this bet was made in
    /// @param          randomness The randomness the user used for this bet in this round
    /// @param          bet_id The id of the bet
    /// @return         A boolean indicating whether a bet with this combination of fields has been initialized or not
    unconstrained fn is_round_randomness_nullified(round_id: Field, randomness: Field) -> bool {
        BetNote::is_round_randomness_nullified(round_id, randomness)
    }
}

/*
    fn reveal(result: bool, user_randomness: Field, round_id: Field) {
        let options = NoteGetterOptions::new().select(1, round_id).select(3, user_randomness).set_limit(1);
        let bet_notes = storage.bets.get_notes(user_bets_getter_option)

        if (bet_notes[0].is_some()) {
            let bet_note = bet_notes[0].unwrap_unchecked();

        }
    }
*/