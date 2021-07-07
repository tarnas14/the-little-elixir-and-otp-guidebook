defmodule Pooly.PoolsSupervisor do
  use DynamicSupervisor

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_child(pool_config) do
    {id, m, f, a} = pool_config[:imfa]
    DynamicSupervisor.start_child(__MODULE__, %{
      id: :"#{pool_config[:name]}Supervisor",
      start: {Pooly.PoolSupervisor, :start_link, [pool_config]},
      type: :supervisor
    })
  end

  def init(_) do
    DynamicSupervisor.init(
      strategy: :one_for_one
    )
  end
end
