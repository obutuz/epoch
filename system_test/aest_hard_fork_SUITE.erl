-module(aest_hard_fork_SUITE).

%=== EXPORTS ===================================================================

% Common Test exports
-export([all/0]).
-export([groups/0]).
-export([suite/0]).
-export([init_per_suite/1]).
-export([end_per_suite/1]).
-export([init_per_group/2]).
-export([end_per_group/2]).
-export([init_per_testcase/2]).
-export([end_per_testcase/2]).

% Test cases
-export([
         old_node_persisting_chain_and_not_mining_has_genesis_as_top/1,
         new_node_persisting_chain_and_not_mining_has_same_old_genesis_as_top/1,
         new_nodes_can_mine_and_sync_fast_minimal_chain_with_pow/1,
         restore_db_backup_on_old_node/1,
         old_node_can_receive_chain_from_other_old_node/1,
         new_node_accepts_long_old_chain_from_old_node_up_to_height_of_new_protocol/1,
         new_node_can_receive_short_old_chain_from_old_node/1,
         old_chain_has_no_contracts_in_top_block_state/1,
         new_node_can_mine_on_old_chain_using_old_protocol/1,
         new_node_can_mine_on_old_chain_using_new_protocol/1,
         new_node_can_mine_old_spend_tx_without_payload_using_new_protocol/1,
         new_node_can_mine_spend_tx_on_old_chain_using_old_protocol/1,
         new_node_can_mine_spend_tx_on_old_chain_using_new_protocol/1,
         new_node_can_mine_contract_on_old_chain_using_old_protocol/1,
         new_node_can_mine_contract_on_old_chain_using_new_protocol/1
        ]).

%=== INCLUDES ==================================================================

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

%=== MACROS ====================================================================

-define(LATEST_DOCKER_IMAGE, "aeternity/epoch:v0.11.1").
-define(TESTED_DOCKER_IMAGE, "aeternity/epoch:local").

-define(DB_BACKUP_DEST_DIR, "/tmp/mnesia_backup").

-define(HEIGHT_OF_NEW_PROTOCOL(OldChainHeight),
        (2 + OldChainHeight)
       ).
-define(HEIGHT_OF_NEW_PROTOCOL_FOR_VALIDATING_BLOCKS(OldChainHeight),
        (- 3 + OldChainHeight)
       ).

-define(HEIGHT_OF_NEW_PROTOCOL_UNREACHABLE(OldChainHeight),
        (1000000000 + OldChainHeight)
       ).

-define(CUCKOO_MINER(N),
        #{ex => list_to_binary("mean" ++ integer_to_list(N) ++ "s-generic"),
          args => <<"-t 5">>,
          bits => N}
       ).

-define(OLD_NODE1, #{
          name    => old_node1,
          peers   => [],
          backend => aest_docker,
          source  => {pull, ?LATEST_DOCKER_IMAGE},
          mine_rate => default
         }).

-define(OLD_NODE2, #{
          name    => old_node2,
          peers   => [old_node1],
          backend => aest_docker,
          source  => {pull, ?LATEST_DOCKER_IMAGE},
          mine_rate => default
}).

-define(NEW_NODE1(Ps), #{
          name    => new_node1,
          peers   => [],
          backend => aest_docker,
          source  => {pull, ?TESTED_DOCKER_IMAGE},
          mine_rate => default,
          hard_forks => Ps
         }).

-define(NEW_NODE2(Ps), #{
          name    => new_node2,
          peers   => [old_node1],
          backend => aest_docker,
          source  => {pull, ?TESTED_DOCKER_IMAGE},
          mine_rate => default,
          hard_forks => Ps
         }).

-define(NEW_NODE3(Ps), #{
          name    => new_node3,
          peers   => [old_node1],
          backend => aest_docker,
          source  => {pull, ?TESTED_DOCKER_IMAGE},
          mine_rate => default,
          hard_forks => Ps
         }).

-define(NEW_NODE4(Ps), #{
          name    => new_node4,
          peers   => [new_node3],
          backend => aest_docker,
          source  => {pull, ?TESTED_DOCKER_IMAGE},
          mine_rate => default,
          hard_forks => Ps
         }).

-define(FAST_NEW_NODE1(Ps), #{
          name    => fast_new_node1,
          peers   => [],
          backend => aest_docker,
          source  => {pull, ?TESTED_DOCKER_IMAGE},
          mine_rate => 1000,
          cuckoo_miner => ?CUCKOO_MINER(16),
          hard_forks => Ps
         }).

-define(FAST_NEW_NODE2(Ps), #{
          name    => fast_new_node2,
          peers   => [fast_new_node1],
          backend => aest_docker,
          source  => {pull, ?TESTED_DOCKER_IMAGE},
          mine_rate => 1000,
          cuckoo_miner => ?CUCKOO_MINER(16),
          hard_forks => Ps
         }).

-define(is_testcase_in_group_assumptions(C),
        ( (C =:= old_node_persisting_chain_and_not_mining_has_genesis_as_top)
          or (C =:= new_node_persisting_chain_and_not_mining_has_same_old_genesis_as_top)
          or (C =:= new_nodes_can_mine_and_sync_fast_minimal_chain_with_pow)
        )).

%=== COMMON TEST FUNCTIONS =====================================================

all() ->
    [
     {group, assumptions},
     {group, hard_fork},
     {group, hard_fork_with_tx},
     {group, hard_fork_with_contract}
    ].

groups() ->
    [
     {assumptions,
      [
       {genesis,
        [sequence], %% Hard deps among tests.
        [
         old_node_persisting_chain_and_not_mining_has_genesis_as_top,
         new_node_persisting_chain_and_not_mining_has_same_old_genesis_as_top
        ]},
       new_nodes_can_mine_and_sync_fast_minimal_chain_with_pow
      ]},
     {hard_fork,
      [sequence], %% Hard deps among tests/groups.
      [
       restore_db_backup_on_old_node, %% Determines info of top of chain in DB backup.
       {group, hard_fork_all}
      ]},
     {hard_fork_all,
      [sequence], %% Soft deps among tests/groups: if a test/group fails better skipping the rest.
      [
       old_node_can_receive_chain_from_other_old_node,
       new_node_accepts_long_old_chain_from_old_node_up_to_height_of_new_protocol,
       {group, upgrade_flow_smoke_test}
      ]},
     {upgrade_flow_smoke_test,
      [sequence], %% Hard deps among tests/groups.
      [
       new_node_can_receive_short_old_chain_from_old_node,
       old_chain_has_no_contracts_in_top_block_state,
       new_node_can_mine_on_old_chain_using_old_protocol,
       new_node_can_mine_on_old_chain_using_new_protocol
      ]},
     {hard_fork_with_tx,
      [sequence],
      [
       restore_db_backup_on_old_node, %% Determines info of top of chain in DB backup.
       {group, hard_fork_all_with_tx}
      ]},
     {hard_fork_all_with_tx,
      [sequence],
      [
       {group, old_spend_tx_in_new_protocol_smoke_test},
       %% {group, hard_fork_old_chain_with_tx}, Not applicable as is in 0.12.0 because new node's user API creates only new spend tx.
       {group, hard_fork_new_chain_with_tx}
      ]},
     {old_spend_tx_in_new_protocol_smoke_test,
      [sequence],
      [
       new_node_can_receive_short_old_chain_from_old_node,
       new_node_can_mine_old_spend_tx_without_payload_using_new_protocol
      ]},
     {hard_fork_old_chain_with_tx,
      [sequence],
      [
       new_node_can_receive_short_old_chain_from_old_node,
       new_node_can_mine_spend_tx_on_old_chain_using_old_protocol
      ]},
     {hard_fork_new_chain_with_tx,
      [sequence],
      [
       new_node_can_receive_short_old_chain_from_old_node,
       new_node_can_mine_spend_tx_on_old_chain_using_new_protocol
      ]},
     {hard_fork_with_contract,
      [sequence],
      [
       restore_db_backup_on_old_node, %% Determines info of top of chain in DB backup.
       {group, hard_fork_all_with_contract}
      ]},
     {hard_fork_all_with_contract,
      [sequence],
      [
       {group, hard_fork_old_chain_with_contract},
       {group, hard_fork_new_chain_with_contract}
      ]},
     {hard_fork_old_chain_with_contract,
      [sequence],
      [
       new_node_can_receive_short_old_chain_from_old_node,
       new_node_can_mine_contract_on_old_chain_using_old_protocol
      ]},
     {hard_fork_new_chain_with_contract,
      [sequence],
      [
       new_node_can_receive_short_old_chain_from_old_node,
       new_node_can_mine_contract_on_old_chain_using_new_protocol
      ]}
    ].

suite() ->
    [
     {require, db_backup_tar},
     {require, db_backup_content}
    ].

init_per_suite(Config) ->
    %% Skip gracefully if no hard forks - without need to delete test suite.
    case aec_governance:sorted_protocol_versions() of
        [_] = ConsensusVersions ->
            {skip, {no_hard_forks, ConsensusVersions}};
        [_,_|_] ->
            %% Skip gracefully if DB backup absent.
            Tar = db_backup_tar(Config),
            ct:log("Attempting to read DB backup ~s", [Tar]),
            case file:read_file(Tar) of
                {error, enoent} -> {skip, {missing_db_backup, Tar}};
                {ok, _TarBin} -> Config
            end
    end.

