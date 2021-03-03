defmodule DataManager do
  @moduledoc """
  Documentation for `DataManager`.
  """

  alias DataManager.Record.DynamicRecordSupervisor

  defdelegate start_recording(symbol), to: DynamicRecordSupervisor
  defdelegate stop_recording(symbol), to: DynamicRecordSupervisor
  # defdelegate start_sim_stream(symbol, from, to), to: DynamicRecordSupervisor
  # defdelegate stop_sim_stream(symbol, from, to), to: DynamicRecordSupervisor
end
