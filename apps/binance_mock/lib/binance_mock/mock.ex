defmodule BinanceMock.Mock do
  use GenServer
  require Logger
  alias Decimal, as: D

  # fake_order_id mocked ID for order
  # subscriptions holds information for every subscription made to streamer.
  # order_books holds info about every ticker
  defmodule State do
    defstruct order_books: %{}, subscriptions: [], fake_order_id: 1
  end

  defmodule OrderBook do
    defstruct buy_side: [], sell_side: [], historical: []
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_args) do
    {:ok, %State{}}
  end

  # Interface

  def get_exchange_info() do
    Binance.get_exchange_info()
  end

  def order_limit_buy(symbol, quantity, price, "GTC") do
    order_limit(symbol, quantity, price, "BUY")
  end

  def order_limit_sell(symbol, quantity, price, "GTC") do
    order_limit(symbol, quantity, price, "SELL")
  end

  def get_order(symbol, time, order_id) do
    GenServer.call(__MODULE__, {:get_order, symbol, time, order_id})
  end

  # Helper functions

  defp order_limit(symbol, quantity, price, side) do
    quantity = Float.parse("#{quantity}") |> elem(0)
    symbol = String.downcase(symbol)
    %Binance.Order{} = fake_order = generate_fake_order(symbol, quantity, price, side)

    GenServer.cast(__MODULE__, {:add_order, fake_order})

    {:ok, convert_order_to_order_response(fake_order)}
  end

  defp subscribe_to_topic(symbol, subscriptions) do
    symbol = String.downcase(symbol)
    stream_name = "trade_events:#{symbol}"

    case Enum.member?(subscriptions, symbol) do
      false ->
        Logger.debug("BinanceMock subscribing to #{stream_name}")

        Phoenix.PubSub.subscribe(
          Streamer.PubSub,
          stream_name
        )

        [symbol | subscriptions]

      _ ->
        subscriptions
    end
  end

  defp add_order(%Binance.Order{symbol: symbol} = order, order_books) do
    symbol = String.downcase(symbol)

    order_book =
      Map.get(
        order_books,
        :"#{symbol}",
        %OrderBook{}
      )

    order_book =
      case order.side do
        "SELL" ->
          Map.replace!(
            order_book,
            :sell_side,
            [order | order_book.sell_side]
            |> Enum.sort(&D.lt?(D.cast(&1.price), D.cast(&2.price)))
          )

        _default ->
          Map.replace!(
            order_book,
            :buy_side,
            [order | order_book.buy_side]
            |> Enum.sort(&D.gt?(D.cast(&1.price), D.cast(&2.price)))
          )
      end

    Map.put(order_books, :"#{symbol}", order_book)
  end

  defp generate_fake_order(symbol, quantity, price, side)
       when is_binary(symbol) and is_float(quantity) and is_float(price) and
              (side == "SELL" or side == "BUY") do
    timestamp_now = :os.system_time(:millisecond)
    order_id = GenServer.call(__MODULE__, :generate_id)
    client_order_id = :crypto.hash(:md5, "#{order_id}") |> Base.encode16()

    Binance.Order.new(%{
      symbol: symbol,
      order_id: order_id,
      client_order_id: client_order_id,
      price: Float.to_string(price),
      orig_qty: Float.to_string(quantity),
      executed_qty: "0.00000000",
      cummulative_quote_qty: "0.00000000",
      status: "NEW",
      time_in_force: "GTC",
      type: "LIMIT",
      side: side,
      stop_price: "0.00000000",
      iceberg_qty: "0.00000000",
      time: timestamp_now,
      update_time: timestamp_now,
      is_working: true
    })
  end

  defp convert_order_to_order_response(%Binance.Order{} = order) do
    %{struct(Binance.OrderResponse, order |> Map.to_list()) | transact_time: order.time}
  end

  defp convert_order_to_event(%Binance.Order{} = order, time) do
    %Streamer.Binance.TradeEvent{
      event_type: order.type,
      event_time: time - 1,
      symbol: order.symbol,
      trade_id: Integer.floor_div(time, 1000),
      price: order.price,
      quantity: order.orig_qty,
      buyer_order_id: order.order_id,
      seller_order_id: order.order_id,
      trade_time: time - 1,
      buyer_market_maker: false
    }
  end

  defp broadcast_trade_event(%Streamer.Binance.TradeEvent{} = trade_event) do
    symbol = String.downcase(trade_event.symbol)
    Phoenix.PubSub.broadcast(Streamer.PubSub, "trade_events:#{symbol}", trade_event)
  end

  # Signalhandling

  def handle_cast(
        {:add_order, %Binance.Order{symbol: symbol} = order},
        %State{
          order_books: order_books,
          subscriptions: sub
        } = state
      ) do
    symbol = String.downcase(symbol)
    new_sub = subscribe_to_topic(symbol, sub)
    updated_order_books = add_order(order, order_books)
    {:noreply, %{state | order_books: updated_order_books, subscriptions: new_sub}}
  end

  def handle_call(:generate_id, _from, %State{fake_order_id: id} = state) do
    {:reply, id + 1, %{state | fake_order_id: id + 1}}
  end

  def handle_call(
        {:get_order, symbol, time, order_id},
        _from,
        %State{order_books: orders} = state
      ) do
    symbol = String.downcase(symbol)
    order_book = Map.get(orders, :"#{symbol}", %OrderBook{})

    order =
      (order_book.buy_side ++ order_book.sell_side ++ order_book.historical)
      |> Enum.find(&(&1.symbol == symbol and &1.time == time and &1.order_id == order_id))

    {:reply, {:ok, order}, state}
  end

  def handle_info(
        %Streamer.Binance.TradeEvent{} = trade_event,
        %{order_books: order_books} = state
      ) do
    downcased_symbol = String.downcase(trade_event.symbol)
    order_book = Map.get(order_books, :"#{downcased_symbol}", %OrderBook{})

    filled_buy_orders =
      order_book.buy_side
      |> Enum.take_while(&D.lt?(D.cast(trade_event.price), D.cast(&1.price)))
      |> Enum.map(&Map.replace!(&1, :status, "FILLED"))

    filled_sell_orders =
      order_book.sell_side
      |> Enum.take_while(&D.gt?(D.cast(trade_event.price), D.cast(&1.price)))
      |> Enum.map(&Map.replace!(&1, :status, "FILLED"))

    if !Enum.empty?(filled_buy_orders ++ filled_sell_orders) do
      Logger.info("transaction performed")
      Logger.debug("#{inspect(filled_buy_orders ++ filled_sell_orders, pretty: true)}")
    end

    (filled_buy_orders ++ filled_sell_orders)
    |> Enum.map(&convert_order_to_event(&1, trade_event.event_time))
    |> Enum.map(&broadcast_trade_event/1)

    remaining_buy_orders =
      order_book.buy_side
      |> Enum.drop(length(filled_buy_orders))

    remaining_sell_orders =
      order_book.sell_side
      |> Enum.drop(length(filled_sell_orders))

    order_books =
      Map.replace!(
        order_books,
        :"#{downcased_symbol}",
        %{
          buy_side: remaining_buy_orders,
          sell_side: remaining_sell_orders,
          historical: filled_buy_orders ++ filled_sell_orders ++ order_book.historical
        }
      )

    {:noreply, %{state | order_books: order_books}}
  end
end
