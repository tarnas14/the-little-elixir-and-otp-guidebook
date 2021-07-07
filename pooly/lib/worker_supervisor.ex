defmodule Pooly.WorkerSupervisor do
  use Supervisor

  # api

  def start_link(pool_server, {_,_,_,_} = imfa) do
    Supervisor.start_link(__MODULE__, [pool_server, imfa])
  end

  # callbacks

  def init([pool_server, {i, m, f, a}]) do
    Process.link(pool_server)
    worker_opts = [restart: :temporary, shutdown: 5000, function: f]
    children = [worker(m, [pool_server|a], worker_opts)]

    opts = [strategy: :simple_one_for_one, max_restarts: 5, max_seconds: 5]

    supervise(children, opts)
  end
end
