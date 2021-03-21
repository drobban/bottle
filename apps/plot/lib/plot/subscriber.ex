defmodule Plot.Subscriber do
  use GenServer, restart: :temporary
  require Decimal
  import Gnuplot

  require Logger
  alias Decimal, as: D
  D.Context.set(%D.Context{D.Context.get() | precision: 9})

  defmodule State do
    defstruct symbol: None,
              trades: Deque.new(1_000_000),
              ma_short: Deque.new(1_000_000),
              ma_long: Deque.new(1_000_000),
              ma_trend: Deque.new(1_000_000),
              trades_bucket: %{ts: 0, price: 0, count: 1},
              short_bucket: %{ts: 0, price: 0, count: 1},
              long_bucket: %{ts: 0, price: 0, count: 1},
              trend_bucket: %{ts: 0, price: 0, count: 1}
  end

  defp set_tick() do
    _timer = Process.send_after(self(), :plot, 5_000)
  end

  def start_link(symbol) do
    Logger.notice("Starting link: #{__MODULE__}-#{symbol}")

    GenServer.start_link(
      __MODULE__,
      %State{symbol: symbol},
      name: :"#{__MODULE__}-#{symbol}"
    )
  end

  def init(%State{symbol: symbol, trades: _trades} = state) do
    symbol = String.downcase(symbol)
    Streamer.start_streaming(symbol)

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade_events:#{symbol}"
    )

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "ma_events:#{symbol}"
    )

    set_tick()

    {:ok, state}
  end

  def handle_info(:plot, state) do
    dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)

    plots_data = [
      [
        [
          "-",
          :with,
          :lines,
          :title,
          "Binance trade since #{DateTime.to_iso8601(dt)}"
        ],
        state.trades
      ],
      [
        ["-", :with, :lines, :title, "MA short"],
        state.ma_short
      ],
      [
        ["-", :with, :lines, :title, "MA long"],
        state.ma_long
      ],
      [
        ["-", :with, :lines, :title, "MA trend"],
        state.ma_trend
      ]
    ]

    available =
      Enum.filter(plots_data, fn [_title, data] ->
        data.size > 1
      end)
      |> Enum.reduce(%{titles: [], data: []}, fn [title, points], m ->
        %{m | titles: m.titles ++ [title], data: m.data ++ [Enum.to_list(points)]}
      end)

    if state.trades.size > 0 do
      try do
        _stat =
          plot(
            [
              [:set, :term, :pngcairo],
              [:set, :output, "/tmp/#{state.symbol}.png"],
              [:set, :title, "#{state.symbol}"],
              [:set, :key, :left, :top],
              plots(available.titles)
            ],
            available.data
          )
      rescue
        e in MatchError -> "Data: #{inspect(e)}"
      end
    end

    _timer = set_tick()
    {:noreply, state}
  end

  def handle_info(
        %{short_ma: short_ma, long_ma: long_ma, trend_ma: trend_ma, ts: ts},
        state
      ) do
    ts = ts * 1000

    {short, short_bucket} =
      event_append(state.ma_short, state.short_bucket, ts, D.to_float(short_ma))

    {long, long_bucket} = event_append(state.ma_long, state.long_bucket, ts, D.to_float(long_ma))

    {trend, trend_bucket} =
      event_append(state.ma_trend, state.trend_bucket, ts, D.to_float(trend_ma))

    dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)
    ts = DateTime.to_unix(dt, :second)

    ma_short = drop_while(short, fn [time, _price] -> time < ts end)
    ma_long = drop_while(long, fn [time, _price] -> time < ts end)
    ma_trend = drop_while(trend, fn [time, _price] -> time < ts end)

    new_state = %{
      state
      | ma_short: ma_short,
        ma_long: ma_long,
        ma_trend: ma_trend,
        short_bucket: short_bucket,
        long_bucket: long_bucket,
        trend_bucket: trend_bucket
    }

    {:noreply, new_state}
  end

  def handle_info(%Streamer.Binance.TradeEvent{trade_time: t_time, price: price}, state) do
    {price, _} = Float.parse(price)
    {t, bucket} = event_append(state.trades, state.trades_bucket, t_time, price)
    dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)
    ts = DateTime.to_unix(dt, :second)

    trades = drop_while(t, fn [time, _price] -> time < ts end)

    new_state = %{state | trades: trades, trades_bucket: bucket}

    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    case msg do
      {_port, {:exit_status, _}} -> None
      msg_umatch -> Logger.warn("#{inspect(state.symbol)} - #{inspect(msg_umatch)}")
    end

    {:noreply, state}
  end

  defp event_append(coll, bucket, ts, price) do
    # convert from milli to seconds
    current_ts = div(ts, 1000)

    {new_coll, bucket} =
      cond do
        current_ts != bucket.ts ->
          {Deque.append(coll, [bucket.ts, bucket.price / bucket.count]),
           %{ts: current_ts, price: price, count: 1}}

        current_ts == bucket.ts ->
          {coll, %{bucket | price: price + bucket.price, count: bucket.count + 1}}
      end

    {new_coll, bucket}
  end

  def drop_while(deque, fun) do
    {x, new_deque} = Deque.popleft(deque)

    popped_que =
      if !is_nil(x) do
        if fun.(x) do
          drop_while(new_deque, fun)
        else
          deque
        end
      else
        deque
      end

    popped_que
  end
end
