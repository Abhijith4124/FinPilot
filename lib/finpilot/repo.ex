defmodule Finpilot.Repo do
  use Ecto.Repo,
    otp_app: :finpilot,
    adapter: Ecto.Adapters.Postgres
end