end_per_suite(_Config) ->
    ok.

init_per_group(Group, Config)
  when Group =:= hard_fork_all; Group =:= hard_fork_all_with_tx ->
    {_, {restore_db_backup_on_old_node, SavedCfg}} =
        proplists:lookup(saved_config, Config),
    [{_, _} = proplists:lookup(db_backup_top_height, SavedCfg),
     {_, _} = proplists:lookup(db_backup_top_hash, SavedCfg)
     | Config];
init_per_group(hard_fork_all_with_contract, Config) ->
    {_, {restore_db_backup_on_old_node, SavedCfg}} =
        proplists:lookup(saved_config, Config),
    %% Taken from aehttp_integration_SUITE:contract_transactions.
    Code = <<"0x36600080376200002160008080805180516004146200003057505B50600119"
             "51005B60005260206000F35B80905090565B602001517F6D61696E0000000000"
             "0000000000000000000000000000000000000000000000146200006157620000"
             "1A565B602001519050809150506200002A56">>,
    DecodedCode = aeu_hex:hexstring_decode(Code),
    [{_, _} = proplists:lookup(db_backup_top_height, SavedCfg),
     {_, _} = proplists:lookup(db_backup_top_hash, SavedCfg),
     {contract_code, Code}, {contract_call_data, Code},
     {decoded_contract_code, DecodedCode},
     {decoded_contract_call_data, DecodedCode},
     {contract_tx_vm_version, 1}, {contract_tx_deposit, 5},
     {contract_tx_amount, 10}, {contract_tx_gas, 1000},
     {contract_tx_gas_price, 3}, {contract_tx_fee, 1},
     {contract_function, <<"main">>}, {contract_arguments, <<"42">>}
     | Config];
init_per_group(Group, Config)
  when Group =:= upgrade_flow_smoke_test;
       Group =:= old_spend_tx_in_new_protocol_smoke_test;
       Group =:= hard_fork_new_chain_with_tx;
       Group =:= hard_fork_new_chain_with_contract ->
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Config),
    NewConfig = aest_nodes:ct_setup(Config),
    Ps = protocols(?HEIGHT_OF_NEW_PROTOCOL(TopHeight)),
    aest_nodes:setup_nodes(
      [?OLD_NODE1,
       ?NEW_NODE3(Ps),
       ?NEW_NODE4(Ps)], NewConfig),
    NewConfig;
init_per_group(Group, Config)
  when Group =:= hard_fork_old_chain_with_tx;
       Group =:= hard_fork_old_chain_with_contract ->
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Config),
    NewConfig = aest_nodes:ct_setup(Config),
    Ps = protocols(?HEIGHT_OF_NEW_PROTOCOL_UNREACHABLE(TopHeight)),
    aest_nodes:setup_nodes(
      [?OLD_NODE1,
       ?NEW_NODE3(Ps),
       ?NEW_NODE4(Ps)], NewConfig),
    NewConfig;
init_per_group(_, Config) -> Config.

end_per_group(Group, Config)
  when Group =:= upgrade_flow_smoke_test;
       Group =:= old_spend_tx_in_new_protocol_smoke_test;
       Group =:= hard_fork_old_chain_with_tx;
       Group =:= hard_fork_new_chain_with_tx;
       Group =:= hard_fork_old_chain_with_contract;
       Group =:= hard_fork_new_chain_with_contract ->
    aest_nodes:ct_cleanup(Config);
end_per_group(_, _) -> ok.

init_per_testcase(TC, Config) when
      ?is_testcase_in_group_assumptions(TC);
      TC =:= restore_db_backup_on_old_node;
      TC =:= old_node_can_receive_chain_from_other_old_node;
      TC =:= new_node_accepts_long_old_chain_from_old_node_up_to_height_of_new_protocol ->
    aest_nodes:ct_setup(Config);
init_per_testcase(_, Config) -> Config.

end_per_testcase(TC, Config) when
      ?is_testcase_in_group_assumptions(TC);
      TC =:= restore_db_backup_on_old_node;
      TC =:= old_node_can_receive_chain_from_other_old_node;
      TC =:= new_node_accepts_long_old_chain_from_old_node_up_to_height_of_new_protocol ->
    aest_nodes:ct_cleanup(Config);
end_per_testcase(_, _) -> ok.

%=== TEST CASES ================================================================

old_node_persisting_chain_and_not_mining_has_genesis_as_top(Cfg) ->
    aest_nodes:setup_nodes([?OLD_NODE1], Cfg),
    start_node(int_http, old_node1, Cfg),
    #{height := 0} = get_block_by_height(int_http, old_node1, 0, Cfg),
    #{height := 0, hash := Hash} = aest_nodes:get_top(old_node1, Cfg),
    aest_nodes:kill_node(old_node1, Cfg),
    {save_config,
     [{genesis_hash, Hash}]}.

new_node_persisting_chain_and_not_mining_has_same_old_genesis_as_top(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, Hash} = proplists:lookup(genesis_hash, SavedCfg),
    aest_nodes:setup_nodes([?NEW_NODE1(protocols(1 + old_protocol_height()))], Cfg),
    start_node(new_node1, Cfg),
    #{height := 0} = get_block_by_height(new_node1, 0, Cfg),
    #{height := 0, hash := NewHash} = aest_nodes:get_top(new_node1, Cfg),
    ?assertEqual(Hash, NewHash),
    aest_nodes:kill_node(new_node1, Cfg),
    ok.

new_nodes_can_mine_and_sync_fast_minimal_chain_with_pow(Cfg) ->
    Ps = fast_protocols(15),
    HCheck = maps:get(new_protocol_version(), Ps),
    aest_nodes:setup_nodes([?FAST_NEW_NODE1(Ps),
                            ?FAST_NEW_NODE2(Ps)], Cfg),
    start_node(fast_new_node1, Cfg),
    ok = run_erl_cmd_on_node(fast_new_node1, "aec_conductor:start_mining().", 10000, Cfg), %% It would be better to configure node to autostart mining in the first place.
    wait_for_height_syncing(HCheck, [fast_new_node1], {{45000, ms}, {5, blocks}}, Cfg),
    start_node(fast_new_node2, Cfg),
    #{hash := HashMined} = get_block_by_height(fast_new_node1, HCheck, Cfg),
    wait_for_height_syncing(HCheck, [fast_new_node2], {{45000, ms}, {5, blocks}}, Cfg),
    ?assertEqual(HashMined, maps:get(hash, get_block_by_height(fast_new_node2, HCheck, Cfg))),
    ok.

%% Old node can restore DB backup of testnet.
restore_db_backup_on_old_node(Cfg) ->
    aest_nodes:setup_nodes([?OLD_NODE1], Cfg),
    start_node(int_http, old_node1, Cfg),
    {ok, {TopHash, TopHeight}} = restore_db_backup_on_node_and_check_top(int_http, old_node1, Cfg),
    aest_nodes:kill_node(old_node1, Cfg),
    {save_config,
     [{db_backup_top_height, TopHeight},
      {db_backup_top_hash, TopHash}]}.

%% Old node can receive (sync) chain from other old node that restored
%% DB from backup.
old_node_can_receive_chain_from_other_old_node(Cfg) ->
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    aest_nodes:setup_nodes([?OLD_NODE1, ?OLD_NODE2], Cfg),
    start_node(int_http, old_node1, Cfg),
    {ok, {TopHash, TopHeight}} = restore_db_backup_on_node(old_node1, Cfg),
    start_node(int_http, old_node2, Cfg),
    aest_nodes:wait_for_value({height, TopHeight}, [old_node1], 5000, Cfg),
    wait_for_height_syncing(TopHeight, [old_node2], {{45000, ms}, {200, blocks}}, Cfg),
    B = get_block_by_height(int_http, old_node2, TopHeight, Cfg),
    ?assertEqual(TopHash, maps:get(hash, B)),
    aest_nodes:kill_node(old_node2, Cfg),
    aest_nodes:kill_node(old_node1, Cfg),
    ok.

