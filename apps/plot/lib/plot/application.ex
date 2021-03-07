defmodule Plot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Plot.Worker.start_link(arg)
      {Plot.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Plot.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
