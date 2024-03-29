defmodule OthelloEngine.Game do
    use GenServer
    alias OthelloEngine.{Board, History, Game, Player, Rules}

    defstruct board: :none, history: :none, playerA: :none, playerB: :none, fsm: :none


    def start_link(game_id, name) when not is_nil(game_id) and not is_nil(name) do
        GenServer.start_link(__MODULE__, name, name: via_tuple(game_id))
    end


    def init(name) do
        state = init_state(name)

        {:ok, state}
    end


    def add_player(game_pid, name) when not is_nil(name) do
        GenServer.call(game_pid, {:add_player, name})
    end


    def request_rematch(game_pid, player) do
        GenServer.call(game_pid, {:request_rematch, player})
    end


    def make_move(game_pid, player, row, col) when is_atom player do
        GenServer.call(game_pid, {:make_move, player, row, col})
    end


    def get_winner(game_pid) do
        GenServer.call(game_pid, {:get_winner})
    end


    def get_full_state(game_pid) do
        GenServer.call(game_pid, :get_full_state)
    end


    def get_fsm_state(game_pid) do
        GenServer.call(game_pid, {:fsmstate_return})
    end

    def handle_call({:fsmstate_return}, _from, state) do
        {:reply, state.fsm, state}
    end


    def stop(game_pid) do
        GenServer.cast(game_pid, :stop)
    end


    def via_tuple(game_id) do
        {:via, Registry, {Registry.Game, game_id}}
    end


    def handle_cast(:stop, state) do
        {:stop, :normal, state}
    end


    def handle_call({:request_rematch, player}, _from, state) do
        player_pid = Map.get(state, player)
        color = Player.get_color(player_pid)

        Rules.rematch(state.fsm, color)
        |> rematch_reply(state, player)
    end


    def handle_call({:get_winner}, _from, state) do
        winner = Board.get_winner(state.board)
        winner =
        case winner do
            :black -> get_player_by_color(state, :black)
            :white -> get_player_by_color(state, :white)
            val    -> val
        end
        {:reply, %{winner: winner}, state}
    end


    def handle_call({:add_player, name}, _from, state) do
        Rules.add_player(state.fsm)
        |> add_player_reply(state, name)
    end


    def handle_call({:make_move, player, row, col}, _from, state) do
        player_pid = Map.get(state, player)
        color = Player.get_color(player_pid)

        Rules.allowed_to_make_move(state.fsm, color)
        |> make_move_reply(state, player, row, col, color)
    end


    def handle_call(:get_full_state, _from, state) do
        full_state = %{}
        |> Map.put(:board, Board.get_board(state.board))
        |> Map.put(:playerA, Player.get_name(state.playerA))
        |> Map.put(:playerB, Player.get_name(state.playerB))
        |> Map.put(:turn, get_turn_player(state))
        |> get_full_state_possible_moves(state)

        {:reply, full_state, state}
    end


    defp make_move_reply(:ok, state, player, row, col, color) do
        Board.make_move(state.board, row, col, color)
        |> move_check(player, state, row, col)
        |> pass_check(player, state)
        |> win_check(player, state)
        |> possible_moves_check(player, state)
        |> convert_move_reply_to_map()
    end

    defp make_move_reply(reply, state, _player, _row, _col, _color) do
        {:reply, reply, state}
    end


    defp move_check(:not_possible, _player, _state, _row, _col) do
        :not_possible
    end

    defp move_check(pieces, player, state, row, col) do
        player_pid = Map.get(state, player)
        color = Player.get_color(player_pid)

        History.add_move(state.history, row, col, color)
        Rules.make_move(state.fsm, color)
        pieces
    end


    defp pass_check(:not_possible, _player, _state) do
        {:not_possible, :no_pass}
    end

    defp pass_check(pieces, player, state) do
        player_pid = Map.get(state, opposite_player(player))
        color = Player.get_color(player_pid)

        pass_status =
        case Board.can_move?(state.board, color) do
            true    -> :no_pass
            false   -> Rules.pass(state.fsm, color)
                       :pass
        end

        {pieces, pass_status}
    end


    defp win_check({pieces, :no_pass}, _player, _state) do
       {pieces, :no_pass, :no_win}
    end

    defp win_check({pieces, :pass}, player, state) do
        player_pid = Map.get(state, player)
        color = Player.get_color(player_pid)

        win_status =
        case Board.can_move?(state.board, color) do
            true    -> :no_win
            false   -> Rules.win(state.fsm)
                       :win
        end

        {pieces, :pass, win_status}
    end


    defp possible_moves_check({pieces, :pass, :win}, _player, state) do
        {:reply, {pieces, :pass, :win, []}, state}
    end

    defp possible_moves_check({:not_possible, pass, win}, player, state) do
        player_pid = Map.get(state, player)
        color = Player.get_color(player_pid)
        moves = Board.get_possible_moves(state.board, color)

        {:reply, {:not_possible, pass, win, moves}, state}
    end

    defp possible_moves_check({pieces, :pass, win}, player, state) do
        player_pid = Map.get(state, player)
        color = Player.get_color(player_pid)
        moves = Board.get_possible_moves(state.board, color)

        {:reply, {pieces, :pass, win, moves}, state}
    end

    defp possible_moves_check({pieces, :no_pass, win}, player, state) do
        player_pid = Map.get(state, opposite_player(player))
        color = Player.get_color(player_pid)
        moves = Board.get_possible_moves(state.board, color)

        {:reply, {pieces, :no_pass, win, moves}, state}
    end


    defp convert_move_reply_to_map({reply, {pieces, pass, win, moves}, state}) do
        map = %{}
        |> Map.put(:touched_pieces, pieces)
        |> Map.put(:pass, pass)
        |> Map.put(:win, win)
        |> Map.put(:possible_moves, moves)
        {reply, map, state}
    end


    defp opposite_player(:playerA) do
        :playerB
    end

    defp opposite_player(:playerB) do
        :playerA
    end


    defp add_player_reply(:ok, state, name) do
        Player.set_name(state.playerB, name)
        {:reply, :ok, state}
    end

    defp add_player_reply(reply, state, _name) do
        {:reply, reply, state}
    end

    defp rematch_reply(:ok, state, _player) do
        case Rules.show_current_state(state.fsm) do
            :initialized -> History.reset(state.history)
                            Board.reset(state.board)
                            Player.flip_color(state.playerA)
                            Player.flip_color(state.playerB)
                            Rules.add_player(state.fsm)
                            {:reply, :rematched, state}
            _            -> {:reply, :rematch_pending, state}
        end
    end

    defp rematch_reply(reply, state, _player) do
        {:reply, reply, state}
    end


    defp init_state(name) do
        {:ok, board} = Board.start_link()
        {:ok, history} = History.start_link()
        {:ok, playerA} = Player.start_link(:black, name)
        {:ok, playerB} = Player.start_link(:white)
        {:ok, fsm} = Rules.start_link()

        %Game{board: board, history: history,
              playerA: playerA, playerB: playerB, fsm: fsm}
    end


    defp get_turn_player(state) do
        case Rules.show_current_state(state.fsm) do
            :black_turn -> get_player_by_color(state, :black)
            :white_turn -> get_player_by_color(state, :white)
            _   -> :finished
        end
    end


    defp get_player_by_color(state, color) do
        case Player.get_color(state.playerA) do
            ^color   -> %{player: :playerA, color: color}
            _        -> %{player: :playerB , color: Player.opposite_color(color)}
        end
    end


    defp get_full_state_possible_moves(%{turn: %{player: player}} = full_state, state) do
        player_pid = Map.get(state, player)
        color = Player.get_color(player_pid)
        moves = Board.get_possible_moves(state.board, color)
        Map.put(full_state, :possible_moves, moves)
    end
end