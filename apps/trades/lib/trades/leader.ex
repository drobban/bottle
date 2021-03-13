defmodule Trades.Leader do
  use GenServer, restart: :temporary

  require Logger
  alias Decimal, as: D
  D.Context.set(%D.Context{D.Context.get() | precision: 9})

  @short 60 * 10
  @long 60 * 120
  @trend 3600 * 24
  @delta_limit 10

  defmodule Mas do
    defstruct short_ma: [[0, Decimal.new(0)]],
              long_ma: [[0, Decimal.new(0)]],
              trend_ma: [[0, Decimal.new(0)]],
              short_events: [[0, Decimal.new(0)]],
              long_events: [[0, Decimal.new(0)]],
              trend_events: [[0, Decimal.new(0)]],
              short_acc: 0,
              long_acc: 0,
              trend_acc: 0,
              trend_deltas: [[0, Decimal.new(0)]]
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
      :mas,
      :trend,
      :signal
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

  def start_link(symbol) do
    Logger.debug("Starting link: #{__MODULE__}-#{symbol}")

    GenServer.start_link(
      __MODULE__,
      %State{
        symbol: symbol,
        mas: %Mas{}
      },
      name: :"#{__MODULE__}-#{symbol}"
    )
  end

  def init(%State{symbol: symbol, mas: _mas} = state) do
    symbol = String.downcase(symbol)

    Streamer.start_streaming(symbol)

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade_events:#{symbol}"
    )

    {:ok, state}
  end

  def handle_info(event, state) do
    symbol = String.downcase(state.symbol)
    mas = state.mas
    td_now = DateTime.now!("Etc/UTC")

    {ma_short, short_events, short_acc} =
      update_ma(td_now, event, {mas.short_ma, mas.short_events, mas.short_acc}, @short)

    {ma_long, long_events, long_acc} =
      update_ma(td_now, event, {mas.long_ma, mas.long_events, mas.long_acc}, @long)

    {ma_trend, trend_events, trend_acc} =
      update_ma(td_now, event, {mas.trend_ma, mas.trend_events, mas.trend_acc}, @trend)

    new_mas = %{
      mas
      | short_ma: ma_short,
        short_acc: short_acc,
        short_events: short_events,
        long_ma: ma_long,
        long_acc: long_acc,
        long_events: long_events,
        trend_ma: ma_trend,
        trend_acc: trend_acc,
        trend_events: trend_events
    }

    %{trend: trend, trade: signal, trend_deltas: new_deltas} = conclusion(new_mas, @delta_limit)

    case state do
      %State{trend: old_trend} when old_trend != trend ->
        Logger.debug("#{inspect(trend)} - #{inspect(signal)}")

      %State{signal: old_signal} when old_signal != signal ->
        Logger.debug("#{inspect(trend)} - #{inspect(signal)}")

      _ ->
        None
    end

    new_state = %{
      state
      | trend: trend,
        signal: signal,
        mas: %{new_mas | trend_deltas: new_deltas}
    }

    [_, sma] = Enum.at(new_mas.short_ma, -1)
    [_, lma] = Enum.at(new_mas.long_ma, -1)
    [_, tma] = Enum.at(new_mas.trend_ma, -1)

    Phoenix.PubSub.broadcast(
      Streamer.PubSub,
      "ma_events:#{symbol}",
      %{
        short_ma: sma,
        long_ma: lma,
        trend_ma: tma,
        ts: DateTime.to_unix(td_now, :millisecond)
      }
    )

    {:noreply, new_state}
  end

  defp calc_delta([prev_ma, current_ma]) do
    [current_time, current_price] = current_ma
    [prev_time, prev_price] = prev_ma
    y = D.sub(current_time, prev_time)
    x = D.sub(current_price, prev_price)

    delta =
      if D.eq?(y, 0) do
        D.new(0)
      else
        D.div(x, y)
      end

    [current_time, delta]
  end

  defp conclusion(%Mas{} = mas, time_limit) do
    td_now = DateTime.now!("Etc/UTC")
    h_limit = DateTime.add(td_now, -time_limit, :second)
    ts = DateTime.to_unix(h_limit, :millisecond)

    {_, a_mas} = Enum.split(mas.trend_ma, -2)

    ma_delta =
      case a_mas do
        [_, _] -> calc_delta(a_mas)
        _default -> [0, Decimal.new(0)]
      end

    trend_deltas = mas.trend_deltas ++ [ma_delta]

    {_old_deltas, new_deltas} =
      Enum.split_with(trend_deltas, fn e ->
        [time, _avg] = e
        time < ts
      end)

    avg =
      if Enum.count(new_deltas) > 1 do
        D.div(
          Enum.reduce(new_deltas, 0, fn [_time, delta], acc -> D.add(acc, delta) end),
          Enum.count(new_deltas)
        )
      else
        D.new(0)
      end

    trend =
      cond do
        D.gt?(avg, "0") -> :bull
        D.lt?(avg, "0") -> :bear
        true -> :neutral
      end

    [_t, short_ma] = Enum.at(mas.short_ma, -1)
    [_t, long_ma] = Enum.at(mas.long_ma, -1)

    signal =
      cond do
        D.gt?(short_ma, long_ma) -> :sell
        D.lt?(short_ma, long_ma) -> :buy
        true -> :neutral
      end

    %{trend: trend, trade: signal, trend_deltas: new_deltas}
  end

  defp update_ma(
         td_now,
         %Streamer.Binance.TradeEvent{trade_time: t_time, price: price},
         {mas, events, acc},
         period
       ) do
    price = Decimal.new(price)
    h_limit = DateTime.add(td_now, -period, :second)
    ts = DateTime.to_unix(h_limit, :millisecond)

    events = events ++ [[t_time, price]]

    {old_events, new_events} =
      Enum.split_with(events, fn e ->
        [time, _price] = e
        time < ts
      end)

    old_events_acc = Enum.reduce(old_events, 0, fn [_t, p], acc -> D.add(p, acc) end)

    new_acc = Decimal.sub(Decimal.add(acc, price), old_events_acc)

    mas = mas ++ [[t_time, Decimal.div(new_acc, Enum.count(new_events))]]

    {_old_mas, new_mas} =
      Enum.split_with(mas, fn e ->
        [time, _price] = e
        time < ts
      end)

    {new_mas, new_events, new_acc}
  end
end