%% New node accepts (sync) from old node that restored DB from backup
%% old chain only up to configured height for new protocol.
new_node_accepts_long_old_chain_from_old_node_up_to_height_of_new_protocol(Cfg) ->
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    HeightOfNewProtocolForValidatingBlocks =
        ?HEIGHT_OF_NEW_PROTOCOL_FOR_VALIDATING_BLOCKS(TopHeight),
    aest_nodes:setup_nodes(
      [?OLD_NODE1,
       ?NEW_NODE2(protocols(HeightOfNewProtocolForValidatingBlocks))], Cfg),
    start_node(int_http, old_node1, Cfg),
    {ok, {TopHash, TopHeight}} = restore_db_backup_on_node(old_node1, Cfg),
    aest_nodes:wait_for_value({height, TopHeight}, [old_node1], 5000, Cfg),
    start_node(new_node2, Cfg),
    LastSyncedOldBlock = - 1 + HeightOfNewProtocolForValidatingBlocks,
    wait_for_height_syncing(LastSyncedOldBlock, [new_node2], {{45000, ms}, {200, blocks}}, Cfg),
    B1 = get_block_by_height(int_http, old_node1, LastSyncedOldBlock, Cfg),
    %% Node 2 does not mine.
    B2 = get_block_by_height(new_node2, LastSyncedOldBlock, Cfg),
    ?assertEqual(maps:get(hash, B1), maps:get(hash, B2)),
    ?assertMatch(
       {ok, 404, _},
       aest_nodes:http_get(new_node2, int_http, [v2, block, height, TopHeight], #{}, Cfg)),
    ?assertMatch(
       {ok, 404, _},
       aest_nodes:http_get(new_node2, int_http, [v2, block, height, HeightOfNewProtocolForValidatingBlocks], #{}, Cfg)),
    aest_nodes:kill_node(new_node2, Cfg),
    aest_nodes:kill_node(old_node1, Cfg),
    ok.

%% New node can receive (sync) old chain from old node that restored
%% DB from backup - case old chain of height lower than height of new
%% protocol.
new_node_can_receive_short_old_chain_from_old_node(Cfg) ->
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    start_node(int_http, old_node1, Cfg),
    {ok, {TopHash, TopHeight}} = restore_db_backup_on_node(old_node1, Cfg),
    aest_nodes:wait_for_value({height, TopHeight}, [old_node1], 5000, Cfg),
    start_node(new_node3, Cfg),
    wait_for_height_syncing(TopHeight, [new_node3], {{45000, ms}, {200, blocks}}, Cfg),
    B = get_block_by_height(new_node3, TopHeight, Cfg),
    ?assertEqual(TopHash, maps:get(hash, B)),
    {save_config,
     [{old_node_left_running_with_old_chain, old_node1},
      {new_node_left_running_with_synced_old_chain, new_node3}]}.

old_chain_has_no_contracts_in_top_block_state(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, old_node1} = proplists:lookup(old_node_left_running_with_old_chain, SavedCfg),
    {_, new_node3} = proplists:lookup(new_node_left_running_with_synced_old_chain, SavedCfg),
    {_, _TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    ErlCmd =
        make_erl_cmd(
          "{{ok, H}, _} = {aec_base58c:safe_decode(block_hash, ~w), decode_hash},~n"
          "{{_, Ts}, _} = {aec_chain:get_block_state(H), get_state},~n"
          "{{contract_tree, CT}, _} = {aec_trees:contracts(Ts), get_contract_tree},~n"
          "{Cs, _} = {aeu_mtrees:to_list(CT), get_contract_list},~n"
          "length(Cs).", [TopHash]),
    0 = run_erl_cmd_on_node(new_node3, ErlCmd, 30000, Cfg),
    {save_config,
     [{old_node_left_running_with_old_chain, old_node1},
      {new_node_left_running_with_synced_old_chain, new_node3}]}.

%% New node can mine on top of short old chain up to max effective
%% height of old protocol.
new_node_can_mine_on_old_chain_using_old_protocol(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, old_node1} = proplists:lookup(old_node_left_running_with_old_chain, SavedCfg),
    {_, new_node3} = proplists:lookup(new_node_left_running_with_synced_old_chain, SavedCfg),
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, _TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    OldProtocolVersion = old_protocol_version(),
    HeightOfNewProtocol = ?HEIGHT_OF_NEW_PROTOCOL(TopHeight),
    #{version := OldProtocolVersion, %% TODO Check mining capability with all protocols - not only the last one.
      height := TopHeight} = aest_nodes:get_top(new_node3, Cfg),
    HeightToBeMinedWithOldProtocol = - 1 + HeightOfNewProtocol,
    {true, _} = {HeightToBeMinedWithOldProtocol > TopHeight,
                 {check_at_least_a_block_to_mine_using_old_protocol,
                  HeightToBeMinedWithOldProtocol}},
    {ok, 404, _} = aest_nodes:http_get(new_node3, int_http, [v2, block, height, HeightToBeMinedWithOldProtocol], #{}, Cfg),
    start_node(new_node4, Cfg),
    wait_for_height_syncing(TopHeight, [new_node4], {{45000, ms}, {200, blocks}}, Cfg),
    ok = mock_pow_on_node(new_node3, Cfg), %% TODO Make configurable.
    ok = mock_pow_on_node(new_node4, Cfg), %% TODO Make configurable.
    ok = mock_pow_on_node(old_node1, Cfg), %% TODO Make configurable.
    ok = run_erl_cmd_on_node(new_node3, "aec_conductor:start_mining().", 10000, Cfg), %% It would be better to: stop container, reinstantiate config template, start container.
    wait_for_height_syncing(HeightToBeMinedWithOldProtocol, [new_node3], {{10000, ms}, {1000, blocks}}, Cfg),
    #{version := OldProtocolVersion, %% TODO Check mining capability with all protocols - not only the last one.
      hash := HashMined} = get_block_by_height(new_node3, HeightToBeMinedWithOldProtocol, Cfg),
    %% Ensure distinct non-mining new node can sync mined block(s).
    wait_for_height_syncing(HeightToBeMinedWithOldProtocol, [new_node4], {{45000, ms}, {200, blocks}}, Cfg),
    ?assertEqual(HashMined, maps:get(hash, get_block_by_height(new_node4, HeightToBeMinedWithOldProtocol, Cfg))),
    %% Ensure distinct non-mining old node can sync mined block(s).
    wait_for_height_syncing(HeightToBeMinedWithOldProtocol, [old_node1], {{45000, ms}, {200, blocks}}, Cfg),
    ?assertEqual(HashMined, maps:get(hash, get_block_by_height(int_http, old_node1, HeightToBeMinedWithOldProtocol, Cfg))),
    aest_nodes:kill_node(old_node1, Cfg),
    {save_config,
     [{new_node_left_mining_with_mined_old_protocol, new_node3},
      {new_node_left_running_with_mined_old_protocol, new_node4}]}.

%% New node can mine on top of old chain further to max effective
%% height of old protocol.
new_node_can_mine_on_old_chain_using_new_protocol(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, new_node3} = proplists:lookup(new_node_left_mining_with_mined_old_protocol, SavedCfg),
    {_, new_node4} = proplists:lookup(new_node_left_running_with_mined_old_protocol, SavedCfg),
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, _TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    NewProtocolVersion = new_protocol_version(),
    HeightOfNewProtocol = ?HEIGHT_OF_NEW_PROTOCOL(TopHeight),
    HeightToBeMinedWithNewProtocol = 1 + HeightOfNewProtocol, %% I.e. two blocks with new protocol.
    wait_for_height_syncing(HeightToBeMinedWithNewProtocol, [new_node3], {{10000, ms}, {1000, blocks}}, Cfg),
    #{version := NewProtocolVersion,
      hash := HashMined} = get_block_by_height(new_node3, HeightToBeMinedWithNewProtocol, Cfg),
    %% Ensure distinct non-mining node can sync mined block(s).
    wait_for_height_syncing(HeightToBeMinedWithNewProtocol, [new_node4], {{45000, ms}, {1000, blocks}}, Cfg),
    ?assertEqual(HashMined, maps:get(hash, get_block_by_height(new_node4, HeightToBeMinedWithNewProtocol, Cfg))),
    aest_nodes:kill_node(new_node4, Cfg),
    aest_nodes:kill_node(new_node3, Cfg),
    ok.

new_node_can_mine_old_spend_tx_without_payload_using_new_protocol(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, old_node1} = proplists:lookup(old_node_left_running_with_old_chain, SavedCfg),
    {_, new_node3} = proplists:lookup(new_node_left_running_with_synced_old_chain, SavedCfg),
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, _TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    start_node(new_node4, Cfg),
    wait_for_height_syncing(TopHeight, [new_node4], {{45000, ms}, {200, blocks}}, Cfg),
    ok = mock_pow_on_node(old_node1, Cfg), %% TODO Make configurable.
    ok = mock_pow_on_node(new_node3, Cfg), %% TODO Make configurable.
    ok = mock_pow_on_node(new_node4, Cfg), %% TODO Make configurable.
    %% Mine on old node - so to accrue enough tokens to send spend tx
    %% from there.  Stop mining on old node when sufficient tokens for
    %% a spend tx (assumptions: spend tx with fee 1 and amount 1 is
    %% ok, block mined reward is at least 2).
    SpendTxFee = 1,
    SpendTxAmount = 1,
    HeightOfNewProtocol = ?HEIGHT_OF_NEW_PROTOCOL(TopHeight),
    HeightToBeMinedWithOldProtocol = - 1 + HeightOfNewProtocol,
    {true, _} = {HeightToBeMinedWithOldProtocol > TopHeight,
                 {check_at_least_a_block_to_mine_using_old_protocol,
                  HeightToBeMinedWithOldProtocol}},
    ok = run_erl_cmd_on_node(old_node1, "aec_conductor:start_mining().", 10000, Cfg), %% It would be better to: stop container, reinstantiate config template, start container.
    wait_for_height_syncing(HeightToBeMinedWithOldProtocol, [old_node1], {{10000, ms}, {1000, blocks}}, Cfg),
    %% TODO Stopping conductor times out. It is fine to leave node running as anyway blocks above height of new consensus are ignored by new nodes.
    %% ok = run_erl_cmd_on_node(old_node1, "aec_conductor:stop_mining().", 10000, Cfg), %% It would be better to: stop container, reinstantiate config template, start container.
    %% Check new node synced chain fully mined with old protocol.
    %% TODO Check new node in sync with old node - for catching errors earlier.
    wait_for_height_syncing(HeightToBeMinedWithOldProtocol, [new_node3], {{10000, ms}, {1000, blocks}}, Cfg),
    %% Check that new node sees mining reward of old node.
    Sender = get_public_key(old_node1, Cfg),
    SenderBalanceAtLastBlockWithOldProtocol = get_balance(new_node3, Sender, Cfg),
    ?assertMatch(
       {true, _},
       {SenderBalanceAtLastBlockWithOldProtocol > (SpendTxFee + SpendTxAmount),
        SenderBalanceAtLastBlockWithOldProtocol}),
    %% Post spend tx on old node.
    %% TODO Ensure in mempool of old node - for catching errors earlier.
    %% TODO Ensure in mempool of new node - for catching errors earlier.
    Recipient = get_public_key(new_node4, Cfg),
    RecipientBalanceAtLastBlockWithOldProtocol = get_balance(new_node3, Recipient, Cfg),
    ok = post_spend_tx(old_node1, Recipient, SpendTxAmount, SpendTxFee, Cfg),
    %% Make new node to mine.
    ok = run_erl_cmd_on_node(new_node3, "aec_conductor:start_mining().", 10000, Cfg), %% It would be better to: stop container, reinstantiate config template, start container.
    %% Check spend tx processed.
    {SpendTxBlockHash, SpendTxHeight} =
        wait_spend_tx_in_chain(new_node3, Sender, Recipient, SpendTxAmount, SpendTxFee, Cfg),
    NewProtocolVersion = new_protocol_version(),
    #{version := NewProtocolVersion,
      hash := SpendTxBlockHash} = get_block_by_height(new_node3, SpendTxHeight, Cfg),
    ?assertEqual(SpendTxAmount + RecipientBalanceAtLastBlockWithOldProtocol,
                 get_balance(new_node3, Recipient, Cfg)),
    %% Check other new node syncs.
    wait_for_height_syncing(SpendTxHeight, [new_node4], {{10000, ms}, {1000, blocks}}, Cfg),
    ?assertEqual(SpendTxBlockHash, maps:get(hash, get_block_by_height(new_node4, SpendTxHeight, Cfg))),
    aest_nodes:kill_node(new_node4, Cfg),
    aest_nodes:kill_node(new_node3, Cfg),
    aest_nodes:kill_node(old_node1, Cfg),
    ok.

%% New node can sync the old chain from old node and can start mining
%% on the top of the old chain. The new node can mine blocks using the
%% old protocol and include spend transaction in the blocks. The block
%% with the spend transaction can be synced among old and other new
%% nodes.
new_node_can_mine_spend_tx_on_old_chain_using_old_protocol(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, old_node1} = proplists:lookup(old_node_left_running_with_old_chain, SavedCfg),
    {_, new_node3} = proplists:lookup(new_node_left_running_with_synced_old_chain, SavedCfg),
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, _TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    OldProtocolVersion = old_protocol_version(),
    start_node(new_node4, Cfg),
    wait_for_height_syncing(TopHeight, [new_node4], {{45000, ms}, {200, blocks}}, Cfg),
    ok = mock_pow_on_node(new_node3, Cfg),
    ok = mock_pow_on_node(new_node4, Cfg),
    ok = mock_pow_on_node(old_node1, Cfg),
    %% Get public key of account meant to be recipient of tokens and make sure its balance is 0.
    PubKey1 = get_public_key(old_node1, Cfg),
    Balance1 = get_balance(old_node1, PubKey1, Cfg),
    ?assertEqual(0, Balance1),
    ct:log("Balance of account with public key ~p is ~p", [PubKey1, Balance1]),
    %% Get public key of account meant to be spender of tokens and make sure it has a sufficient balance by means of mining.
    PubKey3 = get_public_key(new_node3, Cfg),
    Balance3 = get_balance(new_node3, PubKey3, Cfg),
    ct:log("Balance of account with public key ~p is ~p", [PubKey3, Balance3]),
    ok = run_erl_cmd_on_node(new_node3, "aec_conductor:start_mining().", 10000, Cfg),
    MinedReward = 100,
    aest_nodes:wait_for_value({balance, PubKey3, MinedReward}, [new_node3], 10000, Cfg),
    MinedBalance = get_balance(new_node3, PubKey3, Cfg),
    ?assert(MinedBalance >= MinedReward),
    ct:log("Mined balance on ~p with public key ~p is ~p", [new_node3, PubKey3, MinedBalance]),
    %% Send spend transaction and make sure recipient account received the tokens.
    Fee = 5,
    BalanceToSpend = MinedBalance - Fee,
    {SpendTxBlockHash, SpendTxHeight} =
        post_spend_tx_and_wait_in_chain(new_node3, PubKey3, PubKey1, BalanceToSpend, Fee, Cfg),
    %% Block with spend transaction has old version.
    ?assertEqual(
       OldProtocolVersion,
       maps:get(version, get_block_by_hash(new_node3, SpendTxBlockHash, Cfg))),
    %% Sync the chain with the block that includes spend tx on an old node.
    wait_for_height_syncing(SpendTxHeight, [old_node1], {{100000, ms}, {1000, blocks}}, Cfg),
    ?assertEqual(SpendTxBlockHash, maps:get(hash, get_block_by_height(int_http, old_node1, SpendTxHeight, Cfg))),
    %% Sync the chain with the block that includes spend tx on another new node.
    wait_for_height_syncing(SpendTxHeight, [new_node4], {{100000, ms}, {1000, blocks}}, Cfg),
    ?assertEqual(SpendTxBlockHash, maps:get(hash, get_block_by_height(new_node4, SpendTxHeight, Cfg))),
    ok.

%% New node can sync the old chain from old node and can start mining
%% on the top of the old chain until a certain height where it switches to the
%% new protocol. The new node can mine blocks using the new protocol and include
%% spend transaction in the blocks. The block with spend transaction can be
%% synced among other new nodes.
new_node_can_mine_spend_tx_on_old_chain_using_new_protocol(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, old_node1} = proplists:lookup(old_node_left_running_with_old_chain, SavedCfg),
    {_, new_node3} = proplists:lookup(new_node_left_running_with_synced_old_chain, SavedCfg),
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, _TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    OldProtocolVersion = old_protocol_version(),
    NewProtocolVersion = new_protocol_version(),
    HeightOfNewProtocol = ?HEIGHT_OF_NEW_PROTOCOL(TopHeight),
    start_node(new_node4, Cfg),
    wait_for_height_syncing(TopHeight, [new_node4], {{45000, ms}, {200, blocks}}, Cfg),
    ok = mock_pow_on_node(new_node3, Cfg),
    ok = mock_pow_on_node(new_node4, Cfg),
    %% Get public key of account meant to be recipient of tokens and make sure its balance is 0.
    PubKey1 = get_public_key(old_node1, Cfg),
    Balance1 = get_balance(old_node1, PubKey1, Cfg),
    ?assertEqual(0, Balance1),
    ct:log("Balance of account with public key ~p is ~p", [PubKey1, Balance1]),
    %% Kill old node - not needed.
    aest_nodes:kill_node(old_node1, Cfg),
    %% Get public key of account meant to be spender of tokens. (This account will accrue sufficient balance by means of mining.)
    PubKey3 = get_public_key(new_node3, Cfg),
    Balance3 = get_balance(new_node3, PubKey3, Cfg),
    ct:log("Balance of account with public key ~p is ~p", [PubKey3, Balance3]),
    %% Reach height of switch to new protocol.
    ok = run_erl_cmd_on_node(new_node3, "aec_conductor:start_mining().", 10000, Cfg),
    LastHeightOfOldProtocol = HeightOfNewProtocol - 1,
    %% Check the last block of old protocol has old version.
    wait_for_height_syncing(LastHeightOfOldProtocol, [new_node3], {{10000, ms}, {1000, blocks}}, Cfg),
    B3OldProtocol = get_block_by_height(new_node3, LastHeightOfOldProtocol, Cfg),
    ?assertEqual(OldProtocolVersion, maps:get(version, B3OldProtocol)),
    %% Check the first block of new protocol has version of the new protocol.
    wait_for_height_syncing(HeightOfNewProtocol, [new_node3], {{10000, ms}, {1000, blocks}}, Cfg),
    B3NewProtocol = get_block_by_height(new_node3, HeightOfNewProtocol, Cfg),
    ?assertEqual(NewProtocolVersion, maps:get(version, B3NewProtocol)),
    %% Make sure account meant to be spender of tokens has a sufficient balance by means of mining.
    MinedReward = 100,
    aest_nodes:wait_for_value({balance, PubKey3, MinedReward}, [new_node3], 10000, Cfg),
    MinedBalance = get_balance(new_node3, PubKey3, Cfg),
    ?assert(MinedBalance >= MinedReward),
    ct:log("Mined balance on ~p with public key ~p is ~p", [new_node3, PubKey3, MinedBalance]),
    %% Send spend transaction and make sure recipient account received the tokens.
    Fee = 5,
    BalanceToSpend = MinedBalance - Fee,
    {SpendTxBlockHash, SpendTxHeight} =
        post_spend_tx_and_wait_in_chain(new_node3, PubKey3, PubKey1, BalanceToSpend, Fee, Cfg),
    %% Block with spend transaction has new protocol version.
    ?assertEqual(
       NewProtocolVersion,
       maps:get(version, get_block_by_hash(new_node3, SpendTxBlockHash, Cfg))),
    %% Sync the chain with the block that includes spend tx on another new node.
    wait_for_height_syncing(SpendTxHeight, [new_node4], {{100000, ms}, {1000, blocks}}, Cfg),
    ?assertEqual(SpendTxBlockHash, maps:get(hash, get_block_by_height(new_node4, SpendTxHeight, Cfg))),
    ok.

%% New node can sync the old chain from old node and can start mining
%% on the top of the old chain. The new node can mine blocks using the
%% old protocol and include contract create, contract call and contract
%% call compute(?) transactions in the blocks. The blocks with the
%% contract transactions can be synced among old and other new nodes.
new_node_can_mine_contract_on_old_chain_using_old_protocol(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, old_node1} = proplists:lookup(old_node_left_running_with_old_chain, SavedCfg),
    {_, new_node3} = proplists:lookup(new_node_left_running_with_synced_old_chain, SavedCfg),
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, _TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    OldProtocolVersion = old_protocol_version(),
    start_node(new_node4, Cfg),
    wait_for_height_syncing(TopHeight, [new_node4], {{100000, ms}, {1000, blocks}}, Cfg),
    ok = mock_pow_on_node(new_node3, Cfg),
    ok = mock_pow_on_node(new_node4, Cfg),
    %% Kill old node - syncing of blocks with contract transactions is not tested.
    aest_nodes:kill_node(old_node1, Cfg),
    %% expected_mine_rate is lowered so contract gets mined faster.
    ErlCmd = make_erl_cmd("application:set_env(aecore, expected_mine_rate, ~p)", [10]),
    ok = run_erl_cmd_on_node(new_node3, ErlCmd, Cfg),
    ok = run_erl_cmd_on_node(new_node4, ErlCmd, Cfg),
    %% Get public key of account meant to be creator of contract and make sure it has a sufficient balance by means of mining.
    {ok, 200, #{pub_key := PubKey3}} = request(new_node3, 'GetPubKey', #{}, Cfg),
    %% Balance is 0.
    {ok, 404, #{reason := <<"Account not found">>}} =
        request(new_node3, 'GetAccountBalance', #{account_pubkey => PubKey3}, Cfg),
    ct:log("Balance of account with public key ~p is ~p", [PubKey3, 0]),
    ok = run_erl_cmd_on_node(new_node3, "aec_conductor:start_mining().", 10000, Cfg),
    %% 100 should be enough.
    MinedReward = 100,
    aest_nodes:wait_for_value({balance, PubKey3, MinedReward}, [new_node3], 10000, Cfg),
    {ok, 200, #{balance := MinedBalance}} =
        request(new_node3, 'GetAccountBalance', #{account_pubkey => PubKey3}, Cfg),
    ?assert(MinedBalance >= MinedReward),
    ct:log("Mined balance on ~p with public key ~p is ~p", [new_node3, PubKey3, MinedBalance]),
    %% Make sure there are no contracts related to the account.
    ?assertMatch(
       {ok, 200, #{transactions := []}},
       request(new_node3, 'GetAccountTransactions',
               #{account_pubkey => PubKey3, tx_types => contract_create_tx, tx_encoding => json}, Cfg)),
    %% Create contract create transaction.
    {ok, DecPubKey3} = aec_base58c:safe_decode(account_pubkey, PubKey3),
    {ContractCreate, DecContractCreate} =
        make_contract_tx(contract_create_tx, PubKey3, DecPubKey3, Cfg),
    Nonce = 1,
    #{tx := ContractCreateTx, contract_address := ContractPubKey} =
        get_contract_tx(new_node3, 'PostContractCreate', fun aect_create_tx:new/1,
                        Nonce, ContractCreate, DecContractCreate, Cfg),
    %% Post contract create transaction and wait until it's mined.
    #{block_hash := ContractBlockHash, block_height := ContractBlockHeight} =
        post_contract_tx_and_wait_in_chain(new_node3, PubKey3, Nonce, ContractPubKey, contract_create_tx,
                                           ContractCreateTx, Cfg),
    %% Check protocol version of the block with mined transaction on all nodes.
    %% Cannot smoke test that block with contract tx mined by new node with old protocol is synced by old_node1.
    check_protocol_version_on_nodes([new_node3, new_node4], OldProtocolVersion,
                                    ContractBlockHash, ContractBlockHeight, Cfg),
    %% Create contract call transaction.
    {ContractCall, DecContractCall} =
        make_contract_tx(contract_call_tx, PubKey3, DecPubKey3, ContractPubKey, Cfg),
    Nonce1 = Nonce + 1,
    #{tx := ContractCallTx} =
        get_contract_tx(new_node3, 'PostContractCall', fun aect_call_tx:new/1,
                        Nonce1, ContractCall, DecContractCall, Cfg),
    %% Post contract call transaction and wait until it's mined.
    #{block_hash := ContractCallBlockHash, block_height := ContractCallBlockHeight} =
        post_contract_tx_and_wait_in_chain(new_node3, PubKey3, Nonce1, ContractPubKey, contract_call_tx,
                                           ContractCallTx, Cfg),
    %% Check protocol version of the block with mined transacion on all nodes.
    %% Cannot smoke test that block with contract tx mined by new node with old protocol is synced by old_node1.
    check_protocol_version_on_nodes([new_node3, new_node4], OldProtocolVersion,
                                    ContractCallBlockHash, ContractCallBlockHeight, Cfg),
    %% Create contract call compute transaction.
    {ContractCallCompute, DecContractCallCompute} =
        make_contract_tx(contract_call_compute_tx, PubKey3, DecPubKey3, ContractPubKey, Cfg),
    Nonce2 = Nonce1 + 1,
    #{tx := ContractCallComputeTx} =
        get_contract_tx(new_node3, 'PostContractCallCompute', fun aect_call_tx:new/1,
                        Nonce2, ContractCallCompute, DecContractCallCompute, Cfg),
    %% Post contract call compute transaction and wait until it's mined.
    #{block_hash := ContractCallComputeBlockHash, block_height := ContractCallComputeBlockHeight} =
        post_contract_tx_and_wait_in_chain(new_node3, PubKey3, Nonce2, ContractPubKey, contract_call_compute_tx,
                                           ContractCallComputeTx, Cfg),
    %% Check protocol version of the block with mined transaction on all nodes.
    %% Cannot smoke test that block with contract tx mined by new node with old protocol is synced by old_node1.
    check_protocol_version_on_nodes([new_node3, new_node4], OldProtocolVersion,
                                    ContractCallComputeBlockHash, ContractCallComputeBlockHeight, Cfg),
    ok.

%% New node can sync the old chain from old node and can start mining
%% on the top of the old chain. The new node can mine blocks using the
%% new protocol and include contract create, contract call and contract
%% call compute transactions in the blocks. The blocks with the
%% contract transactions can be synced among other new nodes.
new_node_can_mine_contract_on_old_chain_using_new_protocol(Cfg) ->
    {_, {_Saver, SavedCfg}} = proplists:lookup(saved_config, Cfg),
    {_, old_node1} = proplists:lookup(old_node_left_running_with_old_chain, SavedCfg),
    {_, new_node3} = proplists:lookup(new_node_left_running_with_synced_old_chain, SavedCfg),
    {_, TopHeight} = proplists:lookup(db_backup_top_height, Cfg),
    {_, _TopHash} = proplists:lookup(db_backup_top_hash, Cfg),
    OldProtocolVersion = old_protocol_version(),
    NewProtocolVersion = new_protocol_version(),
    HeightOfNewProtocol = ?HEIGHT_OF_NEW_PROTOCOL(TopHeight),
    start_node(new_node4, Cfg),
    wait_for_height_syncing(TopHeight, [new_node4], {{100000, ms}, {1000, blocks}}, Cfg),
    ok = mock_pow_on_node(new_node3, Cfg),
    ok = mock_pow_on_node(new_node4, Cfg),
    %% Kill old node - not needed.
    aest_nodes:kill_node(old_node1, Cfg),
    %% expected_mine_rate is lowered so contract gets mined faster.
    ErlCmd = make_erl_cmd("application:set_env(aecore, expected_mine_rate, ~p)", [10]),
    ok = run_erl_cmd_on_node(new_node3, ErlCmd, Cfg),
    ok = run_erl_cmd_on_node(new_node4, ErlCmd, Cfg),
    %% Get public key of account meant to be creator of contract and make sure it has a sufficient balance by means of mining.
    {ok, 200, #{pub_key := PubKey3}} = request(new_node3, 'GetPubKey', #{}, Cfg),
    %% Balance is 0.
    {ok, 404, #{reason := <<"Account not found">>}} =
        request(new_node3, 'GetAccountBalance', #{account_pubkey => PubKey3}, Cfg),
    ct:log("Balance of account with public key ~p is ~p", [PubKey3, 0]),
    %% Reach height of switch to new protocol.
    ok = run_erl_cmd_on_node(new_node3, "aec_conductor:start_mining().", 10000, Cfg),
    LastHeightOfOldProtocol = HeightOfNewProtocol - 1,
    %% Check the last block of old protocol has old version.
    wait_for_height_syncing(LastHeightOfOldProtocol, [new_node3], {{10000, ms}, {1000, blocks}}, Cfg),
    {ok, 200, B3OldProtocol} =
        request(new_node3, 'GetBlockByHeight', #{height => LastHeightOfOldProtocol}, Cfg),
    ?assertEqual(OldProtocolVersion, maps:get(version, B3OldProtocol)),
    %% Check the first block of new protocol has version of the new protocol.
    wait_for_height_syncing(HeightOfNewProtocol, [new_node3], {{10000, ms}, {1000, blocks}}, Cfg),
    B3NewProtocol = get_block_by_height(new_node3, HeightOfNewProtocol, Cfg),
    {ok, 200, B3NewProtocol} =
        request(new_node3, 'GetBlockByHeight', #{height => HeightOfNewProtocol}, Cfg),
    ?assertEqual(NewProtocolVersion, maps:get(version, B3NewProtocol)),
    %% 100 should be enough.
    MinedReward = 100,
    aest_nodes:wait_for_value({balance, PubKey3, MinedReward}, [new_node3], 10000, Cfg),
    {ok, 200, #{balance := MinedBalance}} =
        request(new_node3, 'GetAccountBalance', #{account_pubkey => PubKey3}, Cfg),
    ?assert(MinedBalance >= MinedReward),
    ct:log("Mined balance on ~p with public key ~p is ~p", [new_node3, PubKey3, MinedBalance]),
    %% Make sure there are no contracts related to the account.
    ?assertMatch(
       {ok, 200, #{transactions := []}},
       request(new_node3, 'GetAccountTransactions',
               #{account_pubkey => PubKey3, tx_types => contract_create_tx, tx_encoding => json}, Cfg)),
    %% Create contract create transaction.
    {ok, DecPubKey3} = aec_base58c:safe_decode(account_pubkey, PubKey3),
    {ContractCreate, DecContractCreate} =
        make_contract_tx(contract_create_tx, PubKey3, DecPubKey3, Cfg),
    Nonce = 1,
    #{tx := ContractCreateTx, contract_address := ContractPubKey} =
        get_contract_tx(new_node3, 'PostContractCreate', fun aect_create_tx:new/1,
                        Nonce, ContractCreate, DecContractCreate, Cfg),
    %% Post contract create transaction and wait until it's mined.
    #{block_hash := ContractBlockHash, block_height := ContractBlockHeight} =
        post_contract_tx_and_wait_in_chain(new_node3, PubKey3, Nonce, ContractPubKey, contract_create_tx,
                                           ContractCreateTx, Cfg),
    %% Check protocol version of the block with mined transaction on all nodes.
    check_protocol_version_on_nodes([new_node3, new_node4], NewProtocolVersion,
                                    ContractBlockHash, ContractBlockHeight, Cfg),
    %% Create contract call transaction.
    {ContractCall, DecContractCall} =
        make_contract_tx(contract_call_tx, PubKey3, DecPubKey3, ContractPubKey, Cfg),
    Nonce1 = Nonce + 1,
    #{tx := ContractCallTx} =
        get_contract_tx(new_node3, 'PostContractCall', fun aect_call_tx:new/1,
                        Nonce1, ContractCall, DecContractCall, Cfg),
    %% Post contract call transaction and wait until it's mined.
    #{block_hash := ContractCallBlockHash, block_height := ContractCallBlockHeight} =
        post_contract_tx_and_wait_in_chain(new_node3, PubKey3, Nonce1, ContractPubKey, contract_call_tx,
                                           ContractCallTx, Cfg),
    %% Check protocol version of the block with mined transacion on all nodes.
    check_protocol_version_on_nodes([new_node3, new_node4], NewProtocolVersion,
                                    ContractCallBlockHash, ContractCallBlockHeight, Cfg),
    %% Create contract call compute transaction.
    {ContractCallCompute, DecContractCallCompute} =
        make_contract_tx(contract_call_compute_tx, PubKey3, DecPubKey3, ContractPubKey, Cfg),
    Nonce2 = Nonce1 + 1,
    #{tx := ContractCallComputeTx} =
        get_contract_tx(new_node3, 'PostContractCallCompute', fun aect_call_tx:new/1,
                        Nonce2, ContractCallCompute, DecContractCallCompute, Cfg),
    %% Post contract call compute transaction and wait until it's mined.
    #{block_hash := ContractCallComputeBlockHash, block_height := ContractCallComputeBlockHeight} =
        post_contract_tx_and_wait_in_chain(new_node3, PubKey3, Nonce2, ContractPubKey, contract_call_compute_tx,
                                           ContractCallComputeTx, Cfg),
    %% Check protocol version of the block with mined transaction on all nodes.
    check_protocol_version_on_nodes([new_node3, new_node4], NewProtocolVersion,
                                    ContractCallComputeBlockHash, ContractCallComputeBlockHeight, Cfg),
    ok.

%=== INTERNAL FUNCTIONS ========================================================

old_protocol_version() ->
    lists:nth(2, lists:reverse(
                   [_,_|_] = aec_governance:sorted_protocol_versions())).

old_protocol_height() ->
    maps:get(old_protocol_version(), aec_governance:protocols()).

new_protocol_version() ->
    lists:last([_,_|_] = aec_governance:sorted_protocol_versions()).

protocols(NewProtocolHeight) ->
    maps:update(new_protocol_version(), NewProtocolHeight,
                aec_governance:protocols()).

fast_protocols(BlocksPerVersion) when is_integer(BlocksPerVersion),
                                      BlocksPerVersion > 0 ->
    Vs = aec_governance:sorted_protocol_versions(),
    Hs = lists:seq(_From = 0,
                   _To = BlocksPerVersion * (length(Vs) - 1),
                   BlocksPerVersion),
    maps:from_list(lists:zip(Vs, Hs)).

db_backup_tar(Cfg) ->
    {_, DataDir} = proplists:lookup(data_dir, Cfg),
    filename:join(DataDir, ct:get_config(db_backup_tar)).

start_node(NodeName, Cfg) ->
    start_node(ext_http, NodeName, Cfg).

start_node(GetBlockByHeightService, NodeName, Cfg) ->
    aest_nodes:start_node(NodeName, Cfg),
    F = fun() -> try get_block_by_height(GetBlockByHeightService, NodeName, 0, Cfg), true catch _:_ -> false end end,
    aec_test_utils:wait_for_it(F, true),
    ct:log("Node ~p started as version~n~p", [NodeName, get_version(NodeName, Cfg)]),
    ok.

restore_db_backup_on_node_and_check_top(GetBlockByHeightService, NodeName, Cfg) ->
    {ok, {TopHash, TopHeight}} = restore_db_backup_on_node(NodeName, Cfg),
    ?assertMatch(X when is_integer(X) andalso X > 0, TopHeight),
    B = get_block_by_height(GetBlockByHeightService, NodeName, TopHeight, Cfg),
    ?assertEqual(TopHash, maps:get(hash, B)),
    {ok, {TopHash, TopHeight}}.

restore_db_backup_on_node(NodeName, Cfg) ->
    {ok, TarBin} = file:read_file(db_backup_tar(Cfg)),
    restore_db_backup_on_node(
      NodeName,
      TarBin, ct:get_config(db_backup_content),
      ?DB_BACKUP_DEST_DIR,
      Cfg).

restore_db_backup_on_node(NodeName, TarBin, Content, DestDir, Cfg) ->
    ct:log("Restoring DB backup of byte size ~p on node ~s",
           [byte_size(TarBin), NodeName]),
    {0, _} = aest_nodes:run_cmd_in_node_dir(NodeName, ["mkdir", DestDir], Cfg),
    {0, ""} = aest_nodes:run_cmd_in_node_dir(NodeName, ["ls", DestDir], Cfg),
    ok = aest_nodes:extract_archive(NodeName, DestDir, TarBin, Cfg),
    {0, Output} = aest_nodes:run_cmd_in_node_dir(NodeName, ["ls", DestDir], Cfg),
    ?assertEqual(Content, string:trim(Output)),
    Dest = DestDir ++ "/" ++ Content,
    ErlCmd = make_erl_cmd("{atomic, [_|_] = Tabs} = mnesia:restore(~p, []), ok.", [Dest]),
    ok = run_erl_cmd_on_node(NodeName, ErlCmd, 45000, Cfg),
    Top = #{height := TopHeight,
            hash := TopHash} = aest_nodes:get_top(NodeName, Cfg),
    ct:log("Restored DB backup on node ~s, whose top is now~n~p",
           [NodeName, Top]),
    {ok, {TopHash, TopHeight}}.

mock_pow_on_node(NodeName, Cfg) ->
    S =
        "-module(aec_pow_cuckoo). "
        "-export([generate/3, verify/4]). "
        "generate(_, _, Nonce) -> Evd = lists:duplicate(42, 0), {ok, {Nonce, Evd}}. "
        "verify(_,_,_,_) -> true.",
    load_module_on_node(NodeName, aec_pow_cuckoo, S, Cfg).

load_module_on_node(NodeName, Module, String, Cfg) ->
    ct:log("Module ~s:~n~s", [Module, String]),
    Tokens = dot_ending_token_lists(String),
    ct:log("Tokens:~n~p", [Tokens]),
    Forms = to_forms(Tokens),
    ct:log("Forms:~n~p", [Forms]),
    {ok, Module, Binary, []} = compile:forms(Forms, [return_errors,
                                                     return_warnings]),
    ErlCmd =
        make_erl_cmd(
          "{module, _} = code:load_binary(~s, \"Dummy Filename\", ~w), ok.",
          [Module, Binary]),
    ok = run_erl_cmd_on_node(NodeName, ErlCmd, 30000, Cfg).

get_signed_tx(NodeName, UnsignedTx, Cfg) ->
    ErlCmd = lists:flatten(io_lib:format("aec_keys:sign(~w).", [UnsignedTx])),
    run_erl_cmd_on_node(NodeName, ErlCmd, Cfg).

dot_ending_token_lists(Chars) ->
    (fun
         F(ContinuationIn, LeftOverCharsIn, TokenListsIn) ->
             case erl_scan:tokens(ContinuationIn, LeftOverCharsIn, 0) of
                 {done, {eof, _EndLocation}, _} ->
                     TokenListsIn;
                 {done, {ok, Tokens, _EndLocation}, LeftOverCharsOut} ->
                     F([], LeftOverCharsOut, TokenListsIn ++ [Tokens]);
                 {more, ContinuationOut} ->
                     F(ContinuationOut, eof, TokenListsIn)
             end
     end)([], Chars, []).

to_forms(DotEndingTokenLists) ->
    lists:map(fun(Ts) -> {ok, F} = erl_parse:parse_form(Ts), F end,
              DotEndingTokenLists).

make_erl_cmd(Fmt, Params) ->
    lists:flatten(io_lib:format(Fmt, Params)).

run_erl_cmd_on_node(NodeName, ErlCmd, Cfg) ->
    run_erl_cmd_on_node(NodeName, ErlCmd, 5000, Cfg).

run_erl_cmd_on_node(NodeName, ErlCmd, Timeout, Cfg) ->
    ct:log("Running Erlang command on node ~s:~n~s", [NodeName, ErlCmd]),
    Cmd = ["bin/epoch", "eval", ErlCmd],
    {0, Output} = aest_nodes:run_cmd_in_node_dir(NodeName, Cmd, Timeout, Cfg),
    Result = eval_expression(Output),
    ct:log("Run Erlang command on node ~s with result: ~p", [NodeName, Result]),
    Result.

eval_expression(Expr) ->
    {ok, Tokens, _} = erl_scan:string(lists:concat([Expr, "."])),
    {ok, Parsed} = erl_parse:parse_exprs(Tokens),
    {value, Result, _} = erl_eval:exprs(Parsed, []),
    Result.

request(NodeName, OpId, Params, Cfg) ->
    ExtAddr = aest_nodes:get_service_address(NodeName, ext_http, Cfg),
    IntAddr = aest_nodes:get_service_address(NodeName, int_http, Cfg),
    Cfg1 = [{ext_http, ExtAddr}, {int_http, IntAddr} | Cfg],
    aehttp_client:request(OpId, Params, Cfg1).

get_version(NodeName, Cfg) ->
    {ok, 200, B} = aest_nodes:http_get(NodeName, ext_http, [v2, version], #{}, Cfg),
    B.

get_block_by_height(NodeName, Height, Cfg) ->
    get_block_by_height(ext_http, NodeName, Height, Cfg).

get_block_by_height(Service, NodeName, Height, Cfg) ->
    {ok, 200, B} = aest_nodes:http_get(NodeName, Service, [v2, block, height, Height], #{}, Cfg),
    B.

get_block_by_hash(NodeName, Hash, Cfg) ->
    get_block_by_hash(ext_http, NodeName, Hash, Cfg).

get_block_by_hash(Service, NodeName, Hash, Cfg) ->
    {ok, 200, B} = aest_nodes:http_get(NodeName, Service, [v2, block, hash, Hash], #{}, Cfg),
    B.

get_public_key(NodeName, Cfg) ->
    {ok, 200, #{pub_key := PubKey}} = aest_nodes:http_get(NodeName, int_http, [v2, account, 'pub-key'], #{}, Cfg),
    PubKey.

get_balance(NodeName, PubKey, Cfg) ->
    case aest_nodes:http_get(NodeName, ext_http, [v2, account, balance, PubKey], #{}, Cfg) of
        {ok, 404, #{reason := <<"Account not found">>}} -> 0;
        {ok, 200, #{balance := Balance}} -> Balance
    end.

get_account_txs(NodeName, PubKey, Cfg) ->
    Params = #{tx_types => spend_tx, tx_encoding => json},
    {ok, 200, #{transactions := Txs}} =
        aest_nodes:http_get(NodeName, ext_http, [v2, account, txs, PubKey], Params, Cfg),
    Txs.

post_spend_tx_and_wait_in_chain(NodeName, Sender, Recipient, Amount, Fee, Cfg) ->
    ok = post_spend_tx(NodeName, Recipient, Amount, Fee, Cfg),
    ct:log("Sent spend tx of amount ~p from node ~p with public key ~p to account with public key ~p",
           [Amount, NodeName, Sender, Recipient]),
    {_SpendTxBlockHash, _SpendTxHeight} = wait_spend_tx_in_chain(NodeName, Sender, Recipient, Amount, Fee, Cfg).

wait_spend_tx_in_chain(NodeName, Sender, Recipient, Amount, Fee, Cfg) ->
    %% Make sure recipient account received the tokens.
    aest_nodes:wait_for_value({balance, Recipient, Amount}, [NodeName], 20000, Cfg),
    ReceivedBalance = get_balance(NodeName, Recipient, Cfg),
    ct:log("Balance of account with public key ~p is ~p", [Recipient, ReceivedBalance]),
    ?assertEqual(Amount, ReceivedBalance),
    %% Recipient account has one spend transaction.
    [#{block_hash := SpendTxBlockHash, block_height := SpendTxHeight, tx := TxInfo}] =
        get_account_txs(NodeName, Recipient, Cfg),
    ?assertEqual(ReceivedBalance, maps:get(amount, TxInfo)),
    ?assertEqual(Fee, maps:get(fee, TxInfo)),
    ?assertEqual(Sender, maps:get(sender, TxInfo)),
    ?assertEqual(Recipient, maps:get(recipient, TxInfo)),
    {SpendTxBlockHash, SpendTxHeight}.

post_spend_tx(NodeName, Recipient, Amount, Fee, Cfg) ->
    Headers = [{<<"Content-Type">>, <<"application/json">>}],
    Body = jsx:encode(#{
            recipient_pubkey => Recipient,
            amount => Amount,
            fee => Fee}),
    {ok, 200, #{}} = aest_nodes:http_post(NodeName, int_http, [v2, 'spend-tx'], #{}, Headers, Body, Cfg),
    ok.

get_contract_tx(NodeName, OpId, NewF, Nonce, Data, DecData, Cfg) ->
    {ok, ExpectedDeserializedTx} = NewF(DecData#{nonce => Nonce}),
    {ok, 200, #{tx := Tx, tx_hash := TxHash} = Result} = request(NodeName, OpId, Data, Cfg),
    {ok, SerializedTx} = aec_base58c:safe_decode(transaction, Tx),
    DeserializedTx = aetx:deserialize_from_binary(SerializedTx),
    ExpectedTxHash = aec_base58c:encode(tx_hash, aetx:hash(DeserializedTx)),
    ?assertEqual(ExpectedDeserializedTx, DeserializedTx),
    ?assertEqual(ExpectedTxHash, TxHash),
    Result.

post_contract_tx_and_wait_in_chain(NodeName, Sender, Nonce, ContractPubKey, TxType, Tx, Cfg) ->
    %% Deserialize, sign and post transaction.
    {ok, SerializedTx} = aec_base58c:safe_decode(transaction, Tx),
    DeserializedTx = aetx:deserialize_from_binary(SerializedTx),
    {ok, SignedDeserializedTx} = get_signed_tx(NodeName, DeserializedTx, Cfg),
    SerializedSignedTx = aetx_sign:serialize_to_binary(SignedDeserializedTx),
    EncSerializedSignedTx = aec_base58c:encode(transaction, SerializedSignedTx),
    ct:log("Sent ~p with sender public key ~p and transaction: ~p", [TxType, Sender, Tx]),
    {ok, 200, _} = request(NodeName, 'PostTx', #{tx => EncSerializedSignedTx}, Cfg),
    wait_contract_tx_in_chain(NodeName, Sender, Nonce, ContractPubKey, TxType, Cfg).

wait_contract_tx_in_chain(NodeName, Sender, Nonce, ContractPubKey, TxType, Cfg) ->
    %% Wait until the contract gets mined, retrieve info about the block which contains the contract.
    aest_nodes:wait_for_value({contract_tx, Sender, Nonce}, [NodeName], 45000, Cfg),
    TxType1 = make_contract_tx_type(TxType),
    {ok, 200, #{transactions := Txs}} =
        request(NodeName, 'GetAccountTransactions',
                #{account_pubkey => Sender, tx_types => TxType1, tx_encoding => json}, Cfg),
    [#{tx := MinedTxInfo} = MinedTx] = tx_with_nonce(Nonce, Txs),
    check_mined_contract_tx(TxType, Sender, ContractPubKey, MinedTxInfo, Cfg),
    MinedTx.

make_contract_tx(contract_create_tx, PubKey, DecPubKey, Cfg) ->
    ContractCreate =
        #{owner      => PubKey,
          code       => ?config(contract_code, Cfg),
          vm_version => ?config(contract_tx_vm_version, Cfg),
          deposit    => ?config(contract_tx_deposit, Cfg),
          amount     => ?config(contract_tx_amount, Cfg),
          gas        => ?config(contract_tx_gas, Cfg),
          gas_price  => ?config(contract_tx_gas_price,Cfg),
          fee        => ?config(contract_tx_fee, Cfg),
          call_data  => ?config(contract_call_data, Cfg)},
    DecContractCreate =
        ContractCreate#{owner     => DecPubKey,
                        code      => ?config(decoded_contract_code, Cfg),
                        call_data => ?config(decoded_contract_call_data, Cfg)},
    {ContractCreate, DecContractCreate}.

make_contract_tx(contract_call_tx, PubKey, DecPubKey, ContractPubKey, Cfg) ->
    ContractCall =
        #{caller     => PubKey,
          contract   => ContractPubKey,
          vm_version => ?config(contract_tx_vm_version, Cfg),
          amount     => ?config(contract_tx_amount, Cfg),
          gas        => ?config(contract_tx_gas, Cfg),
          gas_price  => ?config(contract_tx_gas_price,Cfg),
          fee        => ?config(contract_tx_fee, Cfg),
          call_data  => ?config(contract_call_data, Cfg)},
    DecContractCall =
        ContractCall#{caller    => DecPubKey,
                      call_data => ?config(decoded_contract_call_data, Cfg)},
    {ContractCall, DecContractCall};
make_contract_tx(contract_call_compute_tx, PubKey, DecPubKey, ContractPubKey, Cfg) ->
    ContractCode = ?config(contract_code, Cfg),
    ContractFunction = ?config(contract_function, Cfg),
    ContractArguments = ?config(contract_arguments, Cfg),
    ContractCallCompute =
        #{caller     => PubKey,
          contract   => ContractPubKey,
          vm_version => ?config(contract_tx_vm_version, Cfg),
          amount     => ?config(contract_tx_amount, Cfg),
          gas        => ?config(contract_tx_gas, Cfg),
          gas_price  => ?config(contract_tx_gas_price,Cfg),
          fee        => ?config(contract_tx_fee, Cfg),
          function   => ContractFunction,
          arguments  => ContractArguments},
    {ok, EncContractCallData} =
        aect_sophia:encode_call_data(ContractCode, ContractFunction, ContractArguments),
    DecContractCallData1 = aeu_hex:hexstring_decode(EncContractCallData),
    DecContractCallCompute =
        ContractCallCompute#{caller    => DecPubKey,
                             call_data => DecContractCallData1},
    {ContractCallCompute, DecContractCallCompute}.

check_mined_contract_tx(contract_create_tx, Sender, _ContractPubKey, TxInfo, Cfg) ->
    check_mined_contract_tx_common(TxInfo, Cfg),
    ?assertEqual(Sender, maps:get(owner, TxInfo)),
    ?assertEqual(?config(contract_code, Cfg), list_to_binary(maps:get(code, TxInfo))),
    ?assertEqual(?config(contract_tx_deposit, Cfg), maps:get(deposit, TxInfo)),
    ?assertEqual(?config(contract_call_data, Cfg), list_to_binary(maps:get(call_data, TxInfo))),
    ok;
check_mined_contract_tx(contract_call_tx, Sender, ContractPubKey, TxInfo, Cfg) ->
    check_mined_contract_tx_common(TxInfo, Cfg),
    {ok, TxInfoContractPubKey} = aec_base58c:safe_decode(account_pubkey, maps:get(contract, TxInfo)),
    ?assertEqual(Sender, maps:get(caller, TxInfo)),
    ?assertEqual(ContractPubKey, TxInfoContractPubKey),
    ?assertEqual(?config(contract_call_data, Cfg), list_to_binary(maps:get(call_data, TxInfo))),
    ok;
check_mined_contract_tx(contract_call_compute_tx, Sender, ContractPubKey, TxInfo, Cfg) ->
    check_mined_contract_tx_common(TxInfo, Cfg),
    {ok, TxInfoContractPubKey} = aec_base58c:safe_decode(account_pubkey, maps:get(contract, TxInfo)),
    ?assertEqual(Sender, maps:get(caller, TxInfo)),
    ?assertEqual(ContractPubKey, TxInfoContractPubKey),
    ok.

check_mined_contract_tx_common(TxInfo, Cfg) ->
    ?assertEqual(?config(contract_tx_vm_version, Cfg), hex_to_integer(maps:get(vm_version, TxInfo))),
    ?assertEqual(?config(contract_tx_amount, Cfg), maps:get(amount, TxInfo)),
    ?assertEqual(?config(contract_tx_gas, Cfg), maps:get(gas, TxInfo)),
    ?assertEqual(?config(contract_tx_gas_price, Cfg), maps:get(gas_price, TxInfo)),
    ?assertEqual(?config(contract_tx_fee, Cfg), maps:get(fee, TxInfo)),
    ok.

check_protocol_version_on_nodes(NodeNames, ExpectedProtocolVersion, BlockHash, BlockHeight, Cfg) ->
    lists:foreach(
      fun(NodeName) ->
              check_protocol_version_on_node(NodeName, ExpectedProtocolVersion, BlockHash, BlockHeight, Cfg)
      end,
      NodeNames).

check_protocol_version_on_node(NodeName, ExpectedProtocolVersion, BlockHash, BlockHeight, Cfg) ->
    wait_for_height_syncing(BlockHeight, [NodeName], {{100000, ms}, {1000, blocks}}, Cfg),
    {ok, 200, #{version := ProtocolVersion}} =
        request(NodeName, 'GetBlockByHash', #{hash => BlockHash, tx_encoding => json}, Cfg),
    ?assertMatch(ExpectedProtocolVersion, ProtocolVersion).

wait_for_height_syncing(MinHeight, NodeNames, {{Timeout, ms}, {Blocks, blocks}}, Cfg) ->
    WaitF =
        fun(H) ->
                ct:log("Waiting for height ~p for ~p ms on nodes ~p...", [H, Timeout, NodeNames]),
                aest_nodes:wait_for_value({height, H}, NodeNames, Timeout, Cfg),
                ct:log("Reached height ~p on nodes ~p ...", [H, NodeNames]),
                ok
        end,
    wait_step_for_height(WaitF, MinHeight, Blocks).

wait_step_for_height(WaitF, MinHeight, StepMaxBlocks)
  when is_integer(MinHeight), MinHeight >= 0,
       is_integer(StepMaxBlocks), StepMaxBlocks > 0 ->
    ok = WaitF(0),
    wait_step_for_height(WaitF, MinHeight, StepMaxBlocks, 0).

wait_step_for_height(_, MinHeight, _, MinHeight) ->
    ok;
wait_step_for_height(WaitF, MinHeight, StepMaxBlocks, ReachedHeight) ->
    H = min(MinHeight, ReachedHeight + StepMaxBlocks),
    ok = WaitF(H),
    wait_step_for_height(WaitF, MinHeight, StepMaxBlocks, H).

make_contract_tx_type(contract_create_tx) -> contract_create_tx;
make_contract_tx_type(contract_call_tx) -> contract_call_tx;
make_contract_tx_type(contract_call_compute_tx) -> contract_call_tx.

tx_with_nonce(Nonce, Txs) ->
    lists:filter(fun(#{tx := #{nonce := N}}) when N =:= Nonce -> true;
                    (_) -> false
                end, Txs).

hex_to_integer([$0, $x | N]) ->
    list_to_integer(N, 16).

