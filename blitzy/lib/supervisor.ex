defmodule Blitzy.Supervisor do
  use Supervisor

  def start_link(:ok) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [{Task.Supervisor, name: Blitzy.TasksSupervisor}]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
