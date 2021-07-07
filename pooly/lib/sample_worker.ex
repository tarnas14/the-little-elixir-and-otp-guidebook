defmodule Pooly.SampleWorker do
  use GenServer

  # api

  def start_link(pool_server_pid, _) do
    GenServer.start_link(__MODULE__, pool_server_pid)
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def work_for(pid, duration) do
    GenServer.cast(pid, {:work_for, duration})
  end

  def init(pool_server_pid) do
    Process.link(pool_server_pid)
    {:ok, :ok}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_cast({:work_for, duration}, state) do
    :timer.sleep(duration)
    {:stop, :normal, state}
  end
end
