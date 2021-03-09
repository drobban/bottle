defmodule Trades.Leader do
  use GenServer, restart: :temporary

  require Logger
  alias Decimal, as: D

  @short 60 * 3
  @long 60 * 15
  @trend 3600 * 3

  defmodule Mas do
    defstruct short_ma: [[0, 0]],
              long_ma: [[0, 0]],
              trend_ma: [[0, 0]],
              short_events: [[0, 0]],
              long_events: [[0, 0]],
              trend_events: [[0, 0]],
              short_acc: 0,
              long_acc: 0,
              trend_acc: 0
  end

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
      :symbol,
      :mas
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

  def init(%State{symbol: symbol} = state) do
    symbol = String.downcase(symbol)
    new_state = %{state | mas: %Mas{}}

    Streamer.start_streaming(symbol)

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade_events:#{symbol}"
    )

    {:ok, new_state}
  end

  def handle_info(event, state) do
    mas = state.mas
    td_now = DateTime.now!("Etc/UTC")

    {ma_short, short_events, short_acc} =
      update_ma(td_now, event, {mas.short_ma, mas.short_events, mas.short_acc}, @short)

    {ma_long, long_events, long_acc} =
      update_ma(td_now, event, {mas.long_ma, mas.long_events, mas.long_acc}, @long)

    {ma_trend, trend_events, trend_acc} =
      update_ma(td_now, event, {mas.trend_ma, mas.trend_events, mas.trend_acc}, @trend)

    new_mas = %Mas{
      short_ma: ma_short,
      short_acc: short_acc,
      short_events: short_events,
      long_ma: ma_long,
      long_acc: long_acc,
      long_events: long_events,
      trend_ma: ma_trend,
      trend_acc: trend_acc,
      trend_events: trend_events
    }

    new_state = %{state | mas: new_mas}

    Phoenix.PubSub.broadcast(
      Streamer.PubSub,
      "ma_events:#{state.symbol}",
      %{
        short_ma: new_mas.short_ma,
        long_ma: new_mas.long_ma,
        trend_ma: new_mas.trend_ma,
        ts: DateTime.to_unix(td_now, :millisecond)
      }
    )

    {:noreply, new_state}
  end

  defp update_ma(
         td_now,
         %Streamer.Binance.TradeEvent{trade_time: t_time, price: price},
         {ma, events, acc},
         period
       ) do
    {price, _} = Float.parse(price)
    h_limit = DateTime.add(td_now, -period, :second)
    ts = DateTime.to_unix(h_limit, :millisecond)

    events = events ++ [[t_time, price]]

    {old_events, new_events} =
      Enum.split_with(events, fn e ->
        [time, _price] = e
        time < ts
      end)

    old_events_acc = Enum.reduce(old_events, 0, fn [_t, p], acc -> p + acc end)

    new_acc = acc + price - old_events_acc
    new_ma = new_acc / Enum.count(new_events)

    {new_ma, new_events, new_acc}
  end
end
