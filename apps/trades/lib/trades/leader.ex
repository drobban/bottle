defmodule Trades.Leader do
  use GenServer, restart: :temporary

  require Logger
  alias Decimal, as: D

  defmodule State do
    @enforce_keys [
      # :id,
      :symbol
      # :budget,
      # :buy_down_interval,
      # :profit_interval,
      # :rebuy_interval,
      # :rebuy_notified,
      # :tick_size,
      # :step_size
    ]
    defstruct [
      # :id,
      :symbol
      # :budget,
      # :buy_order,
      # :sell_order,
      # :buy_down_interval,
      # :profit_interval,
      # :rebuy_interval,
      # :rebuy_notified,
      # :tick_size,
      # :step_size
    ]
  end

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{} = state) do
    symbol = String.downcase(state.symbol)

    Streamer.start_streaming(symbol)

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade_events:#{symbol}"
    )

    {:ok, state}
  end

  def handle_info(event, state) do
    # Logger.info("Inside leader")
    # Logger.debug("#{inspect(event)}")
    {:noreply, state}
  end
end
