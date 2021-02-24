defmodule Streamer.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {Streamer.DynamicStreamerSupervisor, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
