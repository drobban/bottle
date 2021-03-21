defmodule Trades.Leader do
  use GenServer, restart: :temporary

  require Logger
  alias Decimal, as: D
  D.Context.set(%D.Context{D.Context.get() | precision: 9})

  @short 60 * 10
  @long 60 * 180
  @trend 3600 * 24

  defmodule Mas do
    defstruct short_ma: Deque.new(2),
              long_ma: Deque.new(2),
              trend_ma: Deque.new(2),
              short_events: Deque.new(1000),
              long_events: Deque.new(50_000),
              trend_events: Deque.new(100_000),
              short_acc: 0,
              long_acc: 0,
              trend_acc: 0,
              trend_deltas: Deque.new(100),
              trades_bucket: %{ts: 0, price: 0, count: 0},
              short_bucket: %{ts: 0, price: 0, count: 0},
              long_bucket: %{ts: 0, price: 0, count: 0},
              trend_bucket: %{ts: 0, price: 0, count: 0}
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
    Logger.notice("Starting link: #{__MODULE__}-#{symbol}")

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

  def handle_info(%Streamer.Binance.TradeEvent{trade_time: t_time, price: price}, state) do
    symbol = String.downcase(state.symbol)
    mas = state.mas
    td_now = DateTime.now!("Etc/UTC")
    ts_now = DateTime.to_unix(td_now, :second)

    {new_short, short_events, short_bucket} =
      event_append(mas.short_events, mas.short_bucket, t_time, price)

    {new_long, long_events, long_bucket} =
      event_append(mas.long_events, mas.long_bucket, t_time, price)

    {new_trend, trend_events, trend_bucket} =
      event_append(mas.trend_events, mas.trend_bucket, t_time, price)

    mas = %Mas{
      mas
      | short_bucket: short_bucket,
        long_bucket: long_bucket,
        trend_bucket: trend_bucket
    }

    ma_data =
      if new_short or new_long or new_trend do
        {rm_short_acc, short_events} =
          sum_drop_while(short_events, 0, fn e ->
            [time, _price] = e
            time < ts_now - @short
          end)

        {short_acc, sma} = update_ma(short_events, mas.short_acc, rm_short_acc)

        {rm_long_acc, long_events} =
          sum_drop_while(long_events, 0, fn e ->
            [time, _price] = e
            time < ts_now - @long
          end)

        {long_acc, lma} = update_ma(long_events, mas.long_acc, rm_long_acc)

        {rm_trend_acc, trend_events} =
          sum_drop_while(trend_events, 0, fn e ->
            [time, _price] = e
            time < ts_now - @trend
          end)

        {trend_acc, tma} = update_ma(trend_events, mas.trend_acc, rm_trend_acc)

        Phoenix.PubSub.broadcast(
          Streamer.PubSub,
          "ma_events:#{symbol}",
          %{
            short_ma: sma,
            long_ma: lma,
            trend_ma: tma,
            ts: ts_now
          }
        )

        %{
          short_ma: Deque.append(mas.short_ma, [ts_now, sma]),
          long_ma: Deque.append(mas.long_ma, [ts_now, lma]),
          trend_ma: Deque.append(mas.trend_ma, [ts_now, tma]),
          short_events: short_events,
          long_events: long_events,
          trend_events: trend_events,
          short_acc: short_acc,
          long_acc: long_acc,
          trend_acc: trend_acc
        }
      else
        nil
      end

    mas =
      if !is_nil(ma_data) do
        %Mas{
          mas
          | short_ma: ma_data.short_ma,
            long_ma: ma_data.long_ma,
            trend_ma: ma_data.trend_ma,
            short_events: ma_data.short_events,
            long_events: ma_data.long_events,
            trend_events: ma_data.trend_events,
            short_acc: ma_data.short_acc,
            long_acc: ma_data.long_acc,
            trend_acc: ma_data.trend_acc
        }
      else
        mas
      end

    %{trend: trend, trade: signal, trend_deltas: new_deltas} = conclusion(mas)

    case state do
      %State{trend: old_trend} when old_trend != trend ->
        Logger.info(
          "#{state.symbol} #{inspect(trend)} - #{inspect(signal)} - #{state.mas.short_events.size} . #{
            state.mas.long_events.size
          } . #{state.mas.trend_events.size}"
        )

      %State{signal: old_signal} when old_signal != signal ->
        Logger.info(
          "#{state.symbol} #{inspect(trend)} - #{inspect(signal)} - #{state.mas.short_events.size} . #{
            state.mas.long_events.size
          } . #{state.mas.trend_events.size}"
        )

      _ ->
        None
    end

    {:noreply,
     %State{state | trend: trend, signal: signal, mas: %{mas | trend_deltas: new_deltas}}}
  end

  defp update_ma(events, events_acc, rm_events_acc) do
    {[_time, price], _q} = Deque.pop(events)
    new_acc = D.sub(D.add(events_acc, price), rm_events_acc)
    new_ma = D.div(new_acc, events.size)

    {new_acc, new_ma}
  end

  defp calc_delta([current_ma, prev_ma]) do
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

  defp conclusion(%Mas{
         trend_ma: trend_ma,
         trend_deltas: trend_deltas,
         short_ma: short_ma,
         long_ma: long_ma
       }) do
    a_mas = Enum.reverse(Enum.to_list(trend_ma))

    ma_delta =
      case a_mas do
        [_, _] -> calc_delta(a_mas)
        _default -> [0, D.new(0)]
      end

    trend_deltas = Deque.append(trend_deltas, ma_delta)

    avg =
      if trend_deltas.size > 1 do
        D.div(
          Enum.reduce(trend_deltas, 0, fn [_time, delta], acc -> D.add(acc, delta) end),
          trend_deltas.size
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

    {[_time, short_ma], _q} =
      if short_ma.size > 0 do
        Deque.pop(short_ma)
      else
        {[0, 0], None}
      end

    {[_time, long_ma], _q} =
      if long_ma.size > 0 do
        Deque.pop(long_ma)
      else
        {[0, 0], None}
      end

    signal =
      cond do
        D.gt?(short_ma, long_ma) -> :sell
        D.lt?(short_ma, long_ma) -> :buy
        true -> :neutral
      end

    %{trend: trend, trade: signal, trend_deltas: trend_deltas}
  end

  defp event_append(coll, bucket, ts, price) do
    # convert from milli to seconds
    ts = div(ts, 1000)

    data =
      cond do
        ts != bucket.ts and bucket.count > 0 ->
          {true, Deque.append(coll, [bucket.ts, D.div(bucket.price, bucket.count)]),
           %{ts: ts, price: price, count: 1}}

        ts == bucket.ts ->
          {false, coll, %{bucket | price: D.add(price, bucket.price), count: bucket.count + 1}}

        bucket.count == 0 ->
          {false, coll, %{bucket | price: price, count: 1, ts: ts}}
      end

    data
  end

  def sum_drop_while(deque, acc, fun) do
    {x, new_deque} = Deque.popleft(deque)

    {acc, popped_que} =
      if !is_nil(x) do
        if fun.(x) do
          [_time, price] = x
          acc = D.add(acc, price)
          sum_drop_while(new_deque, acc, fun)
        else
          {acc, deque}
        end
      else
        {acc, deque}
      end

    {acc, popped_que}
  end
end
