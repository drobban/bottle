defmodule Trades.SymbolSupervisor do
  use Supervisor, restart: :temporary

  def start_link(symbol) do
    Supervisor.start_link(
      __MODULE__,
      symbol,
      name: :"Trades.SymbolSupervisor-#{symbol}"
    )
  end

  def init(symbol) do
    Supervisor.init(
      [
        {
          DynamicSupervisor,
          strategy: :one_for_one, name: :"Trades.DynamicSupervisor-#{symbol}"
        },
        {Trades.Leader, symbol}
      ],
      strategy: :one_for_all
    )
  end
end
