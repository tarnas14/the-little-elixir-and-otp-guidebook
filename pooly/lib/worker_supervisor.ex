defmodule Pooly.WorkerSupervisor do
  use DynamicSupervisor

  # api

  def start_link(pool_server, max_workers_with_overflow) do
    DynamicSupervisor.start_link(__MODULE__, [pool_server, max_workers_with_overflow])
  end

  def start_child(worker_sup, {id, m, f, a} = _imfa) do
    spec = %{id: id, start: {m, f, a}}
    DynamicSupervisor.start_child(worker_sup, spec)
  end

  # callbacks

  def init([pool_server, max_workers_with_overflow]) do
    IO.puts(inspect pool_server)
    IO.puts(inspect max_workers_with_overflow)
    Process.link(pool_server)
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [pool_server],
      max_children: max_workers_with_overflow
    )
  end
end
