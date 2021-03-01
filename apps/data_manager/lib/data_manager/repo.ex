defmodule DataManager.Repo do
  use Ecto.Repo,
    otp_app: :data_manager,
    adapter: Ecto.Adapters.Postgres
end
