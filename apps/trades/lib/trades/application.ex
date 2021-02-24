defmodule Trades.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Trades.Worker.start_link(arg)
      # {Trades.Worker, arg}
      {Trades.Leader, %Trades.Leader.State{:symbol => "xrpeur"}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Trades.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
