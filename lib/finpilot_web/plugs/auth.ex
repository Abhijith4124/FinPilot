defmodule FinpilotWeb.Auth do
  import Plug.Conn

  def init(opts) do
    opts
  end

  def call(%Plug.Conn{} = conn, _opts) do
    case get_session(conn, :user_id) do
      user_id ->
        assign(conn, :current_user, user_id)
    end
    conn
  end

end
