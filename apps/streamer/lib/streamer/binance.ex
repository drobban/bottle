defmodule Streamer.Binance do
  use WebSockex
  require Logger

  defmodule State do
    @enforce_keys [:symbol]
    defstruct [:symbol]
  end

  @stream_endpoint "wss://stream.binance.com:9443/ws/"

  def start_link(symbol) do
    lowercased_symbol = String.downcase(symbol)

    WebSockex.start_link(
      "#{@stream_endpoint}#{lowercased_symbol}@trade",
      __MODULE__,
      %State{
        symbol: lowercased_symbol
      },
      name: :"#{__MODULE__}-#{symbol}"
    )
  end

  def handle_frame({_type, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} -> handle_event(event, state)
      {:error, _} -> Logger.warn("Unable to parse #{inspect(msg)}")
    end

    {:ok, state}
  end

  def handle_disconnect(connection_status_map, state) do
    Logger.error("#{inspect(connection_status_map)}")
    {:reconnect, state}
  end

  def handle_event(%{"e" => "trade"} = event, state) do
    trade_event = %Streamer.Binance.TradeEvent{
      :event_type => event["e"],
      :event_time => event["E"],
      :symbol => event["s"],
      :trade_id => event["t"],
      :price => event["p"],
      :quantity => event["q"],
      :buyer_order_id => event["b"],
      :seller_order_id => event["a"],
      :trade_time => event["T"],
      :buyer_market_maker => event["m"]
    }

    # Logger.debug("Trade event recieved: #{inspect(trade_event)}")

    Phoenix.PubSub.broadcast(
      Streamer.PubSub,
      "trade_events:#{state.symbol}",
      trade_event
    )
  end
end
