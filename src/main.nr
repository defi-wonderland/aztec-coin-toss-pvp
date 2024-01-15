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

    use dep::aztec::oracle::debug_log::{ debug_log, debug_log_field, debug_log_format };

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
            FromShieldStruct,
            TokenPublicContextInterface,
            FromShieldPrivateStruct,
            ToShieldPrivateStruct
        },
        affine_point::{AffinePoint, AffinePointSerializationMethods, AFFINE_POINT_SERIALIZED_LEN},
        elgamal_affine_points::{ElgamalAffinePoints, ElgamalAffinePointsSerializationMethods, ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN},
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
            get_secret_key::get_secret_key,
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
    use dep::bjj;

    use dep::std;
    use dep::std::ec::tecurve::affine::Curve as AffineCurve;
    use dep::std::ec::tecurve::affine::Point;
    use dep::std::collections::vec::Vec;


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
    global NUMBER_OF_TAILS_SLOT = 11;
    global DIVINITY_PUBLIC_KEY_SLOT = 12;

    /// @notice The storage of the contract
    /// @member round_id The id of the current round
    /// @member phase_length The length of each phase
    /// @member bet_amount The amount of each bet
    /// @member oracle_address The address of the private oracle
    /// @member divinity_address The address of the divinity contract
    /// @member token_address The address of the token used to bet
    /// @member results Saves the result of each round id
    /// @member rounds Saves the round data for each round id
    /// @member number_of_tails The number of tails in the cumsum of the tails (encrypted)
    /// @member divinity_bjj_public_key The divinity public key on baby jubjub curve (afffine)
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
        number_of_tails: Map<PublicState<ElgamalAffinePoints, ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN>>,
        divinity_bjj_public_key: PublicState<AffinePoint, AFFINE_POINT_SERIALIZED_LEN>,

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
                number_of_tails: Map::new(
                    context,
                    NUMBER_OF_TAILS_SLOT,
                    |context, slot| {
                        PublicState::new(
                            context,
                            slot,
                            ElgamalAffinePointsSerializationMethods
                        )
                    },
                ),
                divinity_bjj_public_key: PublicState::new( 
                    context,
                    DIVINITY_PUBLIC_KEY_SLOT,
                    AffinePointSerializationMethods,
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
    /// @param          divinity_bjj_public_key The divinity public key on baby jubjub curve (afffine)
    /// @param          private_oracle The private oracle contract address
    /// @param          token The token used to bet
    /// @param          bet_amount The bet amount
    /// @param          phase_length The phase length
    #[aztec(private)]
    fn constructor(divinity: AztecAddress, divinity_bjj_public_key: AffinePoint, private_oracle: AztecAddress, token: AztecAddress, bet_amount: Field, phase_length: Field) {
        let mut config_note = ConfigNote::new(divinity, divinity_bjj_public_key, private_oracle, token, bet_amount);
        storage.config.initialize(&mut config_note, Option::none(), false);

        let selector = compute_selector("_initialize(Field,Field,(Field),(Field),(Field))");
        context.call_public_function(context.this_address(), selector, [phase_length, bet_amount, private_oracle.address, divinity.address, token.address]);

        assert(bjj::is_valid_subgroup(divinity_bjj_public_key.point), "Invalid divinity public key - are you really in bjj field?");

        // insure function selector remains correct in later dev stage
        assert(AFFINE_POINT_SERIALIZED_LEN == 2);
        let selector2 = compute_selector("_init_bjj([Field;2])");
        context.call_public_function(context.this_address(), selector2, divinity_bjj_public_key.serialize());
    }

    /// @notice         Initializes the contract
    /// @custom:privacy public
    /// @param          phase_length The length of each phase
    /// @param          bet_amount The amount of each bet
    /// @param          oracle_address The address of the private oracle
    /// @param          divinity_address The address of the divinity contract
    /// @param          token_address The address of the token used to bet
    #[aztec(public)]
    internal fn _initialize(phase_length: Field, bet_amount: Field, oracle_address: AztecAddress, divinity_address: AztecAddress, token_address: AztecAddress) {
        storage.phase_length.write(phase_length);
        storage.bet_amount.write(bet_amount);
        storage.oracle_address.write(oracle_address);
        storage.divinity_address.write(divinity_address);
        storage.token_address.write(token_address);
    }

    /// @notice         Initializes the divinity public key used for decrypting the tail cumsum
    /// @custom:privacy public
    /// @param          serialized The serialized divinity public key (on baby jubjub curve)
    #[aztec(public)]
    internal fn _init_bjj(serialized: [Field; AFFINE_POINT_SERIALIZED_LEN]) {
        storage.divinity_bjj_public_key.write(AffinePoint::deserialize(serialized));
    }

    /////////////////////////////////////////////////////////////////////
    //                   Public internal functions                    //
    /////////////////////////////////////////////////////////////////////

    /// @notice         Starts a new round only when the previous round already left the betting phase
    /// @custom:privacy public
    #[aztec(public)]
    internal fn _start_next_round(encrypted_zero_C1_field: [Field;2], encrypted_zero_C2_field: [Field;2]) {
        let timestamp = context.timestamp();
        let phase_length = storage.phase_length.read();

        let current_round_id = storage.round_id.read();
        if(current_round_id != 0) {
            /// Checks that the previous round is finished
            let current_round_data = storage.rounds.at(storage.round_id.read()).read();
            assert(current_round_data.phase == Phase::CLAIM, "Current round not finished");
        }
        let next_round_id = current_round_id + 1;
        storage.round_id.write(next_round_id);
        storage.rounds.at(next_round_id).write(RoundData::new(Phase::BETTING, (timestamp + phase_length) as u120, 0, 0));

        let intial_encrypted_tails = ElgamalAffinePoints::new(
            AffinePoint::deserialize(encrypted_zero_C1_field),
            AffinePoint::deserialize(encrypted_zero_C2_field)
        );

        storage.number_of_tails.at(next_round_id).write(intial_encrypted_tails);
    }

    /// @notice         Ends the bet phase
    /// @custom:privacy public internal
    /// @param          round_id The id of the current round
    #[aztec(public)]
    internal fn _end_bet_phase(round_id: Field) {
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
        let new_round_data = RoundData::new(Phase::AWAITING_ANSWER, (timestamp + phase_length) as u120, current_round_data.bettors, 0);
        storage.rounds.at(current_round_id).write(new_round_data);
    }

    /// @notice         Increases the number of bettors
    /// @custom:privacy public internal
    /// @param          round_id The id of the current round
    #[aztec(public)]
    internal fn _increase_bettors(round_id: Field) {
        let current_round_id = storage.round_id.read();
        /// Checks that the round id is the current one
        assert(current_round_id == round_id, "Round id mismatch");

        /// Checks that the current round is in the betting phase
        let current_round_data = storage.rounds.at(current_round_id).read();
        assert(current_round_data.phase >= Phase::BETTING, "Betting phase over");

        /// Adds a bettor to the current round
        let updated_round_data = current_round_data.add_bettor();
        storage.rounds.at(round_id).write(updated_round_data);
    }

    /// @notice         Sets the result of the bet round
    /// @custom:privacy public internal
    /// @param          caller The caller of the function (the oracle)
    /// @param          round_id The id of the current round
    #[aztec(public)]
    internal fn _set_result(caller: Field, round_id: Field, answer: [Field;2], divinity_cum_sum: [Field;4], divinity_plain_embedded: [Field;2], divinity_public_key: [Field;2]) {
        let oracle = storage.oracle_address.read();
        let timestamp = context.timestamp() as u120;
        let phase_length = storage.phase_length.read() as u120;
        let bjj_affine = bjj::get_affine_curve();
        let base_pt = bjj::get_base_point();

        let coin_toss_result = answer[0] as bool;
        let bet_sum_plaintext = answer[1] as u40;
        let divinity_cumsum = ElgamalAffinePoints::deserialize(divinity_cum_sum);
        let divinity_public_key = AffinePoint::deserialize(divinity_public_key);
        let divinity_plain_embedded = AffinePoint::deserialize(divinity_plain_embedded);

        // get the public_key from storage and compare it to the passed in one
        let divinity_bjj_key = storage.divinity_bjj_public_key.read();
        assert(divinity_bjj_key.eq(divinity_public_key));

        // check that the passed in encrypted sum is the same as in storage
        let encrypted_cumsum = storage.number_of_tails.at(round_id).read();
        assert(divinity_cumsum.eq(encrypted_cumsum));

        let expected_plain_embedded: Point = bjj_affine.mul(bet_sum_plaintext as Field, base_pt);
        let expected_plain_embedded: AffinePoint = AffinePoint::new(expected_plain_embedded);
        assert(expected_plain_embedded.eq(divinity_plain_embedded));
        
        // if tails won, update it one way, otherwise calculate the other way

        /// Checks that the caller is the oracle
        assert(caller == oracle.address, "Caller is not the oracle");

        /// Checks that the round id is the current one
        let current_round_id = storage.round_id.read();
        assert(current_round_id == round_id, "Round id mismatch");

        /// Checks that the current round is in the awaiting answer phase
        let current_round_data = storage.rounds.at(current_round_id).read();
        assert(current_round_data.phase == Phase::AWAITING_ANSWER, "Not in awaiting answer phase");

        let bet_amount = storage.bet_amount.read() as u120;
        let number_of_bettors = current_round_data.bettors;
        let number_of_winners = if coin_toss_result { bet_sum_plaintext } else { number_of_bettors - bet_sum_plaintext };
        let claim_amount = number_of_bettors as u120 * bet_amount / number_of_winners as u120;

        // TODO: rounds are not resetted, therefore not checekd, does it make sense to do phase_end = timestamp + phase_length here?
        let new_round_data = RoundData::new(Phase::CLAIM, (timestamp + phase_length) as u120, current_round_data.bettors, claim_amount);
        storage.rounds.at(round_id).write(new_round_data);

        /// Updates the result mapping
        storage.results.at(round_id).write(coin_toss_result);
    }

    /// @notice         Shields the winnings back to the user
    /// @custom:privacy public internal
    /// @param          round_id The id of the current round
    /// @param          amount The amount to claim for winning the round
    #[aztec(public)]
    internal fn _validate_claim(round_id: Field, amount: Field, user_bet: Field) {
        let round_data = storage.rounds.at(round_id).read();

        /// Checks that the round is in the claim phase
        assert(round_data.phase == Phase::CLAIM, "Not in claim phase");

        let results = storage.results.at(round_id).read();
        /// Checks that the user bet matches the result
        assert(results == user_bet as bool, "User bet does not match result");

        let claim_amount = round_data.claim_amount;
        assert(claim_amount == amount as u120, "Claim amount mismatch");
    }

    /// @notice         Updates the encrypted cumulative sum of tails
    /// @custom:privacy public internal
    /// @param          round_id The id of the current round
    /// @param          encrypted_bet_C1_field The encrypted bet C1 point
    /// @param          encrypted_bet_C2_field The encrypted bet C2 point
    #[aztec(public)]
    internal fn _update_cumsum(round_id: Field, encrypted_bet_C1_field: [Field;2], encrypted_bet_C2_field: [Field;2]) {
        let encrypted_tails_to_add = ElgamalAffinePoints::new(
            AffinePoint::deserialize(encrypted_bet_C1_field),
            AffinePoint::deserialize(encrypted_bet_C2_field)
        );

        let current_tails_encrypted_count = storage.number_of_tails.at(round_id).read();    
        // TODO:REMOVE THIS IS FOR TEST
        let serialized_current_count = current_tails_encrypted_count.serialize();
        debug_log_format(" ================ BET_TO_ADD: {0} {1} {2} {3} ================", [encrypted_bet_C1_field[0], encrypted_bet_C1_field[1], encrypted_bet_C2_field[0], encrypted_bet_C2_field[1]]);
        debug_log_format(" ================ CURRENT_ENCRYPTED_COUNT: {0} {1} {2} {3} ================", [serialized_current_count[0], serialized_current_count[1], serialized_current_count[2], serialized_current_count[3]]);

        let new_tails_encrypted_count = current_tails_encrypted_count.add(encrypted_tails_to_add);
        // TODO:REMOVE THIS IS FOR TEST
        let test_var = new_tails_encrypted_count.serialize();
        debug_log_format(" ================ new_tails_encrypted_count: {0} {1} {2} {3} ================", [test_var[0], test_var[1], test_var[2], test_var[3]]);

        storage.number_of_tails.at(round_id).write(new_tails_encrypted_count);
    }

    /// @notice         Validates the encrypted cumulative sum of tails
    /// @custom:privacy public internal
    /// @param          encrypted_tail_sum The encrypted tail sum
    #[aztec(public)]
    // TODO: change name
    internal fn _validate_encrypted_tail_sum(encrypted_tail_sum_test: [Field;4]) {
        let round_id = storage.round_id.read();
        let encrypted_tail_sum = ElgamalAffinePoints::deserialize(encrypted_tail_sum_test);
        let encrypted_tails_count = storage.number_of_tails.at(round_id).read();
        // TODO: REMOVE THIS IS JUST FOR DEBUGGING
        let serialized = encrypted_tails_count.serialize();
        debug_log_format(" ================ encrypted_tail_sum: {0} {1} {2} {3} ================", [encrypted_tail_sum_test[0], encrypted_tail_sum_test[1], encrypted_tail_sum_test[2], encrypted_tail_sum_test[3]]);
        debug_log_format(" ================ encrypted_tails_count: {0} {1} {2} {3} ================ ", [serialized[0], serialized[1], serialized[2], serialized[3]]);
        
        assert(encrypted_tails_count.eq(encrypted_tail_sum), "Encrypted tail sum mismatch");
    }
    

    /////////////////////////////////////////////////////////////////////
    //                   Private external functions                    //
    /////////////////////////////////////////////////////////////////////

    #[aztec(private)]
    fn start_next_round(randomness: Field) {
        let config_note = storage.config.get_note();
        let divinity_bjj_key = config_note.divinity_bjj_public_key;

        let (encrypted_bet_c1, encrypted_bet_c2) = bjj::exp_elgamal_encrypt(divinity_bjj_key.point, 0 as u40, randomness);

        let serialized_calldata = [
            encrypted_bet_c1.x,
            encrypted_bet_c1.y,
            encrypted_bet_c2.x,
            encrypted_bet_c2.y
        ];

        let selector_update_bet_stats = compute_selector("_start_next_round([Field;2],[Field;2])");
        context.call_public_function(context.this_address(), selector_update_bet_stats, serialized_calldata);
    } 

    /// @notice         Creates a bet note for the user
    /// @custom:privacy private
    /// @param          bet The bet of the user
    /// @param          round_id The id of the current round
    /// @param          bet_randomness The randomness provided by the user
    /// @param          unshield_nonce The nonce of the unshield to take tokens from the user
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

        // Create a bet note for the user. This method nullifies the randomness and round_id combination.
        let mut user_bet: BetNote = BetNote::new(&mut context, bettor, round_id, bet, bet_randomness);
        storage.bets.insert(&mut user_bet, true);

        let selector_increase_bettors = compute_selector("_increase_bettors(Field)");
        context.call_public_function(context.this_address(), selector_increase_bettors, [round_id]);

        //TODO: in another private fn for gorgeous-er code? (needs call_private_function tho -> gates count?)
        let divinity_bjj_key = config_note.divinity_bjj_public_key;

        let (encrypted_bet_c1, encrypted_bet_c2) = bjj::exp_elgamal_encrypt(divinity_bjj_key.point, bet as u40, bet_randomness);

        let serialized_calldata = [
            round_id,
            encrypted_bet_c1.x,
            encrypted_bet_c1.y,
            encrypted_bet_c2.x,
            encrypted_bet_c2.y
        ];

        let selector_update_bet_stats = compute_selector("_update_cumsum(Field,[Field;2],[Field;2])");
        context.call_public_function(context.this_address(), selector_update_bet_stats, serialized_calldata);
    }

    /// @notice         Calls the oracle to get the result of the bet round
    /// @custom:privacy private
    /// @param          round_id The id of the current round
    #[aztec(private)]
    fn roll(round_id: Field, oracle_nonce: Field, encrypted_tail_sum: ElgamalAffinePoints) {
        let sender = AztecAddress::new(context.msg_sender());
        let config_note = storage.config.get_note();
        let divinity = config_note.divinity;
        let oracle = config_note.private_oracle;
        let oracle_contract = PrivateOraclePrivateContextInterface::at(oracle.address);
        let address_this = AztecAddress::new(context.this_address());
        let encrypted_sum_serialized = encrypted_tail_sum.serialize();

        // Create the question in the oracle
        let callback = [address_this.address, round_id, encrypted_sum_serialized[0], encrypted_sum_serialized[1], encrypted_sum_serialized[2], encrypted_sum_serialized[3]];
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
        let selector = compute_selector("_end_bet_phase(Field)");
        context.call_public_function(context.this_address(), selector, [round_id]);

        context.call_public_function(
            context.this_address(), 
            compute_selector("_validate_encrypted_tail_sum([Field;4])"), 
            [encrypted_sum_serialized[0], encrypted_sum_serialized[1], encrypted_sum_serialized[2], encrypted_sum_serialized[3]]
        );
    }

    /// @notice         Called by the oracle to set the result of the bet round and update the claimable amount for the winners
    /// @param          answer The answer of the oracle
    ///                 answer[0] bet result
    ///                 answer[1] plaintext
    ///                 answer[2] divinity private_key
    /// @param          data The data of the oracle 
    ///                 data[0]: round_id
    ///                 data[1:4]: serialized encrypted_sum
    #[aztec(private)]
    fn oracle_callback(answer: [Field; 3], data: [Field; 5], divinity_address: AztecAddress) {
        let round_id = data[0];
        let coin_toss_result = answer[0];
        let private_key = answer[1];
        let bet_sum_plaintext = answer[2];
        let divinity_address_config = storage.config.get_note().divinity;
        let divinity_cumsum = (Point::new(data[1], data[2]), Point::new(data[3], data[4]));

        assert(divinity_address_config.address == divinity_address.address, "Caller is not the designated divinity");

        let divinity_public_key: Point = bjj::priv_to_pub_key(private_key);
        let divinity_plain_embedded: Point = bjj::exp_elgamal_decrypt(private_key, divinity_cumsum);

        let selector = compute_selector("_set_result(Field,Field,[Field;2],[Field;4],[Field;2],[Field;2])");
        context.call_public_function(context.this_address(), selector, [context.msg_sender(), round_id, coin_toss_result, bet_sum_plaintext, data[1], data[2], data[3], data[4], divinity_plain_embedded.x, divinity_plain_embedded.y, divinity_public_key.x, divinity_public_key.y]);
    }

    /// @notice         Called by the user to claim their winnings
    /// @custom:privacy private
    /// @param          round_id The id of the current round
    /// @param          amount The amount to claim for winning the round
    #[aztec(private)]
    fn claim(round_id: Field, amount: Field, user_randomness: Field) {
        let config_note = storage.config.get_note();
        let token = TokenPrivateContextInterface::at(config_note.token.address);
        let bettor = AztecAddress::new(context.msg_sender());
        let address_this = AztecAddress::new(context.this_address());
        let options = NoteGetterOptions::new().select(1, round_id).select(3, user_randomness).set_limit(1);
        let bet_notes = storage.bets.get_notes(options);

        if (bet_notes[0].is_some()) {
            let bet_note = bet_notes[0].unwrap_unchecked();
            let user_bet = bet_note.bet;

            /// Nullifies the bet note
            storage.bets.remove(bet_note);

            // Shields privately to the user
            let _ = token.shield_private(
                &mut context,
                FromShieldPrivateStruct { address: address_this.address }, 
                ToShieldPrivateStruct {address: bettor.address }, 
                amount, 
                0
            );

            let selector = compute_selector("_validate_claim(Field,Field,Field)");
            context.call_public_function(context.this_address(), selector, [round_id, amount, user_bet as Field]);
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
        } else {
            note_utils::compute_note_hash_and_nullifier(ConfigNoteMethods, note_header, preimage)
        }
    }

    /// @notice         Returns the phase length
    unconstrained fn get_phase_length_unconstrained() -> Field {
        storage.phase_length.read()
    }

    /// @notice         Returns the bet amount
    unconstrained fn get_bet_amount_unconstrained() -> Field {
        storage.bet_amount.read()
    }

    /// @notice         Returns the oracle address
    unconstrained fn get_oracle_address_unconstrained() -> AztecAddress {
        storage.oracle_address.read()
    }

    /// @notice         Returns the divinity address
    unconstrained fn get_divinity_address_unconstrained() -> AztecAddress {
        storage.divinity_address.read()
    }

    /// @notice         Returns the token address
    unconstrained fn get_token_address_unconstrained() -> AztecAddress {
        storage.token_address.read()
    }

    /// @notice         Returns the round id
    unconstrained fn get_round_id() -> Field {
        storage.round_id.read()
    }

    /// @notice         Returns the round data for a given round id
    unconstrained fn get_round_data(round_id: Field) -> RoundData {
        storage.rounds.at(round_id).read()
    }

    /// @notice         Returns the result for a given round id
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