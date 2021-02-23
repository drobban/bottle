defmodule Trades.Junior do
  use GenServer, restart: :temporary

  require Logger
  alias Decimal, as: D

  defmodule State do
    @enforce_keys [:symbol, :profit_interval, :tick_size]
    defstruct [
      :symbol,
      :buy_order,
      :sell_order,
      :profit_interval,
      :tick_size
    ]
  end

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{} = state) do
    {:ok, state}
  end

  def handle_cast(event, state) do
    Logger.debug("#{inspect(event)} - #{inspect(state)}")

    {:noreply, state}
  end
end
