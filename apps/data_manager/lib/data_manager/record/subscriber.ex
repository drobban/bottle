defmodule DataManager.Record.Subscriber do
  use GenServer, restart: :temporary

  require Logger

  defmodule State do
    defstruct [:symbol]
  end

  def start_link(symbol) do
    Logger.debug("Starting link: #{__MODULE__}-#{symbol}")
    GenServer.start_link(__MODULE__, %State{symbol: symbol}, name: :"#{__MODULE__}-#{symbol}")
  end

  def init(%State{symbol: symbol} = state) do
    symbol = String.downcase(symbol)
    Streamer.start_streaming(symbol)

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade_events:#{symbol}"
    )

    {:ok, state}
  end

  def handle_info(event, state) do
    e = struct(DataManager.TradeEvent, Map.from_struct(event))

    case DataManager.Repo.insert(e) do
      {:ok, inserted_event} -> Logger.debug("Inserted #{inserted_event.id}")
      _default -> Logger.warning("Failed to insert event")
    end

    {:noreply, state}
  end
end
