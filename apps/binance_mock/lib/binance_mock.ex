defmodule BinanceMock do
  @moduledoc """
  Documentation for `BinanceMock`.

  Implements

  get_exchange_info/0
  order_limit_buy/4
  order_limit_sell/4
  get_order/3
  """
  alias BinanceMock.Mock

  defdelegate get_exchange_info(), to: Mock
  defdelegate order_limit_buy(symbol, quantity, price, time_in_force), to: Mock
  defdelegate order_limit_sell(symbol, quantity, price, time_in_force), to: Mock
  defdelegate get_order(symbol, time, order_id), to: Mock
end
