-module(mob).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([join/1]).
-export([run/1]).
-export([deploy/1]).
-export([node_name/0]).
-export([peer/1]).

%% gen_server callbacks
-export([init/1,
     handle_call/3,
     handle_cast/2,
     handle_info/2,
     terminate/2,
     code_change/3]).

-record(state, {peer}).

start_link() ->
    gen_server:start_link({local, mob}, ?MODULE, [], []).

deploy(Service) ->
    gen_server:call(mob, {deploy, Service}).

run(Service) ->
    gen_server:cast(mob, {run, Service}).

join(NodeName) ->
    gen_server:call(mob, {join, NodeName}).

peer(Node) ->
    gen_server:call({mob, Node}, peer).

node_name() ->
    node().

%% Callbacks

init_peer() ->
    {ok, PeerConf} = application:get_env(kademlia),

    {k, K} = lists:keyfind(k, 1, PeerConf),
    {alpha, Alpha} = lists:keyfind(alpha, 1, PeerConf),

    Id = peer:hash_key(node_name()),
    peer:start(Id, K, Alpha).

init([]) ->
    Peer = init_peer(),
    %% annunce itself
    Nodes = sets:new(),
    peer:iterative_store(Peer, {nodes, sets:add_element(node_name(), Nodes)}),
    {ok, #state{peer = Peer}}.

handle_call(peer, _From, State = #state{peer = Peer}) ->
    {reply, Peer, State};

handle_call({join, NodeName}, _From, State = #state{peer = Peer}) ->
    {Reply, State} = handle_join(NodeName, State),
    {reply, Reply, State};

handle_call({deploy, Service}, _From, State) ->
    {Reply, NewState} = handle_deploy(Service, State),
    {reply, Reply, NewState};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({run, Service}, State) ->
    log:log("Hi!! I'm selected to run ~p", [Service]),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% Handlers
handle_join(NodeName, State = #state{peer = Peer}) ->
    ConnectionResult = net_kernel:connect_node(NodeName),
    BootstrapPeer = peer(NodeName),

    %% this "should" never fail since every node annunce itself
    UpdatedNodes = discovery:merge_nodes(Peer, BootstrapPeer),
    peer:join(Peer, BootstrapPeer),

    %% XXX: here should we wait to be sure that the joining process is
    %% completed ?
    peer:iterative_store(Peer, {nodes, UpdatedNodes}),
    {ConnectionResult, State}.

handle_deploy(Service, State) ->
    Reply = case service:parse(Service) of
                {ok, ParsedService} -> do_deploy(ParsedService, State);
                {error, Error} -> Error
            end,
    {Reply, State}.

do_deploy(ParsedService, #state{peer = Peer}) ->
    case discovery:find_available_node(Peer, ParsedService) of
        {ok, Node} -> remote_mob:run(Node, ParsedService),
                      Node;
        {error, Error} -> Error
    end.

-ifdef(TEST).
-compile([export_all]).
-include_lib("../test/mob.hrl").
-endif.
