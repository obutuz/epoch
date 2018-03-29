%%%=============================================================================
%%% @copyright (C) 2018, Aeternity Anstalt
%%% @doc
%%%    ADT for local state objects
%%% @end
%%%=============================================================================
-module(aesc_state).

-include_lib("apps/aecore/include/common.hrl").

%% API
-export([deserialize/1,
         pubkeys/1,
         serialize/1,
         serialize_to_bin/1]).

%% Getters
-export([initiator/1,
         initiator_amount/1,
         responder/1,
         responder_amount/1,
         sequence_number/1]).

%%%===================================================================
%%% Types
%%%===================================================================

-define(LOCAL_STATE_VSN, 1).

-type hash()       :: binary().
-type amount()     :: non_neg_integer().
-type seq_number() :: non_neg_integer().

-record(state, {
          chain_hash       :: hash(),
          initiator_pubkey :: pubkey(),
          responder_pubkey :: pubkey(),
          initiator_amount :: amount(),
          responder_amount :: amount(),
          channel_active   :: boolean(),
          sequence_number  :: seq_number(),
          closed           :: boolean()
         }).
-opaque state() :: #state{}.

-export_type([seq_number/0,
              state/0]).

%%%===================================================================
%%% API
%%%===================================================================
-spec deserialize(binary()) -> state().
deserialize(Bin) ->
    %% Why is that serialized by msgpack?
    %% Why list of maps? Isn't one map sufficient?
    {ok, List} = msgpack:unpack(Bin),
    [#{<<"vsn">>              := ?LOCAL_STATE_VSN},
     #{<<"chain_hash">>       := ChainHash},
     #{<<"initiator_pubkey">> := InitiatorPubKey},
     #{<<"responder_pubkey">> := ResponderPubKey},
     #{<<"initiator_amount">> := InitiatorAmount},
     #{<<"responder_amount">> := ResponderAmount},
     #{<<"channel_active">>   := ChannelActive},
     #{<<"sequence_number">>  := SeqNumber},
     #{<<"closed">>           := Closed}] = List,
    #state{chain_hash       = ChainHash,
           initiator_pubkey = InitiatorPubKey,
           responder_pubkey = ResponderPubKey,
           initiator_amount = InitiatorAmount,
           responder_amount = ResponderAmount,
           channel_active   = ChannelActive,
           sequence_number  = SeqNumber,
           closed           = Closed}.

-spec pubkeys(state()) -> list(pubkey()).
pubkeys(#state{initiator_pubkey = InitiatorPubKey,
               responder_pubkey = ResponderPubKey}) ->
    [InitiatorPubKey, ResponderPubKey].

-spec serialize(state()) -> binary().
serialize(#state{chain_hash       = ChainHash,
                 initiator_pubkey = InitiatorPubKey,
                 responder_pubkey = ResponderPubKey,
                 initiator_amount = InitiatorAmount,
                 responder_amount = ResponderAmount,
                 channel_active   = ChannelActive,
                 sequence_number  = SeqNumber,
                 closed           = Closed}) ->
    msgpack:pack(
      [#{<<"vsn">>              => ?LOCAL_STATE_VSN},
       #{<<"chain_hash">>       => ChainHash},
       #{<<"initiator_pubkey">> => InitiatorPubKey},
       #{<<"responder_pubkey">> => ResponderPubKey},
       #{<<"initiator_amount">> => InitiatorAmount},
       #{<<"responder_amount">> => ResponderAmount},
       #{<<"channel_active">>   => ChannelActive},
       #{<<"sequence_number">>  => SeqNumber},
       #{<<"closed">>           => Closed}]).

-spec serialize_to_bin(state()) -> binary().
serialize_to_bin(State) ->
    StateMap = serialize(State),
    msgpack:pack(StateMap).

%%%===================================================================
%%% Getters
%%%===================================================================

-spec initiator(state()) -> pubkey().
initiator(#state{initiator_pubkey = InitiatorPubKey}) ->
    InitiatorPubKey.

-spec initiator_amount(state()) -> amount().
initiator_amount(#state{initiator_amount = Amount}) ->
    Amount.

-spec responder(state()) -> pubkey().
responder(#state{responder_pubkey = ResponderPubKey}) ->
    ResponderPubKey.

-spec responder_amount(state()) -> amount().
responder_amount(#state{responder_amount = Amount}) ->
    Amount.

-spec sequence_number(state()) -> seq_number().
sequence_number(#state{sequence_number = SeqNumber}) ->
    SeqNumber.