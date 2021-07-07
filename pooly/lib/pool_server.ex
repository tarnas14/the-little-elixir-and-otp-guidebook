defmodule Pooly.PoolServer do
  use GenServer
  import Supervisor.Spec

  defmodule State do
    defstruct pool_sup: nil,
              worker_sup: nil,
              size: nil,
              workers: nil, # available workers
              imfa: nil,
              monitors: nil, # monitored client processes, client references by worker id
              name: nil,
              overflow: nil,
              max_overflow: nil,
              waiting: nil
  end

  # api

  def start_link(pool_sup, pool_config) do
    GenServer.start_link(__MODULE__, [pool_sup, pool_config], name: name(pool_config[:name]))
  end

  def checkout(pool_name, block, timeout) do
    GenServer.call(name(pool_name), {:checkout, block}, timeout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(name(pool_name), {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(name(pool_name), :status)
  end

  # callbacks
  def handle_call({:checkout, block}, {from_pid, _ref} = from, state) do
    %{
      worker_sup: worker_sup,
      workers: workers,
      monitors: monitors,
      waiting: waiting,
      overflow: overflow,
      max_overflow: max_overflow,
      imfa: imfa
    } = state

    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}

      [] when max_overflow > 0 and overflow < max_overflow ->
        worker = new_worker(worker_sup, imfa)
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | overflow: overflow + 1}}

      [] when block == true ->
        ref = Process.monitor(from_pid)
        waiting = :queue.in({from, ref}, waiting)
        {:noreply, %{state | waiting: waiting}, :infinity}

      [] ->
        {:reply, :full, state}
    end
  end

  def handle_call(:status, _from, %{workers: workers, monitors: monitors} = state) do
    {:reply, {state_name(state), length(workers), :ets.info(monitors, :size)}, state}
  end

  def handle_cast({:checkin, worker}, %{monitors: monitors} = state) do
    case :ets.lookup(monitors, worker) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_checkin(pid, state)
        {:noreply, new_state}

      [] ->
        {:noreply, state}
    end
  end

  def handle_info(
        :start_worker_supervisor,
        %{pool_sup: pool_sup, name: name, imfa: imfa, size: size} = state
      ) do
    spec = supervisor_spec(state)

    case Supervisor.start_child(pool_sup, spec) do
      {:ok, worker_sup} ->
        workers = prepopulate(size, worker_sup, imfa)
        {:noreply, %{state | worker_sup: worker_sup, workers: workers}}

      {:error, error} ->
        IO.puts("start_worker_supervisor error " <> name)
        IO.puts(inspect(error))
        {:noreply, state}

      thing ->
        IO.puts("thing")
        IO.puts(inspect(thing))
        {:noreply, state}
    end
  end

  # handling consumer down message
  def handle_info({:DOWN, ref, _, _, _}, state = %{monitors: monitors, workers: workers}) do
    case :ets.match(monitors, {:"$1", ref}) do
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        new_state = %{state | workers: [pid | workers]}
        {:noreply, new_state}

      [[]] ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, worker_sup, reason}, state = %{worker_sup: worker_sup}) do
    {:stop, reason, state}
  end

  def handle_info(
        {:EXIT, pid, _reason},
        state = %{monitors: monitors}
      ) do
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_worker_exit(pid, state)
        {:noreply, new_state}

      [] ->
        new_state = handle_worker_exit(pid, state)
        {:noreply, new_state}
    end
  end

  def init([pool_sup, pool_config]) when is_pid(pool_sup) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])
    waiting = :queue.new()
    state = %State{pool_sup: pool_sup, monitors: monitors, waiting: waiting, overflow: 0}
    init(pool_config, state)
  end

  def init([{:name, name} | rest], state) do
    init(rest, %{state | name: name})
  end

  def init([{:imfa, imfa} | rest], state) do
    init(rest, %{state | imfa: imfa})
  end

  def init([{:size, size} | rest], state) do
    init(rest, %{state | size: size})
  end

  def init([{:max_overflow, max_overflow} | rest], state) do
    init(rest, %{state | max_overflow: max_overflow})
  end

  def init([_ | rest], state) do
    init(rest, state)
  end

  def init([], state) do
    send(self, :start_worker_supervisor)
    {:ok, state}
  end

  # privates
  defp name(pool_name) do
    :"#{pool_name}Server"
  end

  defp supervisor_spec(%{name: name, imfa: imfa}) do
    opts = [id: name <> "WorkerSupervisor", restart: :temporary]
    supervisor(Pooly.WorkerSupervisor, [self, imfa], opts)
    # %{
      # id: name <> "WorkerSupervisor",
      # start: {Pooly.WorkerSupervisor, :start_link, [self]},
      # restart: :temporary,
      # type: :supervisor
    # }
  end

  defp prepopulate(size, worker_sup, imfa) do
    prepopulate(size, worker_sup, imfa, [])
  end

  defp prepopulate(size, _worker_sup, _imfa, workers) when size < 1 do
    workers
  end

  defp prepopulate(size, worker_sup, imfa, workers) do
    prepopulate(size - 1, worker_sup, imfa, [new_worker(worker_sup, imfa) | workers])
  end

  defp new_worker(worker_sup, imfa) do
    case Supervisor.start_child(worker_sup, [[]]) do
      {:ok, worker} ->
        worker

      thing ->
        IO.puts("ERROR")
        IO.puts(inspect(imfa))
        IO.puts(inspect(thing))
        nil
    end
  end

  defp handle_checkin(pid, state) do
    %{
      worker_sup: worker_sup,
      workers: workers,
      monitors: monitors,
      overflow: overflow,
      waiting: waiting
    } = state

    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        true = :ets.insert(monitors, {pid, ref})
        GenServer.reply(from, pid)
        %{state | waiting: left}

      {:empty, empty} when overflow > 0 ->
        :ok = dismiss_worker(worker_sup, pid)
        %{state | waiting: empty, overflow: overflow - 1}

      {:empty, empty} ->
        %{state | waiting: empty, workers: [pid | workers], overflow: overflow}
    end
  end

  defp dismiss_worker(sup, pid) do
    true = Process.unlink(pid)
    Supervisor.terminate_child(sup, pid)
  end

  defp handle_worker_exit(exited_worker_pid, state) do
    %{
      worker_sup: worker_sup,
      workers: workers,
      overflow: overflow,
      monitors: monitors,
      waiting: waiting,
      imfa: imfa
    } = state

    workers_without_exited = workers |> Enum.filter(fn x -> x != exited_worker_pid end)

    case :queue.out(waiting) do
      {{:value, {from, ref}}, left_waiting} ->
        new_worker = new_worker(worker_sup, imfa)
        true = :ets.insert(monitors, {new_worker, ref})
        GenServer.reply(from, new_worker)
        %{state | workers: [new_worker | workers_without_exited], waiting: left_waiting}

      {:empty, empty} when overflow > 0 ->
        %{state | workers: workers_without_exited, waiting: empty, overflow: overflow - 1}

      {:empty, empty} ->
        %{state | waiting: empty, workers: [new_worker(worker_sup, imfa) | workers_without_exited]}
    end
  end

  defp state_name(%State{overflow: overflow, max_overflow: max_overflow, workers: workers})
       when overflow < 1 do
    case length(workers) == 0 do
      true ->
        if max_overflow < 1 do
          :full
        else
          :overflow
        end

      false ->
        :ready
    end
  end

  defp state_name(%State{overflow: max_overflow, max_overflow: max_overflow}) do
    :full
  end

  defp state_name(_state) do
    :overflow
  end
end
