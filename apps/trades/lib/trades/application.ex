defmodule Trades.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # {Trades.Leader, %Trades.Leader.State{:symbol => "xrpeur"}}
      {Trades.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Trades.Application]
    Supervisor.start_link(children, opts)
  end
end
