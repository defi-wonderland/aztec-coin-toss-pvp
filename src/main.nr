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
        reveal_note::{RevealNote, RevealNoteMethods, REVEAL_NOTE_LEN},
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
    global REVEALS_SLOT = 11;

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
        reveals: Set<RevealNote, REVEAL_NOTE_LEN>,
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
                reveals: Set::new(context, REVEALS_SLOT, RevealNoteMethods),
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
        storage.rounds.at(next_round_id).write(RoundData::new(Phase::BETTING, (timestamp + phase_length) as u120, 0, 0, 0));
    }

    #[aztec(public)]
    fn end_reveal_phase() {
        let current_round_id = storage.round_id.read(); 
        let current_round_data = storage.rounds.at(current_round_id).read();
        let number_of_bettors = current_round_data.bettors;
        let number_of_winners = current_round_data.reveals_count;

        assert(current_round_data.phase == Phase::REVEAL, "Reveal phase over");
        
        let bet_amount = storage.bet_amount.read() as u120;
        let claim_amount = number_of_bettors * bet_amount / number_of_winners;

        let timestamp = context.timestamp() as u120;
        let phase_length = storage.phase_length.read() as u120;

        let updated_round_data = RoundData::new(Phase::CLAIM, (timestamp + phase_length) as u120, number_of_winners, number_of_bettors, claim_amount);
        storage.rounds.at(current_round_id).write(updated_round_data);
    }

    /////////////////////////////////////////////////////////////////////
    //                   Public internal functions                    //
    /////////////////////////////////////////////////////////////////////

    #[aztec(public)]
    fn initialize(phase_length: Field, bet_amount: Field, oracle_address: AztecAddress, divinity_address: AztecAddress, token_address: AztecAddress) {
        assert(context.msg_sender() == context.this_address());

        storage.phase_length.write(phase_length);
        storage.bet_amount.write(bet_amount);
        storage.oracle_address.write(oracle_address);
        storage.divinity_address.write(divinity_address);
        storage.token_address.write(token_address);
    }

    #[aztec(public)]
    internal fn end_bet_phase(round_id: Field) {
        let timestamp = context.timestamp() as u120;
        let phase_length = storage.phase_length.read() as u120;

        // Check that the phase is BETTING 
        let current_round_id = storage.round_id.read();
        assert(round_id == current_round_id, "Round id mismatch");

        let current_round_data = storage.rounds.at(storage.round_id.read()).read();
        assert(current_round_data.phase == Phase::BETTING, "Not in bet phase");

        // Check that the timestamp is after the end of the bet phase
        assert(timestamp >= current_round_data.current_phase_end, "Bet phase not finished");

        // Set state to AWAITING_ANSWER and update the end phase timestamp
        let new_round_data = RoundData::new(Phase::AWAITING_ANSWER, (timestamp + phase_length) as u120, 0, current_round_data.bettors, 0);
        storage.rounds.at(current_round_id).write(new_round_data);
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
        assert(current_round_id == round_id, "Round id mismatch");

        let current_round_data = storage.rounds.at(current_round_id).read();
        assert(current_round_data.phase >= Phase::BETTING, "Betting phase over");

        let updated_round_data = current_round_data.add_bettor();
        storage.rounds.at(round_id).write(updated_round_data);
    }

    #[aztec(public)]
    internal fn _set_result(caller: Field, round_id: Field, answer: Field) {
        let oracle = storage.oracle_address.read();
        let timestamp = context.timestamp() as u120;
        let phase_length = storage.phase_length.read() as u120;

        assert(caller == oracle.address, "Caller is not the oracle");

        let current_round_id = storage.round_id.read();
        assert(current_round_id == round_id, "Round id mismatch");

        let current_round_data = storage.rounds.at(current_round_id).read();
        assert(current_round_data.phase == Phase::AWAITING_ANSWER, "Not in awaiting answer phase");

        let new_round_data = RoundData::new(Phase::REVEAL, (timestamp + phase_length) as u120, 0, current_round_data.bettors, 0);
        storage.rounds.at(round_id).write(new_round_data);

        storage.results.at(round_id).write(answer as bool);
    }

    #[aztec(public)]
    internal fn _increase_reveals(round_id: Field, user_bet: Field) {
        let current_round_id = storage.round_id.read();
        assert(current_round_id == round_id, "Round id mismatch");

        let current_round_data = storage.rounds.at(current_round_id).read();
        assert(current_round_data.phase == Phase::REVEAL, "Reveal phase over");

        let results = storage.results.at(round_id).read();
        assert(results == user_bet as bool, "User bet does not match result");

        let updated_round_data = current_round_data.increase_reveal_count();
        storage.rounds.at(round_id).write(updated_round_data);
    }

    /////////////////////////////////////////////////////////////////////
    //                   Private internal functions                    //
    /////////////////////////////////////////////////////////////////////

    /// @notice         Calls the oracle to get the result of the bet round
    /// @custom:privacy private
    /// @param          round_id The id of the current round
    #[aztec(private)]
    fn roll(round_id: Field, oracle_nonce: Field) {
        let sender = AztecAddress::new(context.msg_sender());
        let config_note = storage.config.get_note();
        let divinity = config_note.divinity;
        let oracle = config_note.private_oracle;
        let oracle_contract = PrivateOraclePrivateContextInterface::at(oracle.address);
        let address_this = AztecAddress::new(context.this_address());

        // Create the question in the oracle
        let callback = [address_this.address, round_id, 0, 0, 0, 0];
        let __ = oracle_contract.submit_question(
            &mut context,
            FromSubmitQuestionStruct { address: sender.address },
            round_id,
            DivinityAddressSubmitQuestionStruct { address: divinity.address },
            oracle_nonce,
            callback
        );

        // End the bet phase and update public state
        // This checks that the round id is correct and that the phase is BETTING
        let selector = compute_selector("end_bet_phase(Field)");
        context.call_public_function(context.this_address(), selector, [round_id]);
    }

    /// @notice         Called by the oracle to set the result of the bet round
    /// @param          answer The answer of the oracle
    /// @param          data The data of the oracle 
    ///                 data[0]: round_id
    ///                 data[1:5]: unused
    #[aztec(private)]
    fn oracle_callback(answer: Field, data: [Field; 5]) {
        let round_id = data[0];
        let selector = compute_selector("_set_result(Field,Field,Field)");
        context.call_public_function(context.this_address(), selector, [context.msg_sender(), round_id, answer]);
    }

    #[aztec(private)]
    fn reveal(round_id: Field, user_randomness: Field) {
        let options = NoteGetterOptions::new().select(1, round_id).select(3, user_randomness).set_limit(1);
        let bet_notes = storage.bets.get_notes(options);
        let bettor = AztecAddress::new(context.msg_sender());

        if (bet_notes[0].is_some()) {
            let bet_note = bet_notes[0].unwrap_unchecked();
            let user_bet = bet_note.bet;
            
            let mut reveal_note: RevealNote = RevealNote::new(bettor, round_id, user_randomness);
            storage.reveals.insert(&mut reveal_note, true);

            storage.bets.remove(bet_note);

            let selector = compute_selector("_increase_reveals(Field,Field)");
            context.call_public_function(context.this_address(), selector, [round_id, user_bet as Field]);
        } else {
            assert(false, "Bet note not found");
        }
    }

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

    /// @notice         Gets the reveal notes for an user
    /// @custom:privacy unconstrained
    /// @param          start_offset The offset to start from
    /// @return         The reveal notes (padded with empty notes, up to 10)
    unconstrained fn get_reveal_notes_unconstrained(start_offset: u32) -> [Option<RevealNote>; 10] {
        let reveal_notes_getter_option = NoteViewerOptions::new().set_offset(start_offset);
        storage.reveals.view_notes(reveal_notes_getter_option)
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

        if(storage_slot == BETS_SLOT) {
            note_utils::compute_note_hash_and_nullifier(BetNoteMethods, note_header, preimage)
        } else if(storage_slot == REVEALS_SLOT) {
            note_utils::compute_note_hash_and_nullifier(RevealNoteMethods, note_header, preimage)
        } else {
            note_utils::compute_note_hash_and_nullifier(ConfigNoteMethods, note_header, preimage)
        }
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

    unconstrained fn get_result(round_id: Field) -> bool {
        storage.results.at(round_id).read()
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