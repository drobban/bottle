defmodule Plot.Subscriber do
  use GenServer, restart: :temporary
  require Decimal
  import Gnuplot

  require Logger

  defmodule State do
    defstruct [:symbol, :trades, :ma_short, :ma_long, :ma_trend]
  end

  defp set_tick() do
    Process.send_after(self(), :plot, 5_000)
  end

  def start_link(symbol) do
    Logger.debug("Starting link: #{__MODULE__}-#{symbol}")

    GenServer.start_link(
      __MODULE__,
      %State{
        symbol: symbol,
        trades: [[0, 0]],
        ma_short: [[0, 0]],
        ma_long: [[0, 0]],
        ma_trend: [[0, 0]]
      },
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

    if !Enum.empty?(state.trades) do
      try do
        _stat =
          plot(
            [
              [:set, :term, :pngcairo],
              [:set, :output, "/tmp/#{state.symbol}.png"],
              [:set, :title, "#{state.symbol}"],
              [:set, :key, :left, :top],
              plots([
                [
                  "-",
                  :with,
                  :lines,
                  :title,
                  "Binance trade since #{DateTime.to_iso8601(dt)}"
                ],
                ["-", :with, :lines, :title, "MA short"],
                ["-", :with, :lines, :title, "MA long"],
                ["-", :with, :lines, :title, "MA trend"]
              ])
            ],
            [
              Enum.to_list(state.trades),
              Enum.to_list(state.ma_short),
              Enum.to_list(state.ma_long),
              Enum.to_list(state.ma_trend)
            ]
          )
      rescue
        e in MatchError -> inspect(e)
      end
    end

    set_tick()
    {:noreply, state}
  end

  def handle_info(
        %{short_ma: short_ma, long_ma: long_ma, trend_ma: trend_ma, ts: ts},
        state
      ) do
    short = [[ts, Decimal.to_float(short_ma)]] ++ state.ma_short
    long = [[ts, Decimal.to_float(long_ma)]] ++ state.ma_long
    trend = [[ts, Decimal.to_float(trend_ma)]] ++ state.ma_trend

    ma_short =
      Enum.filter(short, fn e ->
        [time, _price] = e
        dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)
        time > DateTime.to_unix(dt, :millisecond)
      end)

    ma_long =
      Enum.filter(long, fn e ->
        [time, _price] = e
        dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)
        time > DateTime.to_unix(dt, :millisecond)
      end)

    ma_trend =
      Enum.filter(trend, fn e ->
        [time, _price] = e
        dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)
        time > DateTime.to_unix(dt, :millisecond)
      end)

    new_state = %{state | ma_short: ma_short, ma_long: ma_long, ma_trend: ma_trend}

    {:noreply, new_state}
  end

  def handle_info(%Streamer.Binance.TradeEvent{trade_time: t_time, price: price}, state) do
    {price, _} = Float.parse(price)
    t = [[t_time, price]] ++ state.trades

    trades =
      Enum.filter(t, fn e ->
        [time, _price] = e
        dt = DateTime.add(DateTime.now!("Etc/UTC"), -(12 * 3600), :second)
        time > DateTime.to_unix(dt, :millisecond)
      end)

    new_state = %{state | trades: trades}

    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
