defmodule FinpilotWeb.Auth do
  import Plug.Conn

  def init(opts) do
    opts
  end

  def call(%Plug.Conn{} = conn, _opts) do
    conn
  end

end
